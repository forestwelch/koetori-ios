import Foundation

struct APIResponse: Codable, Sendable {
    let transcript: String
    let transcriptionId: String
    let memos: [Memo]
    let duration: Int?
    let language: String?
    
    enum CodingKeys: String, CodingKey {
        case transcript
        case transcriptionId = "transcription_id"
        case memos
        case duration
        case language
    }
    
    /// Decode from data in a nonisolated context (for use from actors).
    nonisolated static func decode(from data: Data) throws -> APIResponse {
        try JSONDecoder().decode(APIResponse.self, from: data)
    }
}
