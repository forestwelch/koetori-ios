import SwiftUI

enum Category: String, Codable, CaseIterable, Sendable {
    case media
    case todo
    case reminder
    case journal
    case idea
    case shopping
    case tarot
    case other
    
    var color: Color {
        switch self {
        case .media: return .categoryMedia
        case .todo: return .categoryTodo
        case .reminder: return .categoryReminder
        case .journal: return .categoryJournal
        case .idea: return .categoryIdea
        case .shopping: return .categoryShopping
        case .tarot: return .categoryTarot
        case .other: return .categoryOther
        }
    }
    
    var displayName: String {
        rawValue.capitalized
    }
}
