import Foundation

struct Memo: Codable, Identifiable, Sendable {
    let id: String
    let category: Category
    let confidence: Double
    let transcriptExcerpt: String
    let extracted: ExtractedData?
    let tags: [String]
    let needsReview: Bool?
    let starred: Bool?
    
    struct ExtractedData: Codable, Sendable {
        let title: String?
        let who: [String]?
        let when: String?
        let `where`: String?
        let what: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case category
        case confidence
        case transcriptExcerpt = "transcript_excerpt"
        case extracted
        case tags
        case needsReview = "needs_review"
        case starred
    }
    
    // Computed property for summary (using transcript_excerpt)
    var summary: String {
        transcriptExcerpt
    }
}
