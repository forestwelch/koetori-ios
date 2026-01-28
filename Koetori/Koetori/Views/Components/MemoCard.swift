import SwiftUI

struct MemoCard: View {
    let memo: Memo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryBadge(category: memo.category)
                Spacer()
                Text("\(Int(memo.confidence * 100))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.success)
            }
            
            Text(memo.summary)
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
                .lineLimit(nil)
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(12)
    }
}
