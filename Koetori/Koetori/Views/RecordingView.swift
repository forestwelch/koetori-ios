import SwiftUI
import AudioToolbox

struct RecordingView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    
    @State private var showResults = false
    @State private var apiResponse: APIResponse?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isUploading = false
    @State private var hasRequestedPermission = false
    
    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            
            VStack(spacing: 4) {
                // Title
                Text("Koetori")
                    .font(.system(size: 72, weight: .ultraLight, design: .default))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 60)
                
                // Microphone selector
                MicrophoneSelector(audioRecorder: audioRecorder)
                
                Spacer()
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
                
                // Record Button - always centered
                RecordButton(isRecording: audioRecorder.isRecording) {
                    handleButtonTap()
                }
                .disabled(isUploading)
                .opacity(isUploading ? 0.5 : 1.0)
                
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
            // Update microphone list when view appears
            audioRecorder.updateAvailableMicrophones()
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
            
            // Play success sound
            AudioServicesPlaySystemSound(1057)
            
            // Clean up audio file
            audioRecorder.cleanup()
            
            // Show results
            await MainActor.run {
                apiResponse = response
                showResults = true
                isUploading = false
            }
        } catch {
            // Clean up audio file on error
            audioRecorder.cleanup()
            
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isUploading = false
            }
        }
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
