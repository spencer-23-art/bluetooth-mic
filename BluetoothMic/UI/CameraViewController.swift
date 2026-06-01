import UIKit
import AVFoundation

class CameraViewController: UIViewController {
    
    // MARK: - Properties
    
    private let cameraManager = CameraManager()
    private let audioManager = BluetoothAudioManager.shared
    
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var recordingTimer: Timer?
    private var recordingDuration: TimeInterval = 0
    private var initialZoom: CGFloat = 1.0
    
    // MARK: - UI Elements
    
    private lazy var previewView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    // Top bar
    private lazy var topBar: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .dark)
        let v = UIVisualEffectView(effect: blur)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 16
        v.clipsToBounds = true
        return v
    }()
    
    private lazy var audioDeviceButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        btn.tintColor = .white
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.setTitleColor(.white, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(showAudioDevicePicker), for: .touchUpInside)
        btn.semanticContentAttribute = .forceLeftToRight
        btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        return btn
    }()
    
    private lazy var qualityButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("1080p", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(toggleQuality), for: .touchUpInside)
        return btn
    }()
    
    private lazy var frameRateButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("60Hz", for: .normal)
        btn.setTitleColor(.systemOrange, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(toggleFrameRate), for: .touchUpInside)
        return btn
    }()
    
    private lazy var torchButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        return btn
    }()
    
    private lazy var timerLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "00:00"
        lbl.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        lbl.textColor = .white
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.isHidden = true
        return lbl
    }()
    
    private lazy var recordingDot: UIView = {
        let v = UIView()
        v.backgroundColor = .red
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()
    
    // Bottom bar
    private lazy var bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var recordButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        btn.layer.cornerRadius = 37
        btn.layer.borderWidth = 5
        btn.layer.borderColor = UIColor.white.cgColor
        return btn
    }()
    
    private lazy var recordInner: UIView = {
        let v = UIView()
        v.backgroundColor = .red
        v.layer.cornerRadius = 30
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isUserInteractionEnabled = false
        return v
    }()
    
    private lazy var switchCameraButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "camera.rotate.fill"), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        btn.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        return btn
    }()
    
    private lazy var capturePhotoButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        btn.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        return btn
    }()
    
    // Audio level indicator
    private lazy var audioLevelBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.green.withAlphaComponent(0.8)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 2
        return v
    }()
    
    private lazy var audioLevelContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 2
        return v
    }()
    
    private var audioLevelWidthConstraint: NSLayoutConstraint?
    
    // Focus indicator
    private lazy var focusIndicator: UIView = {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        v.layer.borderColor = UIColor.yellow.cgColor
        v.layer.borderWidth = 2
        v.layer.cornerRadius = 4
        v.isHidden = true
        return v
    }()
    
    // Zoom label
    private lazy var zoomLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "1.0x"
        lbl.font = .systemFont(ofSize: 13, weight: .bold)
        lbl.textColor = .yellow
        lbl.textAlignment = .center
        lbl.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        lbl.layer.cornerRadius = 12
        lbl.clipsToBounds = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.isHidden = true
        return lbl
    }()
    
    // Exposure slider
    private lazy var exposureSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = -3.0
        slider.maximumValue = 3.0
        slider.value = 0.0
        slider.tintColor = .yellow
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(exposureChanged), for: .valueChanged)
        slider.isHidden = true
        slider.alpha = 0.0
        // Rotate to vertical
        slider.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        return slider
    }()
    
    private lazy var sunIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "sun.max.fill"))
        iv.tintColor = .yellow
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupUI()
        setupGestures()
        
        cameraManager.delegate = self
        audioManager.delegate = self
        
        // Configure bluetooth audio FIRST, before camera session
        audioManager.configureAudioSession()
        
        // Request permissions and configure
        requestPermissions()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cameraManager.startSession()
        
        // Only start if microphone permission is already granted
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            audioManager.startLevelMonitoring()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stopSession()
        audioManager.stopLevelMonitoring()
    }
    
    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        // Preview
        view.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        // Focus indicator
        previewView.addSubview(focusIndicator)
        
        // Zoom label
        previewView.addSubview(zoomLabel)
        NSLayoutConstraint.activate([
            zoomLabel.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            zoomLabel.bottomAnchor.constraint(equalTo: previewView.centerYAnchor, constant: -40),
            zoomLabel.widthAnchor.constraint(equalToConstant: 60),
            zoomLabel.heightAnchor.constraint(equalToConstant: 28),
        ])
        
        // Exposure slider (right side, vertical)
        view.addSubview(sunIcon)
        view.addSubview(exposureSlider)
        NSLayoutConstraint.activate([
            sunIcon.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            sunIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -120),
            sunIcon.widthAnchor.constraint(equalToConstant: 20),
            sunIcon.heightAnchor.constraint(equalToConstant: 20),
            
            exposureSlider.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            exposureSlider.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            exposureSlider.widthAnchor.constraint(equalToConstant: 200),
        ])
        
        // Top bar
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            topBar.heightAnchor.constraint(equalToConstant: 48),
        ])
        
        let topStack = UIStackView(arrangedSubviews: [audioDeviceButton, timerLabel, qualityButton, frameRateButton, torchButton])
        topStack.axis = .horizontal
        topStack.distribution = .equalSpacing
        topStack.alignment = .center
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.contentView.addSubview(topStack)
        topBar.contentView.addSubview(recordingDot)
        
        NSLayoutConstraint.activate([
            topStack.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 16),
            topStack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -16),
            topStack.centerYAnchor.constraint(equalTo: topBar.contentView.centerYAnchor),
            
            recordingDot.widthAnchor.constraint(equalToConstant: 8),
            recordingDot.heightAnchor.constraint(equalToConstant: 8),
            recordingDot.trailingAnchor.constraint(equalTo: timerLabel.leadingAnchor, constant: -6),
            recordingDot.centerYAnchor.constraint(equalTo: timerLabel.centerYAnchor),
            
            audioDeviceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
        
        // Audio level
        view.addSubview(audioLevelContainer)
        audioLevelContainer.addSubview(audioLevelBar)
        let levelWidth = audioLevelBar.widthAnchor.constraint(equalToConstant: 0)
        audioLevelWidthConstraint = levelWidth
        
        NSLayoutConstraint.activate([
            audioLevelContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            audioLevelContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            audioLevelContainer.widthAnchor.constraint(equalToConstant: 120),
            audioLevelContainer.heightAnchor.constraint(equalToConstant: 4),
            
            audioLevelBar.leadingAnchor.constraint(equalTo: audioLevelContainer.leadingAnchor),
            audioLevelBar.topAnchor.constraint(equalTo: audioLevelContainer.topAnchor),
            audioLevelBar.bottomAnchor.constraint(equalTo: audioLevelContainer.bottomAnchor),
            levelWidth,
        ])
        
        // Bottom bar
        view.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 140),
        ])
        
        // Record button
        recordButton.addSubview(recordInner)
        bottomBar.addSubview(recordButton)
        bottomBar.addSubview(switchCameraButton)
        bottomBar.addSubview(capturePhotoButton)
        
        NSLayoutConstraint.activate([
            recordButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            recordButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: -10),
            recordButton.widthAnchor.constraint(equalToConstant: 74),
            recordButton.heightAnchor.constraint(equalToConstant: 74),
            
            recordInner.centerXAnchor.constraint(equalTo: recordButton.centerXAnchor),
            recordInner.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            recordInner.widthAnchor.constraint(equalToConstant: 60),
            recordInner.heightAnchor.constraint(equalToConstant: 60),
            
            switchCameraButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            switchCameraButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -40),
            switchCameraButton.widthAnchor.constraint(equalToConstant: 44),
            switchCameraButton.heightAnchor.constraint(equalToConstant: 44),
            
            capturePhotoButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            capturePhotoButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 40),
            capturePhotoButton.widthAnchor.constraint(equalToConstant: 44),
            capturePhotoButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }
    
    private func setupGestures() {
        // Tap to focus
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus))
        previewView.addGestureRecognizer(tapGesture)
        
        // Pinch to zoom
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchZoom))
        previewView.addGestureRecognizer(pinchGesture)
        
        // Double tap to switch camera
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(switchCamera))
        doubleTap.numberOfTapsRequired = 2
        previewView.addGestureRecognizer(doubleTap)
        tapGesture.require(toFail: doubleTap)
        
        // Long press for exposure slider
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.5
        previewView.addGestureRecognizer(longPress)
    }
    
    private func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: cameraManager.captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = previewView.bounds
        previewView.layer.insertSublayer(previewLayer, at: 0)
    }
    
    // MARK: - Permissions
    
    private func requestPermissions() {
        let group = DispatchGroup()
        var cameraGranted = false
        var micGranted = false
        
        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            cameraGranted = granted
            group.leave()
        }
        
        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            micGranted = granted
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            if cameraGranted && micGranted {
                self?.setupPreviewLayer()
                self?.cameraManager.configure()
                self?.audioManager.startLevelMonitoring()
            } else {
                self?.showPermissionAlert()
            }
        }
    }
    
    private func showPermissionAlert() {
        let alert = UIAlertController(
            title: "需要权限",
            message: "请在设置中授予相机和麦克风权限",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    // MARK: - Actions
    
    @objc private func toggleRecording() {
        if cameraManager.isRecording {
            cameraManager.stopRecording()
        } else {
            // Ensure bluetooth audio is still routed before recording
            audioManager.configureAudioSession()
            cameraManager.startRecording()
        }
    }
    
    @objc private func switchCamera() {
        guard !cameraManager.isRecording else { return }
        
        // Flip animation
        UIView.transition(with: previewView, duration: 0.4, options: .transitionFlipFromLeft) {
            // animation
        } completion: { _ in }
        
        cameraManager.switchCamera()
    }
    
    @objc private func capturePhoto() {
        cameraManager.capturePhoto()
        
        // Flash animation
        let flashView = UIView(frame: view.bounds)
        flashView.backgroundColor = .white
        flashView.alpha = 0
        view.addSubview(flashView)
        UIView.animate(withDuration: 0.1, animations: {
            flashView.alpha = 0.8
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                flashView.alpha = 0
            } completion: { _ in
                flashView.removeFromSuperview()
            }
        }
    }
    
    @objc private func toggleTorch() {
        cameraManager.toggleTorch()
        let icon = cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill"
        torchButton.setImage(UIImage(systemName: icon), for: .normal)
        torchButton.tintColor = cameraManager.isTorchOn ? .yellow : .white
    }
    
    @objc private func toggleQuality() {
        let qualities = VideoQuality.allCases
        guard let currentIndex = qualities.firstIndex(of: cameraManager.currentQuality) else { return }
        let nextIndex = (currentIndex + 1) % qualities.count
        let nextQuality = qualities[nextIndex]
        cameraManager.setVideoQuality(nextQuality)
        qualityButton.setTitle(nextQuality.rawValue, for: .normal)
    }
    
    @objc private func toggleFrameRate() {
        let rates = FrameRate.allCases
        guard let currentIndex = rates.firstIndex(of: cameraManager.currentFrameRate) else { return }
        let nextIndex = (currentIndex + 1) % rates.count
        let nextRate = rates[nextIndex]
        cameraManager.setFrameRate(nextRate)
        frameRateButton.setTitle(nextRate.displayName, for: .normal)
    }
    
    @objc private func showAudioDevicePicker() {
        let devices = audioManager.availableDevices
        let alert = UIAlertController(title: "选择音频输入", message: "当前使用蓝牙设备收音效果更好", preferredStyle: .actionSheet)
        
        for device in devices {
            let prefix = device.isBluetooth ? "🎧 " : "🎤 "
            let isCurrent = device.port.uid == audioManager.currentInputDevice?.port.uid
            let suffix = isCurrent ? " ✓" : ""
            let title = prefix + device.name + suffix
            
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.audioManager.selectDevice(device)
                // Refresh audio input in camera session
                self?.cameraManager.captureSession.beginConfiguration()
                self?.cameraManager.addAudioInput()
                self?.cameraManager.captureSession.commitConfiguration()
            })
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = audioDeviceButton
            popover.sourceRect = audioDeviceButton.bounds
        }
        
        present(alert, animated: true)
    }
    
    @objc private func exposureChanged(_ slider: UISlider) {
        cameraManager.setExposureCompensation(slider.value)
    }
    
    // MARK: - Gestures
    
    @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: previewView)
        
        // Convert to camera coordinates
        guard let previewLayer = previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        
        cameraManager.focus(at: devicePoint)
        
        // Show focus indicator
        focusIndicator.center = point
        focusIndicator.isHidden = false
        focusIndicator.alpha = 1.0
        focusIndicator.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        
        UIView.animate(withDuration: 0.3, animations: {
            self.focusIndicator.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.8, delay: 0.5, options: [], animations: {
                self.focusIndicator.alpha = 0
            }) { _ in
                self.focusIndicator.isHidden = true
            }
        }
        
        // Show exposure slider briefly
        showExposureSlider()
    }
    
    @objc private func handlePinchZoom(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialZoom = cameraManager.currentZoom
            zoomLabel.isHidden = false
        case .changed:
            let newZoom = initialZoom * gesture.scale
            cameraManager.setZoom(newZoom)
            zoomLabel.text = String(format: "%.1fx", cameraManager.currentZoom)
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.5, delay: 1.0) {
                self.zoomLabel.alpha = 0
            } completion: { _ in
                self.zoomLabel.isHidden = true
                self.zoomLabel.alpha = 1.0
            }
        default:
            break
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            showExposureSlider()
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    private func showExposureSlider() {
        sunIcon.isHidden = false
        exposureSlider.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.exposureSlider.alpha = 1.0
            self.sunIcon.alpha = 1.0
        }
        
        // Auto hide after 3 seconds
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideExposureSlider), object: nil)
        perform(#selector(hideExposureSlider), with: nil, afterDelay: 3.0)
    }
    
    @objc private func hideExposureSlider() {
        UIView.animate(withDuration: 0.3) {
            self.exposureSlider.alpha = 0
            self.sunIcon.alpha = 0
        } completion: { _ in
            self.exposureSlider.isHidden = true
            self.sunIcon.isHidden = true
        }
    }
    
    // MARK: - Recording Timer
    
    private func startTimer() {
        recordingDuration = 0
        timerLabel.isHidden = false
        recordingDot.isHidden = false
        timerLabel.text = "00:00"
        
        // Blinking red dot
        UIView.animate(withDuration: 0.6, delay: 0, options: [.repeat, .autoreverse]) {
            self.recordingDot.alpha = 0.2
        }
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingDuration += 1
            let minutes = Int(self.recordingDuration) / 60
            let seconds = Int(self.recordingDuration) % 60
            self.timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        timerLabel.isHidden = true
        recordingDot.isHidden = true
        recordingDot.alpha = 1.0
        recordingDot.layer.removeAllAnimations()
    }
    
    // MARK: - Record Button Animation
    
    private func animateRecordButton(isRecording: Bool) {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
            if isRecording {
                self.recordInner.layer.cornerRadius = 8
                self.recordInner.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
            } else {
                self.recordInner.layer.cornerRadius = 30
                self.recordInner.transform = .identity
            }
        }
    }
}

// MARK: - CameraManagerDelegate

extension CameraViewController: CameraManagerDelegate {
    func cameraDidStartRecording() {
        animateRecordButton(isRecording: true)
        startTimer()
        
        // Disable controls during recording
        switchCameraButton.isEnabled = false
        switchCameraButton.alpha = 0.4
        qualityButton.isEnabled = false
        qualityButton.alpha = 0.4
        frameRateButton.isEnabled = false
        frameRateButton.alpha = 0.4
    }
    
    func cameraDidStopRecording(url: URL?, error: Error?) {
        animateRecordButton(isRecording: false)
        stopTimer()
        
        // Re-enable controls
        switchCameraButton.isEnabled = true
        switchCameraButton.alpha = 1.0
        qualityButton.isEnabled = true
        qualityButton.alpha = 1.0
        frameRateButton.isEnabled = true
        frameRateButton.alpha = 1.0
        
        if let error = error {
            let alert = UIAlertController(title: "录制失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
        } else {
            // Show saved toast
            showToast("视频已保存到相册")
        }
    }
    
    func cameraDidCapturePhoto(_ image: UIImage?) {
        if image != nil {
            showToast("照片已保存")
        }
    }
    
    func cameraSessionConfigured() {
        // Session is ready
    }
    
    func cameraError(_ error: Error) {
        let alert = UIAlertController(title: "相机错误", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - BluetoothAudioManagerDelegate

extension CameraViewController: BluetoothAudioManagerDelegate {
    func audioRouteDidChange(currentInput: AVAudioSession.Port?, inputName: String?) {
        let isBluetooth = currentInput.map {
            [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE].contains($0)
        } ?? false
        
        let iconName = isBluetooth ? "airpodspro" : "mic.fill"
        audioDeviceButton.setImage(UIImage(systemName: iconName), for: .normal)
        audioDeviceButton.setTitle(" \(inputName ?? "内置")", for: .normal)
        audioDeviceButton.tintColor = isBluetooth ? .cyan : .white
    }
    
    func availableDevicesDidChange(_ devices: [AudioInputDevice]) {
        // Could update UI here if needed
    }
    
    func audioLevelDidUpdate(_ level: Float) {
        let maxWidth: CGFloat = 120
        audioLevelWidthConstraint?.constant = maxWidth * CGFloat(level)
        
        // Color: green -> yellow -> red
        if level < 0.5 {
            audioLevelBar.backgroundColor = UIColor.green.withAlphaComponent(0.8)
        } else if level < 0.8 {
            audioLevelBar.backgroundColor = UIColor.yellow.withAlphaComponent(0.8)
        } else {
            audioLevelBar.backgroundColor = UIColor.red.withAlphaComponent(0.8)
        }
    }
}

// MARK: - Toast

extension CameraViewController {
    private func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 16
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -20),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            toast.heightAnchor.constraint(equalToConstant: 36),
        ])
        
        toast.layoutMargins = UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16)
        
        toast.alpha = 0
        UIView.animate(withDuration: 0.3) {
            toast.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 1.5) {
                toast.alpha = 0
            } completion: { _ in
                toast.removeFromSuperview()
            }
        }
    }
}
