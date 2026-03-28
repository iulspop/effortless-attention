import Foundation
import Combine

extension Notification.Name {
    static let sessionStateChanged = Notification.Name("sessionStateChanged")
    static let needsIntention = Notification.Name("needsIntention")
    static let needsInterruptionIntention = Notification.Name("needsInterruptionIntention")
    static let timerExpired = Notification.Name("timerExpired")
}

/// A saved position on the interruption stack — where to return when the interruption ends.
struct InterruptionFrame: Codable {
    let contextIndex: Int
    let todo: TodoItem  // snapshot of the interrupted todo (for logging)
}

struct PersistedState: Codable {
    let contexts: [CognitiveContext]
    let activeIndex: Int
    var isPaused: Bool
    var interruptionStack: [InterruptionFrame]

    init(contexts: [CognitiveContext], activeIndex: Int, isPaused: Bool = false, interruptionStack: [InterruptionFrame] = []) {
        self.contexts = contexts
        self.activeIndex = activeIndex
        self.isPaused = isPaused
        self.interruptionStack = interruptionStack
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contexts = try container.decode([CognitiveContext].self, forKey: .contexts)
        activeIndex = try container.decode(Int.self, forKey: .activeIndex)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        interruptionStack = try container.decodeIfPresent([InterruptionFrame].self, forKey: .interruptionStack) ?? []
    }
}

@MainActor
class SessionManager: ObservableObject {
    @Published var contexts: [CognitiveContext] = []
    @Published var activeIndex: Int = 0
    @Published var remainingTimeFormatted: String = ""
    @Published var isPaused: Bool = false
    @Published var interruptionStack: [InterruptionFrame] = []

    private var timer: Timer?
    private let logger: SessionLogger
    private let transitionLogger: TransitionLogger
    private var lastTickDate: Date?
    var stateFileURL: URL

    init() {
        self.logger = SessionLogger()
        self.transitionLogger = TransitionLogger()
        self.stateFileURL = Self.defaultStateFile
        restoreState()
    }

    init(skipRestore: Bool, stateFileURL: URL? = nil, logger: SessionLogger? = nil, transitionLogger: TransitionLogger? = nil) {
        self.logger = logger ?? SessionLogger()
        self.transitionLogger = transitionLogger ?? TransitionLogger()
        self.stateFileURL = stateFileURL ?? Self.defaultStateFile
        if !skipRestore {
            restoreState()
        }
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

    /// Whether we're currently in an escape-hatch interruption
    var isInInterruption: Bool {
        !interruptionStack.isEmpty
    }

    /// How deep the interruption nesting is (0 = main flow)
    var interruptionDepth: Int {
        interruptionStack.count
    }

    // MARK: - Pause / Resume

    func pause() {
        guard !isPaused else { return }
        accumulateElapsed(at: activeIndex)
        stopTimer()
        isPaused = true
        notifyChange()
    }

    func resume(index: Int? = nil) {
        guard isPaused else { return }
        if let idx = index {
            activeIndex = idx
        }
        isPaused = false
        if hasActiveIntention {
            startTimer()
        }
        notifyChange()
    }

    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    // MARK: - Timer Expiry Actions

    /// Extend the current (expired) todo by adding more minutes
    func extendTime(minutes: Int) {
        guard activeIndex >= 0, activeIndex < contexts.count,
              let todoIndex = contexts[activeIndex].currentTodoIndex else { return }
        contexts[activeIndex].todos[todoIndex].timeboxMinutes += minutes
        startTimer()
        notifyChange()
    }

    /// Mark the expired todo as complete and advance
    func completeExpired() {
        if isInInterruption {
            completeInterruption()
            return
        }
        guard activeIndex >= 0, activeIndex < contexts.count,
              let todoIndex = contexts[activeIndex].currentTodoIndex else { return }
        let fromSnap = currentSnapshot()
        logTodo(contexts[activeIndex].todos[todoIndex], context: contexts[activeIndex], outcome: .expired)
        contexts[activeIndex].todos[todoIndex].completed = true
        advanceAfterTodoFinished()
        if let from = fromSnap, let to = currentSnapshot() {
            logTransition(.completion, from: from, to: to)
        }
        notifyChange()
    }

    // MARK: - Context Lifecycle

    func addContext(label: String, intention: String, minutes: Int) {
        let todo = TodoItem(text: intention, timeboxMinutes: minutes)
        let ctx = CognitiveContext(label: label, todos: [todo])
        let wasEmpty = contexts.isEmpty

        if contexts.isEmpty {
            contexts.append(ctx)
            activeIndex = 0
            startTimer()
        } else {
            contexts.append(ctx)
        }

        if wasEmpty, let snap = currentSnapshot() {
            logTransition(.start, from: nil, to: snap)
        }
        notifyChange()
    }

    func addTodoToActiveContext(text: String, minutes: Int) {
        guard !contexts.isEmpty, activeIndex >= 0, activeIndex < contexts.count else { return }
        let hadActive = contexts[activeIndex].hasActiveIntention
        let fromSnap = currentSnapshot()

        let todo = TodoItem(text: text, timeboxMinutes: minutes)
        contexts[activeIndex].todos.append(todo)

        // If timer wasn't running (no active todo before), start it
        if timer == nil && contexts[activeIndex].hasActiveIntention {
            startTimer()
        }

        // Log start transition when resuming work in a context that had no active todo
        if !hadActive, let to = currentSnapshot() {
            logTransition(.start, from: fromSnap, to: to)
        }
        notifyChange()
    }

    func addTodo(text: String, minutes: Int, at contextIndex: Int) {
        guard contextIndex >= 0, contextIndex < contexts.count else { return }
        let hadActive = contextIndex == activeIndex && contexts[contextIndex].hasActiveIntention
        let fromSnap = contextIndex == activeIndex ? currentSnapshot() : nil

        let todo = TodoItem(text: text, timeboxMinutes: minutes)
        contexts[contextIndex].todos.append(todo)

        // Start timer if this is the active context and it now has an intention
        if contextIndex == activeIndex && timer == nil && contexts[contextIndex].hasActiveIntention {
            startTimer()
        }

        // Log start transition when adding a todo reactivates the active context
        if contextIndex == activeIndex && !hadActive, let to = currentSnapshot() {
            logTransition(.start, from: fromSnap, to: to)
        }
        notifyChange()
    }

    func switchTo(index: Int) {
        guard index >= 0, index < contexts.count else { return }
        guard index != activeIndex else { return }
        guard !isInInterruption else { return } // Can't context-switch during interruption

        let fromSnap = currentSnapshot()

        // Pause current — snapshot elapsed time
        accumulateElapsed(at: activeIndex)

        activeIndex = index
        lastTickDate = Date()

        if let from = fromSnap, let to = snapshot(at: activeIndex) {
            logTransition(.contextSwitch, from: from, to: to)
        }

        // Ensure timer is running if new context has active intention
        if contexts[activeIndex].hasActiveIntention && timer == nil {
            startTimer()
        }
        notifyChange()
    }

    func cycleNext() {
        guard contexts.count > 1, !isInInterruption else { return }
        let next = (activeIndex + 1) % contexts.count
        switchTo(index: next)
    }

    func cyclePrev() {
        guard contexts.count > 1, !isInInterruption else { return }
        let prev = (activeIndex - 1 + contexts.count) % contexts.count
        switchTo(index: prev)
    }

    func complete() {
        if isInInterruption {
            completeInterruption()
            return
        }
        guard activeIndex >= 0, activeIndex < contexts.count else { return }
        guard let todoIndex = contexts[activeIndex].currentTodoIndex else { return }

        let fromSnap = currentSnapshot()

        accumulateElapsed(at: activeIndex)
        logTodo(contexts[activeIndex].todos[todoIndex], context: contexts[activeIndex], outcome: .completed)
        contexts[activeIndex].todos[todoIndex].completed = true
        advanceAfterTodoFinished()

        // Log completion transition — "to" is whatever we advanced to
        if let from = fromSnap, let to = currentSnapshot() {
            logTransition(.completion, from: from, to: to)
        }
        notifyChange()
    }

    /// Initiates the escape hatch flow. Pauses the current todo's timer and posts
    /// a notification so the UI can prompt for the interruption intention.
    /// If already in an interruption, the UI should show a guardrail confirmation first.
    func interrupt() {
        guard activeIndex >= 0, activeIndex < contexts.count else { return }
        guard let todoIndex = contexts[activeIndex].currentTodoIndex else { return }

        // Snapshot elapsed time before pausing
        accumulateElapsed(at: activeIndex)
        stopTimer()

        // Push current position onto the stack
        let frame = InterruptionFrame(
            contextIndex: activeIndex,
            todo: contexts[activeIndex].todos[todoIndex]
        )
        interruptionStack.append(frame)

        // Signal the UI to show the escape-hatch prompt
        NotificationCenter.default.post(name: .needsInterruptionIntention, object: nil)
        notifyChange()
    }

    /// Cancels the most recent interrupt() — user decided not to go through with the escape hatch.
    /// Pops the frame and restarts the original timer.
    func cancelInterrupt() {
        guard !interruptionStack.isEmpty else { return }
        interruptionStack.removeLast()
        if hasActiveIntention {
            startTimer()
        }
        notifyChange()
    }

    /// Called after the user declares what they're interrupting for.
    /// Creates an ephemeral context with a single todo and starts its timer.
    func beginInterruption(intention: String, minutes: Int) {
        // Snapshot the intention being interrupted (before switching)
        let fromSnap = currentSnapshot()

        let todo = TodoItem(text: intention, timeboxMinutes: minutes)
        let ctx = CognitiveContext(label: "⚡ Interruption", todos: [todo])
        contexts.append(ctx)
        activeIndex = contexts.count - 1

        if let from = fromSnap, let to = currentSnapshot() {
            logTransition(.interruption, from: from, to: to)
        }
        startTimer()
        notifyChange()
    }

    /// Completes/discards the current interruption and pops back to the previous context.
    func completeInterruption() {
        guard !interruptionStack.isEmpty else { return }

        let fromSnap = currentSnapshot()

        // Log the interruption todo
        if activeIndex >= 0, activeIndex < contexts.count,
           let todoIndex = contexts[activeIndex].currentTodoIndex {
            accumulateElapsed(at: activeIndex)
            logTodo(contexts[activeIndex].todos[todoIndex], context: contexts[activeIndex], outcome: .interrupted)
        }

        // Remove the ephemeral interruption context
        if activeIndex >= 0, activeIndex < contexts.count {
            contexts.remove(at: activeIndex)
        }

        // Pop the stack and restore previous position
        let frame = interruptionStack.removeLast()

        // Adjust the saved contextIndex if contexts shifted
        let restoredIndex = min(frame.contextIndex, contexts.count - 1)
        activeIndex = max(0, restoredIndex)

        // Log the return as a completion (popping back from escape hatch)
        if let from = fromSnap, let to = currentSnapshot() {
            logTransition(.completion, from: from, to: to)
        }

        // Resume the original todo's timer
        if hasActiveIntention {
            startTimer()
        }
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

    func updateTodoTimebox(_ minutes: Int, todoId: UUID, at contextIndex: Int) {
        guard contextIndex >= 0, contextIndex < contexts.count, minutes > 0 else { return }
        if let todoIndex = contexts[contextIndex].todos.firstIndex(where: { $0.id == todoId }) {
            contexts[contextIndex].todos[todoIndex].timeboxMinutes = minutes
            notifyChange()
        }
    }

    func moveTodo(todoId: UUID, direction: Int, at contextIndex: Int) {
        guard contextIndex >= 0, contextIndex < contexts.count else { return }
        guard let fromIndex = contexts[contextIndex].todos.firstIndex(where: { $0.id == todoId }) else { return }
        let toIndex = fromIndex + direction
        guard toIndex >= 0, toIndex < contexts[contextIndex].todos.count else { return }

        let beforeTodo = contextIndex == activeIndex ? contexts[contextIndex].currentTodo : nil
        let fromSnap = contextIndex == activeIndex ? currentSnapshot() : nil

        contexts[contextIndex].todos.swapAt(fromIndex, toIndex)

        // If reorder changed the current intention in the active context, log a context switch
        if contextIndex == activeIndex,
           let before = beforeTodo,
           let after = contexts[contextIndex].currentTodo,
           before.id != after.id,
           let from = fromSnap,
           let to = currentSnapshot() {
            logTransition(.contextSwitch, from: from, to: to)
        }
        notifyChange()
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

    func uncompleteTodo(todoId: UUID, at contextIndex: Int) {
        guard contextIndex >= 0, contextIndex < contexts.count else { return }
        guard let todoIndex = contexts[contextIndex].todos.firstIndex(where: { $0.id == todoId }) else { return }
        guard contexts[contextIndex].todos[todoIndex].completed else { return }

        contexts[contextIndex].todos[todoIndex].completed = false
        contexts[contextIndex].todos[todoIndex].elapsedSeconds = 0
        notifyChange()
    }

    func moveContext(from index: Int, direction: Int) {
        let toIndex = index + direction
        guard index >= 0, index < contexts.count,
              toIndex >= 0, toIndex < contexts.count else { return }
        contexts.swapAt(index, toIndex)

        // Keep activeIndex pointing at the same context
        if activeIndex == index {
            activeIndex = toIndex
        } else if activeIndex == toIndex {
            activeIndex = index
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
        if !isPaused {
            remainingTimeFormatted = ""
        }
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
            // Don't auto-complete — prompt user to extend or mark complete
            stopTimer()
            remainingTimeFormatted = "0:00"
            NotificationCenter.default.post(name: .timerExpired, object: nil)
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

    // MARK: - Transition Logging

    /// Snapshot the current active intention for transition events.
    /// Returns nil only when there are no contexts at all.
    private func currentSnapshot() -> CognitiveSnapshot? {
        guard activeIndex >= 0, activeIndex < contexts.count else { return nil }
        let todo = contexts[activeIndex].currentTodo
        return CognitiveSnapshot(
            contextId: contexts[activeIndex].id,
            contextLabel: contexts[activeIndex].label,
            todoId: todo?.id ?? contexts[activeIndex].id,
            todoText: todo?.text ?? "(idle)",
            timeboxMinutes: todo?.timeboxMinutes
        )
    }

    private func snapshot(at index: Int) -> CognitiveSnapshot? {
        guard index >= 0, index < contexts.count else { return nil }
        let todo = contexts[index].currentTodo
        return CognitiveSnapshot(
            contextId: contexts[index].id,
            contextLabel: contexts[index].label,
            todoId: todo?.id ?? contexts[index].id,
            todoText: todo?.text ?? "(idle)",
            timeboxMinutes: todo?.timeboxMinutes
        )
    }

    private func logTransition(_ type: TransitionEvent.TransitionType, from: CognitiveSnapshot?, to: CognitiveSnapshot, distractionText: String? = nil) {
        let event = TransitionEvent(
            type: type,
            from: from,
            to: to,
            interruptionDepth: interruptionStack.count,
            distractionText: distractionText
        )
        transitionLogger.log(event)
    }

    func logDistraction(_ text: String) {
        guard let snap = currentSnapshot() else { return }
        logTransition(.distraction, from: nil, to: snap, distractionText: text)
    }

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

    static var defaultStateFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Effortless", isDirectory: true)
        return dir.appendingPathComponent("state.json")
    }

    private func persistState() {
        let persisted = PersistedState(contexts: contexts, activeIndex: activeIndex, isPaused: isPaused, interruptionStack: interruptionStack)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(persisted) else { return }
        let dir = stateFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: stateFileURL)
    }

    private func restoreState() {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else { return }
        guard let data = try? Data(contentsOf: stateFileURL) else { return }
        guard let persisted = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        guard !persisted.contexts.isEmpty else { return }
        contexts = persisted.contexts
        activeIndex = min(persisted.activeIndex, persisted.contexts.count - 1)
        isPaused = persisted.isPaused
        interruptionStack = persisted.interruptionStack
        if !isPaused && contexts[activeIndex].hasActiveIntention {
            startTimer()
        }
    }
}
