import AVFoundation
import Foundation
import Combine

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var availableMicrophones: [Microphone] = []
    @Published var currentMicrophone: Microphone?
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var audioFileURL: URL?
    
    override init() {
        super.init()
        updateAvailableMicrophones()
        setupAudioRouteChangeObserver()
    }
    
    private func setupAudioRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        Task { @MainActor in
            updateAvailableMicrophones()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func updateAvailableMicrophones() {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Get available inputs
        if let inputs = audioSession.availableInputs {
            availableMicrophones = inputs.map { Microphone(portDescription: $0) }
        } else {
            availableMicrophones = []
        }
        
        // Get current preferred input
        if let preferredInput = audioSession.preferredInput {
            currentMicrophone = Microphone(portDescription: preferredInput)
        } else {
            // Fallback to built-in mic if no preferred input
            if let builtInMic = availableMicrophones.first(where: { $0.portType == .builtInMic }) {
                currentMicrophone = builtInMic
            }
        }
    }
    
    func setPreferredMicrophone(_ microphone: Microphone) throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Find the matching port description
        guard let input = audioSession.availableInputs?.first(where: { $0.uid == microphone.id }) else {
            throw RecordingError.microphoneNotFound
        }
        
        try audioSession.setPreferredInput(input)
        currentMicrophone = microphone
        
        // Update list in case it changed
        updateAvailableMicrophones()
    }
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func startRecording() throws {
        // Check permission
        let permission = AVAudioSession.sharedInstance().recordPermission
        guard permission == .granted else {
            throw RecordingError.permissionDenied
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        
        // Update microphone list before activating (in case new devices connected)
        updateAvailableMicrophones()
        
        try audioSession.setActive(true)
        
        // Create file URL
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        audioFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        guard let url = audioFileURL else {
            throw RecordingError.fileCreationFailed
        }
        
        // Audio settings for M4A (AAC)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        // Create recorder
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
        
        isRecording = true
        recordingDuration = 0
        
        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recordingDuration += 0.1
            }
        }
    }
    
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        return audioFileURL
    }
    
    func cleanup() {
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioFileURL = nil
    }
    
    enum RecordingError: LocalizedError {
        case permissionDenied
        case fileCreationFailed
        case recordingFailed
        case microphoneNotFound
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission is required to record audio."
            case .fileCreationFailed:
                return "Failed to create audio file."
            case .recordingFailed:
                return "Failed to start recording."
            case .microphoneNotFound:
                return "Selected microphone is no longer available."
            }
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !flag {
                self.isRecording = false
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
            }
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
        }
    }
}
