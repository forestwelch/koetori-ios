import SwiftUI

struct MicrophoneSelector: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @State private var showPicker = false
    
    var body: some View {
        Button(action: {
            showPicker = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                Text(audioRecorder.currentMicrophone?.displayName ?? "Microphone")
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.bgSecondary)
            .cornerRadius(20)
        }
        .sheet(isPresented: $showPicker) {
            MicrophonePickerView(audioRecorder: audioRecorder, isPresented: $showPicker)
        }
    }
}

struct MicrophonePickerView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                
                List {
                    ForEach(audioRecorder.availableMicrophones) { microphone in
                        Button(action: {
                            do {
                                try audioRecorder.setPreferredMicrophone(microphone)
                                isPresented = false
                            } catch {
                                // Handle error silently or show alert
                                print("Failed to set microphone: \(error)")
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(microphone.displayName)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                    
                                    Text(microphone.portTypeDescription)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textMuted)
                                }
                                
                                Spacer()
                                
                                if audioRecorder.currentMicrophone?.id == microphone.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.bgSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Microphone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            audioRecorder.updateAvailableMicrophones()
        }
    }
}
