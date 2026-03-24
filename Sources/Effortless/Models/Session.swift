import Foundation

struct Session: Codable, Sendable {
    let id: UUID
    let label: String
    let intention: String
    let timeboxMinutes: Int
    let elapsedSeconds: TimeInterval
    let todos: [TodoItem]
    let startedAt: Date
    var endedAt: Date?
    var outcome: Outcome?

    enum Outcome: String, Codable, Sendable {
        case completed
        case interrupted
        case expired
    }
}
