import SwiftUI

struct CategoryBadge: View {
    let category: Category
    
    var body: some View {
        Text(category.displayName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(category.color)
            )
    }
}
