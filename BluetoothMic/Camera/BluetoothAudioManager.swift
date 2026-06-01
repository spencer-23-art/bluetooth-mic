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
    private var isHandlingRouteChange = false
    
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
        isHandlingRouteChange = true
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            refreshAvailableDevices()
            autoSelectBluetoothDevice()
            
            // After bluetooth route is set, tell CameraManager to add audio input
            // with a small delay so the route change propagates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                CameraManager.shared.refreshAudioInput()
            }
        } catch {
            print("[BluetoothAudioManager] Failed to configure audio session: \(error)")
        }
        // Allow route change handling again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isHandlingRouteChange = false
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
            
            // Refresh capture session audio input after route change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                CameraManager.shared.refreshAudioInput()
            }
        } catch {
            print("[BluetoothAudioManager] Failed to select device: \(error)")
        }
    }
    
    func autoSelectBluetoothDevice() {
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
        // Prevent re-entrant handling: setPreferredInput/setCategory trigger more route changes
        guard !isHandlingRouteChange else { return }
        
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable:
            isHandlingRouteChange = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.refreshAvailableDevices()
                self.autoSelectBluetoothDevice()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isHandlingRouteChange = false
                }
            }
        case .oldDeviceUnavailable:
            DispatchQueue.main.async { [weak self] in
                self?.refreshAvailableDevices()
            }
        case .override, .categoryChange:
            // DO NOT call configureAudioSession() here - it calls setCategory()
            // which triggers another .categoryChange = infinite loop!
            // Just refresh and re-apply preferred input.
            isHandlingRouteChange = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.refreshAvailableDevices()
                self.autoSelectBluetoothDevice()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isHandlingRouteChange = false
                }
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
