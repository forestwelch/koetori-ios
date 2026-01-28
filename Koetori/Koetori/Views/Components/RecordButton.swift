import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action()
        }) {
            ZStack {
                // Full circle hit area so first tap always registers (no "load" tap)
                Color.clear
                    .frame(width: 240, height: 240)
                    .contentShape(Circle())
                // Outer pulsing circle (only when recording)
                if isRecording {
                    Circle()
                        .fill(Color.accent.opacity(0.3))
                        .frame(width: 240, height: 240)
                        .scaleEffect(pulseScale)
                        .animation(
                            Animation.easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                }
                
                // Main button circle (visual only; hit area is clear circle above)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isRecording ? [Color.accent, Color.accent.opacity(0.8)] : [Color.primary, Color.primaryHover],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .shadow(color: isRecording ? Color.accent.opacity(0.5) : Color.primary.opacity(0.3), radius: 30)
                
                // Icon
                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 80, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if isRecording {
                pulseScale = 1.2
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                pulseScale = 1.2
            } else {
                pulseScale = 1.0
            }
        }
    }
}
