import Foundation

struct Session: Codable, Sendable {
    let id: UUID
    let intention: String
    let timeboxMinutes: Int
    let startedAt: Date
    var endedAt: Date?
    var outcome: Outcome?

    enum Outcome: String, Codable, Sendable {
        case completed
        case interrupted
        case expired
    }

    var timeboxSeconds: TimeInterval {
        TimeInterval(timeboxMinutes * 60)
    }

    var elapsedSeconds: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    var remainingSeconds: TimeInterval {
        max(0, timeboxSeconds - elapsedSeconds)
    }

    var isExpired: Bool {
        remainingSeconds <= 0
    }
}
