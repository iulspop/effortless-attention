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

    let distractionText: String?

    enum TransitionType: String, Codable, Sendable {
        case start
        case completion
        case interruption
        case contextSwitch
        case distraction
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: TransitionType,
        from: CognitiveSnapshot?,
        to: CognitiveSnapshot,
        interruptionDepth: Int = 0,
        distractionText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.from = from
        self.to = to
        self.interruptionDepth = interruptionDepth
        self.distractionText = distractionText
    }
}
