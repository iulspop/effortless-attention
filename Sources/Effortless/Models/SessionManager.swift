import Foundation
import Combine

extension Notification.Name {
    static let sessionStateChanged = Notification.Name("sessionStateChanged")
}

@MainActor
class SessionManager: ObservableObject {
    enum State {
        case idle
        case active(contexts: [CognitiveContext], activeIndex: Int)
    }

    @Published var state: State = .idle
    @Published var remainingTimeFormatted: String = ""

    private var timer: Timer?
    private let logger = SessionLogger()
    private var lastTickDate: Date?

    // MARK: - Computed Properties

    var contexts: [CognitiveContext] {
        if case .active(let contexts, _) = state { return contexts }
        return []
    }

    var activeIndex: Int? {
        if case .active(_, let index) = state { return index }
        return nil
    }

    var activeContext: CognitiveContext? {
        guard case .active(let contexts, let index) = state else { return nil }
        guard index >= 0 && index < contexts.count else { return nil }
        return contexts[index]
    }

    // MARK: - Context Lifecycle

    func addContext(label: String, intention: String, minutes: Int) {
        let ctx = CognitiveContext(label: label, intention: intention, timeboxMinutes: minutes)

        switch state {
        case .idle:
            state = .active(contexts: [ctx], activeIndex: 0)
            startTimer()
        case .active(var contexts, let activeIndex):
            contexts.append(ctx)
            state = .active(contexts: contexts, activeIndex: activeIndex)
        }
        notifyChange()
    }

    func switchTo(index: Int) {
        guard case .active(var contexts, let currentIndex) = state else { return }
        guard index >= 0 && index < contexts.count else { return }
        guard index != currentIndex else { return }

        // Pause current — snapshot elapsed time
        accumulateElapsed(&contexts, at: currentIndex)

        state = .active(contexts: contexts, activeIndex: index)
        lastTickDate = Date()
        notifyChange()
    }

    func cycleNext() {
        guard case .active(let contexts, let index) = state else { return }
        let next = (index + 1) % contexts.count
        switchTo(index: next)
    }

    func cyclePrev() {
        guard case .active(let contexts, let index) = state else { return }
        let prev = (index - 1 + contexts.count) % contexts.count
        switchTo(index: prev)
    }

    func complete() {
        guard case .active(var contexts, let index) = state else { return }
        accumulateElapsed(&contexts, at: index)
        let ctx = contexts[index]
        logContext(ctx, outcome: .completed)
        contexts.remove(at: index)

        if contexts.isEmpty {
            stopTimer()
            state = .idle
        } else {
            let newIndex = min(index, contexts.count - 1)
            state = .active(contexts: contexts, activeIndex: newIndex)
            lastTickDate = Date()
        }
        notifyChange()
    }

    func interrupt() {
        guard case .active(var contexts, let index) = state else { return }
        accumulateElapsed(&contexts, at: index)
        let ctx = contexts[index]
        logContext(ctx, outcome: .interrupted)
        contexts.remove(at: index)

        if contexts.isEmpty {
            stopTimer()
            state = .idle
        } else {
            let newIndex = min(index, contexts.count - 1)
            state = .active(contexts: contexts, activeIndex: newIndex)
            lastTickDate = Date()
        }
        notifyChange()
    }

    // MARK: - Context Editing

    func updateLabel(_ label: String, at index: Int) {
        guard case .active(var contexts, let activeIndex) = state else { return }
        guard index >= 0 && index < contexts.count else { return }
        contexts[index].label = label
        state = .active(contexts: contexts, activeIndex: activeIndex)
        notifyChange()
    }

    func updateIntention(_ intention: String, at index: Int) {
        guard case .active(var contexts, let activeIndex) = state else { return }
        guard index >= 0 && index < contexts.count else { return }
        contexts[index].intention = intention
        state = .active(contexts: contexts, activeIndex: activeIndex)
        notifyChange()
    }

    func addTodo(_ text: String, at contextIndex: Int) {
        guard case .active(var contexts, let activeIndex) = state else { return }
        guard contextIndex >= 0 && contextIndex < contexts.count else { return }
        contexts[contextIndex].todos.append(TodoItem(text: text))
        state = .active(contexts: contexts, activeIndex: activeIndex)
        notifyChange()
    }

    func toggleTodo(todoId: UUID, at contextIndex: Int) {
        guard case .active(var contexts, let activeIndex) = state else { return }
        guard contextIndex >= 0 && contextIndex < contexts.count else { return }
        if let todoIndex = contexts[contextIndex].todos.firstIndex(where: { $0.id == todoId }) {
            contexts[contextIndex].todos[todoIndex].completed.toggle()
            state = .active(contexts: contexts, activeIndex: activeIndex)
            notifyChange()
        }
    }

    func removeTodo(todoId: UUID, at contextIndex: Int) {
        guard case .active(var contexts, let activeIndex) = state else { return }
        guard contextIndex >= 0 && contextIndex < contexts.count else { return }
        contexts[contextIndex].todos.removeAll { $0.id == todoId }
        state = .active(contexts: contexts, activeIndex: activeIndex)
        notifyChange()
    }

    func removeContext(at index: Int) {
        guard case .active(var contexts, let activeIndex) = state else { return }
        guard index >= 0 && index < contexts.count else { return }

        accumulateElapsed(&contexts, at: index)
        let ctx = contexts[index]
        logContext(ctx, outcome: .interrupted)
        contexts.remove(at: index)

        if contexts.isEmpty {
            stopTimer()
            state = .idle
        } else {
            let newActive: Int
            if index == activeIndex {
                newActive = min(index, contexts.count - 1)
            } else if index < activeIndex {
                newActive = activeIndex - 1
            } else {
                newActive = activeIndex
            }
            state = .active(contexts: contexts, activeIndex: newActive)
            lastTickDate = Date()
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
        guard case .active(var contexts, let index) = state else { return }
        guard index >= 0 && index < contexts.count else { return }

        // Accumulate time on active context
        let now = Date()
        if let last = lastTickDate {
            contexts[index].elapsedSeconds += now.timeIntervalSince(last)
        }
        lastTickDate = now

        if contexts[index].isExpired {
            let ctx = contexts[index]
            logContext(ctx, outcome: .expired)
            contexts.remove(at: index)

            if contexts.isEmpty {
                stopTimer()
                state = .idle
            } else {
                let newIndex = min(index, contexts.count - 1)
                state = .active(contexts: contexts, activeIndex: newIndex)
            }
            notifyChange()
            return
        }

        state = .active(contexts: contexts, activeIndex: index)

        let remaining = Int(contexts[index].remainingSeconds)
        let minutes = remaining / 60
        let seconds = remaining % 60
        remainingTimeFormatted = String(format: "%d:%02d", minutes, seconds)
        notifyChange()
    }

    private func accumulateElapsed(_ contexts: inout [CognitiveContext], at index: Int) {
        guard index >= 0 && index < contexts.count else { return }
        let now = Date()
        if let last = lastTickDate {
            contexts[index].elapsedSeconds += now.timeIntervalSince(last)
        }
        lastTickDate = now
    }

    // MARK: - Logging

    private func logContext(_ ctx: CognitiveContext, outcome: Session.Outcome) {
        let session = Session(
            id: ctx.id,
            label: ctx.label,
            intention: ctx.intention,
            timeboxMinutes: ctx.timeboxMinutes,
            elapsedSeconds: ctx.elapsedSeconds,
            todos: ctx.todos,
            startedAt: ctx.createdAt,
            endedAt: Date(),
            outcome: outcome
        )
        logger.log(session)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .sessionStateChanged, object: nil)
    }
}
