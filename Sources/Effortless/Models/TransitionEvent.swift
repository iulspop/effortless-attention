import Foundation

struct CognitiveSnapshot: Codable, Sendable, Equatable {
    let contextId: UUID
    let contextLabel: String
    let todoId: UUID
    let todoText: String
    var timeboxMinutes: Int?
}

struct TransitionEvent: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: TransitionType
    let from: CognitiveSnapshot?
    let to: CognitiveSnapshot
    let interruptionDepth: Int

    enum TransitionType: String, Codable, Sendable {
        case start
        case completion
        case interruption
        case contextSwitch
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: TransitionType,
        from: CognitiveSnapshot?,
        to: CognitiveSnapshot,
        interruptionDepth: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.from = from
        self.to = to
        self.interruptionDepth = interruptionDepth
    }
}
