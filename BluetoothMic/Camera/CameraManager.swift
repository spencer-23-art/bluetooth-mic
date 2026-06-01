import AVFoundation
import UIKit
import Photos

enum CameraPosition {
    case back, front
}

enum VideoQuality: String, CaseIterable {
    case uhd4K = "4K"
    case fullHD = "1080p"
    case hd = "720p"
    
    var preset: AVCaptureSession.Preset {
        switch self {
        case .uhd4K: return .hd4K3840x2160
        case .fullHD: return .hd1920x1080
        case .hd: return .hd1280x720
        }
    }
}

enum FrameRate: Int, CaseIterable {
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120
    
    var displayName: String {
        "\(rawValue)Hz"
    }
}

protocol CameraManagerDelegate: AnyObject {
    func cameraDidStartRecording()
    func cameraDidStopRecording(url: URL?, error: Error?)
    func cameraDidCapturePhoto(_ image: UIImage?)
    func cameraSessionConfigured()
    func cameraError(_ error: Error)
}

class CameraManager: NSObject {
    weak var delegate: CameraManagerDelegate?
    
    let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private(set) var currentPosition: CameraPosition = .back
    private(set) var currentQuality: VideoQuality = .fullHD
    private(set) var currentFrameRate: FrameRate = .fps60
    private(set) var isRecording = false
    private(set) var isTorchOn = false
    
    private var outputURL: URL?
    
    // MARK: - Session Configuration
    
    func configure() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }
    
    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = currentQuality.preset
        
        // Add video input
        if let videoDevice = bestVideoDevice(for: currentPosition) {
            do {
                let input = try AVCaptureDeviceInput(device: videoDevice)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                    videoDeviceInput = input
                }
                
                // Configure video device for best quality
                try videoDevice.lockForConfiguration()
                
                // Enable video stabilization will be set per-connection
                if videoDevice.isSmoothAutoFocusSupported {
                    videoDevice.isSmoothAutoFocusEnabled = true
                }
                if videoDevice.isAutoFocusRangeRestrictionSupported {
                    videoDevice.autoFocusRangeRestriction = .none
                }
                
                // Set frame rate
                configureFrameRate(videoDevice, desiredFPS: Double(currentFrameRate.rawValue))
                
                videoDevice.unlockForConfiguration()
            } catch {
                print("[CameraManager] Video input error: \(error)")
            }
        }
        
        // Add audio input
        addAudioInput()
        
        // Add movie output
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }
        
        // Add photo output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        
        captureSession.commitConfiguration()
        
        // Configure connection settings after committing configuration so connections are established
        if let connection = movieOutput.connection(with: .video) {
            // Configure video stabilization
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .cinematic
            }
            // Enable video mirroring for front camera
            if currentPosition == .front && connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
            
            // Prefer HEVC
            if movieOutput.availableVideoCodecTypes.contains(.hevc) {
                let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc]
                movieOutput.setOutputSettings(settings, for: connection)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cameraSessionConfigured()
        }
    }
    
    func addAudioInput() {
        // Remove existing audio input
        if let existingInput = audioDeviceInput {
            captureSession.removeInput(existingInput)
        }
        
        // The audio session should already be configured by BluetoothAudioManager
        // to route to bluetooth. We just need to add the default audio device.
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("[CameraManager] No audio device available")
            return
        }
        
        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
                audioDeviceInput = audioInput
            }
        } catch {
            print("[CameraManager] Audio input error: \(error)")
        }
    }
    
    // MARK: - Session Control
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
    
    // MARK: - Recording
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Re-add audio input to pick up bluetooth route changes
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.addAudioInput()
            self.captureSession.commitConfiguration()
            
            let tempDir = NSTemporaryDirectory()
            let fileName = "BT_\(Date().timeIntervalSince1970).mov"
            let url = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
            self.outputURL = url
            
            DispatchQueue.main.async {
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }
    
    // MARK: - Photo Capture
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings.photoQualityPrioritization = .quality
        }
        
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - Camera Controls
    
    func switchCamera() {
        guard !isRecording else { return }
        currentPosition = (currentPosition == .back) ? .front : .back
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            // Remove current video input
            if let currentInput = self.videoDeviceInput {
                self.captureSession.removeInput(currentInput)
            }
            
            // Add new video input
            if let newDevice = self.bestVideoDevice(for: self.currentPosition) {
                do {
                    let newInput = try AVCaptureDeviceInput(device: newDevice)
                    if self.captureSession.canAddInput(newInput) {
                        self.captureSession.addInput(newInput)
                        self.videoDeviceInput = newInput
                    }
                    
                    try newDevice.lockForConfiguration()
                    if newDevice.isSmoothAutoFocusSupported {
                        newDevice.isSmoothAutoFocusEnabled = true
                    }
                    self.configureFrameRate(newDevice, desiredFPS: Double(self.currentFrameRate.rawValue))
                    newDevice.unlockForConfiguration()
                } catch {
                    print("[CameraManager] Switch camera error: \(error)")
                }
            }
            
            // Update movie output connection
            if let connection = self.movieOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .cinematic
                }
                if self.currentPosition == .front && connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
            
            self.captureSession.commitConfiguration()
        }
    }
    
    func setVideoQuality(_ quality: VideoQuality) {
        guard !isRecording, quality != currentQuality else { return }
        currentQuality = quality
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            if self.captureSession.canSetSessionPreset(quality.preset) {
                self.captureSession.sessionPreset = quality.preset
            }
            // Re-apply frame rate after quality change
            if let device = self.videoDeviceInput?.device {
                do {
                    try device.lockForConfiguration()
                    self.configureFrameRate(device, desiredFPS: Double(self.currentFrameRate.rawValue))
                    device.unlockForConfiguration()
                } catch {
                    print("[CameraManager] Frame rate error after quality change: \(error)")
                }
            }
            self.captureSession.commitConfiguration()
        }
    }
    
    func setFrameRate(_ fps: FrameRate) {
        guard !isRecording, fps != currentFrameRate else { return }
        currentFrameRate = fps
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                self.configureFrameRate(device, desiredFPS: Double(fps.rawValue))
                device.unlockForConfiguration()
            } catch {
                print("[CameraManager] Frame rate error: \(error)")
            }
        }
    }
    
    func toggleTorch() {
        guard let device = videoDeviceInput?.device,
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            isTorchOn.toggle()
            device.torchMode = isTorchOn ? .on : .off
            if isTorchOn {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            }
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] Torch error: \(error)")
        }
    }
    
    // MARK: - Focus & Exposure
    
    func focus(at point: CGPoint) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] Focus error: \(error)")
        }
    }
    
    // MARK: - Zoom
    
    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            device.videoZoomFactor = max(1.0, min(factor, maxZoom))
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] Zoom error: \(error)")
        }
    }
    
    var currentZoom: CGFloat {
        return videoDeviceInput?.device.videoZoomFactor ?? 1.0
    }
    
    var maxZoom: CGFloat {
        guard let device = videoDeviceInput?.device else { return 1.0 }
        return min(device.activeFormat.videoMaxZoomFactor, 10.0)
    }
    
    // MARK: - Exposure Compensation
    
    func setExposureCompensation(_ value: Float) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let clamped = max(device.minExposureTargetBias, min(value, device.maxExposureTargetBias))
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] Exposure error: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func bestVideoDevice(for position: CameraPosition) -> AVCaptureDevice? {
        let devicePosition: AVCaptureDevice.Position = position == .back ? .back : .front
        
        // Try to get the best available camera
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: devicePosition
        )
        
        return discoverySession.devices.first
    }
    
    private func configureFrameRate(_ device: AVCaptureDevice, desiredFPS: Double) {
        var bestFormat: AVCaptureDevice.Format?
        var bestFrameRate: AVFrameRateRange?
        
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= desiredFPS {
                    if bestFrameRate == nil || range.maxFrameRate <= (bestFrameRate?.maxFrameRate ?? .greatestFiniteMagnitude) {
                        bestFormat = format
                        bestFrameRate = range
                    }
                }
            }
        }
        
        if bestFormat != nil {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(desiredFPS))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(desiredFPS))
        }
    }
    
    private func saveVideoToLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else {
                print("[CameraManager] Photo library access denied")
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { saved, error in
                if saved {
                    print("[CameraManager] Video saved to library")
                }
                if let error = error {
                    print("[CameraManager] Save error: \(error)")
                }
                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        isRecording = true
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cameraDidStartRecording()
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        isRecording = false
        
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.cameraDidStopRecording(url: nil, error: error)
            }
            return
        }
        
        saveVideoToLibrary(url: outputFileURL)
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cameraDidStopRecording(url: outputFileURL, error: nil)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            delegate?.cameraDidCapturePhoto(nil)
            return
        }
        
        let image = UIImage(data: data)
        
        // Save to library
        if let image = image {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized else { return }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                })
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cameraDidCapturePhoto(image)
        }
    }
}
