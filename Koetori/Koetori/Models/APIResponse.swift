import Foundation

struct APIResponse: Codable {
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
}
