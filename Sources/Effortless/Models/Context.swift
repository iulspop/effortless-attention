import Foundation

struct TodoItem: Identifiable, Codable, Sendable {
    let id: UUID
    var text: String
    var timeboxMinutes: Int
    var elapsedSeconds: TimeInterval
    var completed: Bool

    init(id: UUID = UUID(), text: String, timeboxMinutes: Int, completed: Bool = false) {
        self.id = id
        self.text = text
        self.timeboxMinutes = timeboxMinutes
        self.elapsedSeconds = 0
        self.completed = completed
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
}

struct CognitiveContext: Identifiable, Codable, Sendable {
    let id: UUID
    var label: String
    var todos: [TodoItem]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        todos: [TodoItem] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.todos = todos
        self.createdAt = createdAt
    }

    /// The first uncompleted todo is the current intention
    var currentTodo: TodoItem? {
        todos.first { !$0.completed }
    }

    /// Index of the current todo in the array
    var currentTodoIndex: Int? {
        todos.firstIndex { !$0.completed }
    }

    /// Whether this context has an active intention (uncompleted todo)
    var hasActiveIntention: Bool {
        currentTodo != nil
    }

    var remainingSeconds: TimeInterval {
        currentTodo?.remainingSeconds ?? 0
    }

    var todosCompleted: Int {
        todos.filter(\.completed).count
    }

    var todosTotal: Int {
        todos.count
    }
}
