import AVFoundation
import UIKit

protocol BluetoothAudioManagerDelegate: AnyObject {
    func audioRouteDidChange(currentInput: AVAudioSession.Port?, inputName: String?)
    func availableDevicesDidChange(_ devices: [AudioInputDevice])
}

struct AudioInputDevice {
    let port: AVAudioSessionPortDescription
    var name: String { port.portName }
    var portType: AVAudioSession.Port { port.portType }
    var isBluetooth: Bool {
        [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE].contains(portType)
    }
    var iconName: String {
        if isBluetooth { return "airpodspro" }
        switch portType {
        case .builtInMic: return "mic.fill"
        case .headsetMic: return "headphones"
        default: return "mic.fill"
        }
    }
}

class BluetoothAudioManager {
    static let shared = BluetoothAudioManager()
    weak var delegate: BluetoothAudioManagerDelegate?
    
    private let audioSession = AVAudioSession.sharedInstance()

    
    private(set) var currentInputDevice: AudioInputDevice?
    private(set) var availableDevices: [AudioInputDevice] = []
    
    private init() {
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Audio Session Setup
    
    func configureAudioSession() {
        do {
            // Key: allowBluetooth enables HFP, allowBluetoothA2DP allows A2DP input on supported devices
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            refreshAvailableDevices()
            autoSelectBluetoothDevice()
        } catch {
            print("[BluetoothAudioManager] Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Device Discovery
    
    func refreshAvailableDevices() {
        guard let inputs = audioSession.availableInputs else {
            availableDevices = []
            return
        }
        availableDevices = inputs.map { AudioInputDevice(port: $0) }
        delegate?.availableDevicesDidChange(availableDevices)
        
        // Update current input
        if let currentRoute = audioSession.currentRoute.inputs.first {
            currentInputDevice = availableDevices.first { $0.port.uid == currentRoute.uid }
            delegate?.audioRouteDidChange(
                currentInput: currentRoute.portType,
                inputName: currentRoute.portName
            )
        }
    }
    
    // MARK: - Device Selection
    
    func selectDevice(_ device: AudioInputDevice) {
        do {
            try audioSession.setPreferredInput(device.port)
            currentInputDevice = device
            delegate?.audioRouteDidChange(
                currentInput: device.portType,
                inputName: device.name
            )
        } catch {
            print("[BluetoothAudioManager] Failed to select device: \(error)")
        }
    }
    
    func autoSelectBluetoothDevice() {
        // Prefer bluetooth device if available
        if let btDevice = availableDevices.first(where: { $0.isBluetooth }) {
            selectDevice(btDevice)
        }
    }
    

    
    // MARK: - Notifications
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable:
            DispatchQueue.main.async { [weak self] in
                self?.refreshAvailableDevices()
                self?.autoSelectBluetoothDevice()
            }
        case .oldDeviceUnavailable:
            DispatchQueue.main.async { [weak self] in
                self?.refreshAvailableDevices()
            }
        case .override, .categoryChange:
            // AVCaptureSession can cause these when starting recording.
            // Re-apply bluetooth preference to prevent falling back to built-in mic.
            DispatchQueue.main.async { [weak self] in
                self?.configureAudioSession()
            }
        default:
            break
        }
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        if type == .ended {
            do {
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                autoSelectBluetoothDevice()
            } catch {
                print("[BluetoothAudioManager] Failed to reactivate: \(error)")
            }
        }
    }
}
