import Foundation

struct HistoryItem: Codable, Identifiable, Sendable {
    let id: UUID
    let response: APIResponse
    let receivedAt: Date
    let source: Source

    enum Source: String, Codable, CaseIterable, Sendable {
        case ble
        case mic
    }

    init(id: UUID = UUID(), response: APIResponse, receivedAt: Date = Date(), source: Source) {
        self.id = id
        self.response = response
        self.receivedAt = receivedAt
        self.source = source
    }
}
