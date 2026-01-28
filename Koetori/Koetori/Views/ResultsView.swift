import SwiftUI

struct ResultsView: View {
    let response: APIResponse
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Transcript Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Transcript")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            
                            Text(response.transcript)
                                .font(.system(size: 15))
                                .foregroundColor(.textSecondary)
                                .lineSpacing(4)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgSecondary)
                        .cornerRadius(16)
                        
                        // Memos Section
                        if !response.memos.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Memos")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                
                                ForEach(response.memos) { memo in
                                    MemoCard(memo: memo)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
