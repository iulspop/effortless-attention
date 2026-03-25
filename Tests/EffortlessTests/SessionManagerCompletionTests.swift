import Testing
import Foundation
@testable import Effortless

@MainActor
private func makeManager() -> SessionManager {
    SessionManager(skipRestore: true)
}

@Suite("SessionManager — Todo Completion Flow")
@MainActor
struct SessionManagerCompletionTests {

    // MARK: - complete()

    @Test("complete marks current todo as completed")
    func completeMarksDone() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 25)
        mgr.addTodoToActiveContext(text: "Task 2", minutes: 10)
        mgr.complete()

        #expect(mgr.contexts[0].todos[0].completed)
        #expect(!mgr.contexts[0].todos[1].completed)
    }

    @Test("complete advances to next todo in queue")
    func completeAdvancesToNext() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 25)
        mgr.addTodoToActiveContext(text: "Task 2", minutes: 10)
        mgr.complete()

        #expect(mgr.contexts[0].currentTodo?.text == "Task 2")
        #expect(mgr.hasActiveIntention)
    }

    @Test("complete with no contexts is no-op")
    func completeNoContexts() {
        let mgr = makeManager()
        mgr.complete() // should not crash
        #expect(mgr.contexts.isEmpty)
    }

    @Test("complete with no active todo is no-op")
    func completeNoActiveTodo() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 25)
        mgr.complete() // complete the only todo
        mgr.complete() // no-op, no active todo left
        #expect(mgr.contexts[0].todos.count == 1)
        #expect(mgr.contexts[0].todos[0].completed)
    }

    // MARK: - interrupt()

    @Test("interrupt marks current todo as completed (logged as interrupted)")
    func interruptMarksDone() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 25)
        mgr.interrupt()

        #expect(mgr.contexts[0].todos[0].completed)
    }

    @Test("interrupt advances to next todo in queue")
    func interruptAdvances() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 25)
        mgr.addTodoToActiveContext(text: "Task 2", minutes: 10)
        mgr.interrupt()

        #expect(mgr.contexts[0].currentTodo?.text == "Task 2")
    }

    // MARK: - advanceAfterTodoFinished (tested via complete/interrupt)

    @Test("complete switches to next context when current context queue is empty")
    func completeSwitchesContext() {
        let mgr = makeManager()
        mgr.addContext(label: "A", intention: "Task A", minutes: 5)
        mgr.addContext(label: "B", intention: "Task B", minutes: 10)

        // Complete the only todo in context A
        mgr.complete()

        // Should auto-switch to context B
        #expect(mgr.activeIndex == 1)
        #expect(mgr.activeContext?.label == "B")
    }

    @Test("complete wraps around when searching for next context with work")
    func completeSwitchesContextWraparound() {
        let mgr = makeManager()
        mgr.addContext(label: "A", intention: "Task A", minutes: 5)
        mgr.addContext(label: "B", intention: "Task B", minutes: 10)
        mgr.addContext(label: "C", intention: "Task C", minutes: 15)

        // Switch to C, complete it
        mgr.switchTo(index: 2)
        mgr.complete()

        // Should wrap to A (index 0)
        #expect(mgr.activeIndex == 0)
        #expect(mgr.activeContext?.label == "A")
    }

    @Test("complete stays on current context if more todos remain")
    func completeStaysIfMoreTodos() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 25)
        mgr.addTodoToActiveContext(text: "Task 2", minutes: 10)
        mgr.complete()

        #expect(mgr.activeIndex == 0)
        #expect(mgr.contexts[0].currentTodo?.text == "Task 2")
    }

    // MARK: - extendTime

    @Test("extendTime adds minutes to current todo timebox")
    func extendTimeAddsMinutes() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 5)
        mgr.extendTime(minutes: 10)

        #expect(mgr.contexts[0].todos[0].timeboxMinutes == 15)
    }

    @Test("extendTime no-op when no contexts")
    func extendTimeNoContexts() {
        let mgr = makeManager()
        mgr.extendTime(minutes: 10) // should not crash
    }

    // MARK: - completeExpired

    @Test("completeExpired marks current todo completed and advances")
    func completeExpiredAdvances() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 1)
        mgr.addTodoToActiveContext(text: "Task 2", minutes: 10)

        // Simulate expiry by setting elapsed past timebox
        mgr.contexts[0].todos[0].elapsedSeconds = 120
        mgr.completeExpired()

        #expect(mgr.contexts[0].todos[0].completed)
        #expect(mgr.contexts[0].currentTodo?.text == "Task 2")
    }
}
