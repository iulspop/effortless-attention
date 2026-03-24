import Foundation

struct TodoItem: Identifiable, Codable, Sendable {
    let id: UUID
    var text: String
    var completed: Bool

    init(id: UUID = UUID(), text: String, completed: Bool = false) {
        self.id = id
        self.text = text
        self.completed = completed
    }
}

struct CognitiveContext: Identifiable, Codable, Sendable {
    let id: UUID
    var label: String
    var intention: String
    var timeboxMinutes: Int
    var elapsedSeconds: TimeInterval
    var todos: [TodoItem]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        intention: String,
        timeboxMinutes: Int,
        todos: [TodoItem] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.intention = intention
        self.timeboxMinutes = timeboxMinutes
        self.elapsedSeconds = 0
        self.todos = todos
        self.createdAt = createdAt
    }

    var timeboxSeconds: TimeInterval {
        TimeInterval(timeboxMinutes * 60)
    }

    var remainingSeconds: TimeInterval {
        max(0, timeboxSeconds - elapsedSeconds)
    }

    var isExpired: Bool {
        remainingSeconds <= 0
    }

    var todosCompleted: Int {
        todos.filter(\.completed).count
    }

    var todosTotal: Int {
        todos.count
    }
}
