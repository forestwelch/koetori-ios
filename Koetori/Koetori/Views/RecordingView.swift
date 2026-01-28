import SwiftUI
import AudioToolbox

struct RecordingView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var bleManager = BLEManager.shared
    
    @State private var showResults = false
    @State private var apiResponse: APIResponse?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isUploading = false
    @State private var hasRequestedPermission = false
    @State private var showDebug = false
    
    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            
            VStack(spacing: 4) {
                // BLE status
                bleStatusView
                    .padding(.top, 8)
                
                // Title
                Text("Koetori")
                    .font(.system(size: 72, weight: .ultraLight, design: .default))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 24)
                
                // Microphone selector
                MicrophoneSelector(audioRecorder: audioRecorder)
                
                Spacer()
                
                // BLE debug (collapsible)
                DisclosureGroup(isExpanded: $showDebug) {
                    debugSection
                } label: {
                    Text("BLE Debug")
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            
            // Centered content - button stays in same position
            VStack(spacing: 0) {
                // Fixed height timer area (prevents button from moving)
                ZStack {
                    if audioRecorder.isRecording {
                        Text(formatTime(audioRecorder.recordingDuration))
                            .font(.system(size: 48, weight: .medium, design: .monospaced))
                            .foregroundColor(.textPrimary)
                    }
                }
                .frame(height: 60)
                .padding(.bottom, 30)
                
                // Record Button - always centered (disabled when BLE receiving or uploading)
                RecordButton(isRecording: audioRecorder.isRecording) {
                    handleButtonTap()
                }
                .disabled(isUploading || isBLEReceiving)
                .opacity((isUploading || isBLEReceiving) ? 0.5 : 1.0)
                
                // Fixed height cancel button area
                ZStack {
                    if audioRecorder.isRecording {
                        Button(action: {
                            cancelRecording()
                        }) {
                            Text("Cancel")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.bgSecondary)
                                .cornerRadius(20)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(height: 60)
                .padding(.top, 30)
                
                // Loading indicator
                if isUploading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                        .scaleEffect(1.5)
                        .padding(.top, 20)
                }
            }
        }
        .sheet(isPresented: $showResults) {
            if let response = apiResponse {
                ResultsView(response: response) {
                    showResults = false
                    apiResponse = nil
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
            if errorMessage?.contains("permission") == true {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .task {
            if !hasRequestedPermission {
                await requestMicrophonePermission()
            }
            audioRecorder.updateAvailableMicrophones()
        }
        .onAppear {
            bleManager.onAudioAssembled = { url in
                Task { await uploadBLEAudio(fileURL: url) }
            }
            bleManager.startScanning()
        }
        .onDisappear {
            bleManager.onAudioAssembled = nil
        }
        .onChange(of: bleManager.showError) { _, show in
            if show, let msg = bleManager.errorMessage {
                errorMessage = msg
                showError = true
                bleManager.showError = false
            }
        }
    }
    
    @ViewBuilder
    private var debugSection: some View {
        let info = bleManager.debugInfo
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Chunks:")
                    .foregroundColor(.textMuted)
                Text("\(info.lastChunksReceived) / \(info.lastChunksExpected)")
                    .foregroundColor(.textSecondary)
            }
            .font(.system(size: 12, design: .monospaced))
            HStack {
                Text("Event:")
                    .foregroundColor(.textMuted)
                Text(info.lastEvent)
                    .foregroundColor(.textSecondary)
            }
            .font(.system(size: 12, design: .monospaced))
            if let err = info.lastError {
                HStack {
                    Text("Error:")
                        .foregroundColor(.textMuted)
                    Text(err)
                        .foregroundColor(.warning)
                }
                .font(.system(size: 12, design: .monospaced))
            }
            if let at = info.lastTransferAt {
                HStack {
                    Text("At:")
                        .foregroundColor(.textMuted)
                    Text(at, style: .time)
                        .foregroundColor(.textSecondary)
                }
                .font(.system(size: 12, design: .monospaced))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary.opacity(0.6))
        .cornerRadius(8)
    }
    
    private var isBLEReceiving: Bool {
        if case .receiving = bleManager.connectionState { return true }
        return false
    }
    
    @ViewBuilder
    private var bleStatusView: some View {
        Group {
            switch bleManager.connectionState {
            case .disconnected:
                Text("Searching for device…")
                    .font(.system(size: 13))
                    .foregroundColor(.textMuted)
            case .scanning:
                Text("Searching for device…")
                    .font(.system(size: 13))
                    .foregroundColor(.textMuted)
            case .connecting:
                Text("Connecting…")
                    .font(.system(size: 13))
                    .foregroundColor(.warning)
            case .connected(let name):
                Text("Connected to \(name)")
                    .font(.system(size: 13))
                    .foregroundColor(.success)
            case .receiving(let name):
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                    Text("Receiving from \(name)")
                        .font(.system(size: 13))
                        .foregroundColor(.accent)
                }
            }
        }
    }
    
    private func handleButtonTap() {
        if audioRecorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        do {
            try audioRecorder.startRecording()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func stopRecording() {
        guard let audioURL = audioRecorder.stopRecording() else {
            errorMessage = "Failed to get recording file"
            showError = true
            return
        }
        
        Task {
            await uploadAudio(fileURL: audioURL)
        }
    }
    
    private func cancelRecording() {
        audioRecorder.stopRecording()
        audioRecorder.cleanup()
    }
    
    private func uploadAudio(fileURL: URL) async {
        isUploading = true
        do {
            let response = try await APIService.shared.uploadAudio(fileURL: fileURL)
            AudioServicesPlaySystemSound(1057)
            audioRecorder.cleanup()
            HistoryStore.shared.add(response, source: .mic)
            apiResponse = response
            showResults = true
        } catch {
            audioRecorder.cleanup()
            errorMessage = error.localizedDescription
            showError = true
        }
        isUploading = false
    }
    
    private func uploadBLEAudio(fileURL: URL) async {
        isUploading = true
        do {
            let response = try await APIService.shared.uploadAudio(fileURL: fileURL)
            AudioServicesPlaySystemSound(1057)
            try? FileManager.default.removeItem(at: fileURL)
            HistoryStore.shared.add(response, source: .ble)
            apiResponse = response
            showResults = true
            // Notify M5 so it can show category/confidence
            if let first = response.memos.first {
                bleManager.writeToControl("SUCCESS:\(first.category.rawValue):\(Float(first.confidence))")
            } else {
                bleManager.writeToControl("SUCCESS:other:0")
            }
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            errorMessage = error.localizedDescription
            showError = true
        }
        isUploading = false
    }
    
    private func requestMicrophonePermission() async {
        hasRequestedPermission = true
        let granted = await audioRecorder.requestPermission()
        
        if !granted {
            await MainActor.run {
                errorMessage = "Microphone permission is required to record audio. Please enable it in Settings."
                showError = true
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
