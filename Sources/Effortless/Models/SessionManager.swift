import Foundation
import Combine

extension Notification.Name {
    static let sessionStateChanged = Notification.Name("sessionStateChanged")
    static let needsIntention = Notification.Name("needsIntention")
}

private struct PersistedState: Codable {
    let contexts: [CognitiveContext]
    let activeIndex: Int
}

@MainActor
class SessionManager: ObservableObject {
    @Published var contexts: [CognitiveContext] = []
    @Published var activeIndex: Int = 0
    @Published var remainingTimeFormatted: String = ""

    private var timer: Timer?
    private let logger = SessionLogger()
    private var lastTickDate: Date?

    init() {
        restoreState()
    }

    // MARK: - Computed Properties

    var activeContext: CognitiveContext? {
        guard !contexts.isEmpty, activeIndex >= 0, activeIndex < contexts.count else { return nil }
        return contexts[activeIndex]
    }

    /// Whether the active context has a running intention
    var hasActiveIntention: Bool {
        activeContext?.hasActiveIntention ?? false
    }

    // MARK: - Context Lifecycle

    func addContext(label: String, intention: String, minutes: Int) {
        let todo = TodoItem(text: intention, timeboxMinutes: minutes)
        let ctx = CognitiveContext(label: label, todos: [todo])

        if contexts.isEmpty {
            contexts.append(ctx)
            activeIndex = 0
            startTimer()
        } else {
            contexts.append(ctx)
        }
        notifyChange()
    }

    func addTodoToActiveContext(text: String, minutes: Int) {
        guard !contexts.isEmpty, activeIndex >= 0, activeIndex < contexts.count else { return }
        let todo = TodoItem(text: text, timeboxMinutes: minutes)
        contexts[activeIndex].todos.append(todo)

        // If timer wasn't running (no active todo before), start it
        if timer == nil && contexts[activeIndex].hasActiveIntention {
            startTimer()
        }
        notifyChange()
    }

    func addTodo(text: String, minutes: Int, at contextIndex: Int) {
        guard contextIndex >= 0, contextIndex < contexts.count else { return }
        let todo = TodoItem(text: text, timeboxMinutes: minutes)
        contexts[contextIndex].todos.append(todo)

        // Start timer if this is the active context and it now has an intention
        if contextIndex == activeIndex && timer == nil && contexts[contextIndex].hasActiveIntention {
            startTimer()
        }
        notifyChange()
    }

    func switchTo(index: Int) {
        guard index >= 0, index < contexts.count else { return }
        guard index != activeIndex else { return }

        // Pause current — snapshot elapsed time
        accumulateElapsed(at: activeIndex)

        activeIndex = index
        lastTickDate = Date()

        // Ensure timer is running if new context has active intention
        if contexts[activeIndex].hasActiveIntention && timer == nil {
            startTimer()
        }
        notifyChange()
    }

    func cycleNext() {
        guard contexts.count > 1 else { return }
        let next = (activeIndex + 1) % contexts.count
        switchTo(index: next)
    }

    func cyclePrev() {
        guard contexts.count > 1 else { return }
        let prev = (activeIndex - 1 + contexts.count) % contexts.count
        switchTo(index: prev)
    }

    func complete() {
        guard activeIndex >= 0, activeIndex < contexts.count else { return }
        guard let todoIndex = contexts[activeIndex].currentTodoIndex else { return }

        accumulateElapsed(at: activeIndex)
        logTodo(contexts[activeIndex].todos[todoIndex], context: contexts[activeIndex], outcome: .completed)
        contexts[activeIndex].todos[todoIndex].completed = true
        advanceAfterTodoFinished()
        notifyChange()
    }

    func interrupt() {
        guard activeIndex >= 0, activeIndex < contexts.count else { return }
        guard let todoIndex = contexts[activeIndex].currentTodoIndex else { return }

        accumulateElapsed(at: activeIndex)
        logTodo(contexts[activeIndex].todos[todoIndex], context: contexts[activeIndex], outcome: .interrupted)
        contexts[activeIndex].todos[todoIndex].completed = true
        advanceAfterTodoFinished()
        notifyChange()
    }

    /// After finishing a todo: stay if more in queue, else switch to next context with work, else altar
    private func advanceAfterTodoFinished() {
        // Current context still has work
        if contexts[activeIndex].hasActiveIntention {
            lastTickDate = Date()
            return
        }

        // Find next context with an active intention
        for offset in 1..<contexts.count {
            let idx = (activeIndex + offset) % contexts.count
            if contexts[idx].hasActiveIntention {
                switchTo(index: idx)
                return
            }
        }

        // All contexts done — open altar
        NotificationCenter.default.post(name: .needsIntention, object: nil)
    }

    // MARK: - Context Editing

    func updateLabel(_ label: String, at index: Int) {
        guard index >= 0, index < contexts.count else { return }
        contexts[index].label = label
        notifyChange()
    }

    func updateTodoText(_ text: String, todoId: UUID, at contextIndex: Int) {
        guard contextIndex >= 0, contextIndex < contexts.count else { return }
        if let todoIndex = contexts[contextIndex].todos.firstIndex(where: { $0.id == todoId }) {
            contexts[contextIndex].todos[todoIndex].text = text
            notifyChange()
        }
    }

    func removeTodo(todoId: UUID, at contextIndex: Int) {
        guard contextIndex >= 0, contextIndex < contexts.count else { return }
        let wasCurrent = contexts[contextIndex].currentTodo?.id == todoId
        contexts[contextIndex].todos.removeAll { $0.id == todoId }

        if wasCurrent && contextIndex == activeIndex {
            advanceAfterTodoFinished()
        }
        notifyChange()
    }

    func removeContext(at index: Int) {
        guard index >= 0, index < contexts.count else { return }
        contexts.remove(at: index)

        if contexts.isEmpty {
            stopTimer()
            activeIndex = 0
        } else {
            if index == activeIndex {
                activeIndex = min(index, contexts.count - 1)
                lastTickDate = Date()
            } else if index < activeIndex {
                activeIndex -= 1
            }
        }
        notifyChange()
    }

    // MARK: - Timer

    private func startTimer() {
        lastTickDate = Date()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        remainingTimeFormatted = ""
        lastTickDate = nil
    }

    private func tick() {
        guard activeIndex >= 0, activeIndex < contexts.count else { return }
        guard let todoIndex = contexts[activeIndex].currentTodoIndex else {
            remainingTimeFormatted = ""
            return
        }

        // Accumulate time on active todo
        let now = Date()
        if let last = lastTickDate {
            contexts[activeIndex].todos[todoIndex].elapsedSeconds += now.timeIntervalSince(last)
        }
        lastTickDate = now

        if contexts[activeIndex].todos[todoIndex].isExpired {
            logTodo(contexts[activeIndex].todos[todoIndex], context: contexts[activeIndex], outcome: .expired)
            contexts[activeIndex].todos[todoIndex].completed = true
            advanceAfterTodoFinished()
            notifyChange()
            return
        }

        let remaining = Int(contexts[activeIndex].todos[todoIndex].remainingSeconds)
        let minutes = remaining / 60
        let seconds = remaining % 60
        remainingTimeFormatted = String(format: "%d:%02d", minutes, seconds)
        notifyChange()
    }

    private func accumulateElapsed(at index: Int) {
        guard index >= 0, index < contexts.count else { return }
        guard let todoIndex = contexts[index].currentTodoIndex else { return }
        let now = Date()
        if let last = lastTickDate {
            contexts[index].todos[todoIndex].elapsedSeconds += now.timeIntervalSince(last)
        }
        lastTickDate = now
    }

    // MARK: - Logging

    private func logTodo(_ todo: TodoItem, context ctx: CognitiveContext, outcome: Session.Outcome) {
        let session = Session(
            id: todo.id,
            label: ctx.label,
            intention: todo.text,
            timeboxMinutes: todo.timeboxMinutes,
            elapsedSeconds: todo.elapsedSeconds,
            todos: ctx.todos,
            startedAt: ctx.createdAt,
            endedAt: Date(),
            outcome: outcome
        )
        logger.log(session)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .sessionStateChanged, object: nil)
        persistState()
    }

    // MARK: - Persistence

    private static var stateFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Effortless", isDirectory: true)
        return dir.appendingPathComponent("state.json")
    }

    private func persistState() {
        if contexts.isEmpty {
            try? FileManager.default.removeItem(at: Self.stateFile)
            return
        }
        let persisted = PersistedState(contexts: contexts, activeIndex: activeIndex)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(persisted) else { return }
        let dir = Self.stateFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.stateFile)
    }

    private func restoreState() {
        guard FileManager.default.fileExists(atPath: Self.stateFile.path) else { return }
        guard let data = try? Data(contentsOf: Self.stateFile) else { return }
        guard let persisted = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        guard !persisted.contexts.isEmpty else { return }
        contexts = persisted.contexts
        activeIndex = min(persisted.activeIndex, persisted.contexts.count - 1)
        if contexts[activeIndex].hasActiveIntention {
            startTimer()
        }
    }
}
