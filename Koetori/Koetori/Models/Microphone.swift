import Foundation
import AVFoundation

struct Microphone: Identifiable, Equatable {
    let id: String
    let name: String
    let portType: AVAudioSession.Port
    
    init(portDescription: AVAudioSessionPortDescription) {
        self.id = portDescription.uid
        self.name = portDescription.portName
        self.portType = portDescription.portType
    }
    
    var displayName: String {
        switch portType {
        case .builtInMic:
            return "iPhone Microphone"
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP:
            return "\(name) (Bluetooth)"
        case .headsetMic:
            return "\(name) (Headset)"
        case .usbAudio:
            return "\(name) (USB)"
        default:
            return name
        }
    }
    
    var portTypeDescription: String {
        switch portType {
        case .builtInMic:
            return "Built-in"
        case .bluetoothHFP:
            return "Bluetooth HFP"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .bluetoothA2DP:
            return "Bluetooth A2DP"
        case .headsetMic:
            return "Headset"
        case .usbAudio:
            return "USB"
        default:
            return "Other"
        }
    }
}
