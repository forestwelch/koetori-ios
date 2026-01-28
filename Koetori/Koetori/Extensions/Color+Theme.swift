import SwiftUI

extension Color {
    // Background colors
    static let bgPrimary = Color(hex: "#0a0a0f")
    static let bgSecondary = Color(hex: "#14151f")
    
    // Primary colors
    static let primary = Color(hex: "#6366f1")
    static let primaryHover = Color(hex: "#4f46e5")
    static let accent = Color(hex: "#f43f5e")
    
    // Status colors
    static let success = Color(hex: "#10b981")
    static let warning = Color(hex: "#f59e0b")
    static let error = Color(hex: "#ef4444")
    
    // Text colors
    static let textPrimary = Color(hex: "#f8fafc")
    static let textSecondary = Color(hex: "#cbd5e1")
    static let textMuted = Color(hex: "#64748b")
    
    // Category colors
    static let categoryMedia = Color(hex: "#6366f1")
    static let categoryTodo = Color(hex: "#f43f5e")
    static let categoryReminder = Color(hex: "#f59e0b")
    static let categoryJournal = Color(hex: "#10b981")
    static let categoryIdea = Color(hex: "#a855f7")
    static let categoryShopping = Color(hex: "#06b6d4")
    static let categoryTarot = Color(hex: "#ec4899")
    static let categoryOther = Color(hex: "#64748b")
    
    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
