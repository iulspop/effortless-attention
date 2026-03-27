import Testing
import Foundation
@testable import Effortless

@MainActor
private func makeManager() -> SessionManager {
    let tempFile = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("state.json")
    return SessionManager(skipRestore: true, stateFileURL: tempFile)
}

@Suite("SessionManager — Interruption (Escape Hatch)")
@MainActor
struct SessionManagerInterruptionTests {

    // MARK: - interrupt() opens escape hatch

    @Test("interrupt pushes frame onto interruption stack")
    func interruptPushesFrame() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)
        mgr.interrupt()

        #expect(mgr.isInInterruption)
        #expect(mgr.interruptionDepth == 1)
        #expect(mgr.interruptionStack[0].contextIndex == 0)
        #expect(mgr.interruptionStack[0].todo.text == "Spreadsheet")
    }

    @Test("interrupt stops the timer")
    func interruptStopsTimer() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)
        mgr.interrupt()

        // Timer stopped — remainingTimeFormatted frozen (not blank, just not ticking)
        // The original todo is NOT marked completed
        #expect(!mgr.contexts[0].todos[0].completed)
    }

    @Test("interrupt with no contexts is no-op")
    func interruptNoContexts() {
        let mgr = makeManager()
        mgr.interrupt()
        #expect(!mgr.isInInterruption)
    }

    @Test("interrupt with no active todo is no-op")
    func interruptNoActiveTodo() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 5)
        mgr.complete()
        mgr.interrupt() // no active todo left
        #expect(!mgr.isInInterruption)
    }

    // MARK: - beginInterruption()

    @Test("beginInterruption creates ephemeral context and switches to it")
    func beginInterruptionCreatesContext() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)
        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)

        #expect(mgr.contexts.count == 2)
        #expect(mgr.activeIndex == 1)
        #expect(mgr.activeContext?.label == "⚡ Interruption")
        #expect(mgr.activeContext?.currentTodo?.text == "Check Amazon")
        #expect(mgr.activeContext?.currentTodo?.timeboxMinutes == 5)
    }

    // MARK: - completeInterruption()

    @Test("completeInterruption removes ephemeral context and restores position")
    func completeInterruptionRestores() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)
        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)
        mgr.completeInterruption()

        #expect(mgr.contexts.count == 1)
        #expect(mgr.activeIndex == 0)
        #expect(mgr.activeContext?.label == "Work")
        #expect(mgr.activeContext?.currentTodo?.text == "Spreadsheet")
        #expect(!mgr.isInInterruption)
    }

    @Test("completeInterruption when not in interruption is no-op")
    func completeInterruptionNoOp() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 5)
        mgr.completeInterruption() // no-op
        #expect(mgr.contexts.count == 1)
    }

    @Test("original todo timer resumes after completing interruption")
    func originalTodoTimerResumes() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)

        // Simulate some elapsed time
        mgr.contexts[0].todos[0].elapsedSeconds = 300 // 5 min elapsed

        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)
        mgr.completeInterruption()

        // Original todo's elapsed time should be preserved (not reset)
        #expect(mgr.contexts[0].todos[0].elapsedSeconds >= 300)
        #expect(!mgr.contexts[0].todos[0].completed)
        #expect(mgr.hasActiveIntention)
    }

    // MARK: - Nesting

    @Test("interruptions can nest — each pushes a new frame")
    func interruptionsNest() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)

        // First interruption
        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)
        #expect(mgr.interruptionDepth == 1)

        // Nested interruption
        mgr.interrupt()
        mgr.beginInterruption(intention: "Reply to Slack", minutes: 2)
        #expect(mgr.interruptionDepth == 2)
        #expect(mgr.contexts.count == 3)
        #expect(mgr.activeContext?.currentTodo?.text == "Reply to Slack")
    }

    @Test("completing nested interruption pops back one level")
    func completingNestedPopsOneLevel() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)

        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)
        mgr.interrupt()
        mgr.beginInterruption(intention: "Reply to Slack", minutes: 2)

        // Pop back to first interruption
        mgr.completeInterruption()
        #expect(mgr.interruptionDepth == 1)
        #expect(mgr.activeContext?.currentTodo?.text == "Check Amazon")
        #expect(mgr.contexts.count == 2)

        // Pop back to main flow
        mgr.completeInterruption()
        #expect(mgr.interruptionDepth == 0)
        #expect(mgr.activeContext?.currentTodo?.text == "Spreadsheet")
        #expect(mgr.contexts.count == 1)
        #expect(!mgr.isInInterruption)
    }

    // MARK: - Context switching blocked during interruption

    @Test("switchTo is blocked during interruption")
    func switchToBlockedDuringInterruption() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)
        mgr.addContext(label: "Personal", intention: "Email", minutes: 10)

        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)

        // Try to switch — should be blocked
        mgr.switchTo(index: 1)
        #expect(mgr.activeIndex == 2) // still on ephemeral context
    }

    @Test("cycleNext is blocked during interruption")
    func cycleNextBlockedDuringInterruption() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)
        mgr.addContext(label: "Personal", intention: "Email", minutes: 10)

        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)

        let indexBefore = mgr.activeIndex
        mgr.cycleNext()
        #expect(mgr.activeIndex == indexBefore) // unchanged
    }

    @Test("cyclePrev is blocked during interruption")
    func cyclePrevBlockedDuringInterruption() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)
        mgr.addContext(label: "Personal", intention: "Email", minutes: 10)

        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)

        let indexBefore = mgr.activeIndex
        mgr.cyclePrev()
        #expect(mgr.activeIndex == indexBefore) // unchanged
    }

    // MARK: - Multiple contexts with interruption

    @Test("interrupt from non-first context restores correctly")
    func interruptFromSecondContext() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Spreadsheet", minutes: 25)
        mgr.addContext(label: "Personal", intention: "Email", minutes: 10)
        mgr.switchTo(index: 1)

        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)

        #expect(mgr.interruptionStack[0].contextIndex == 1)

        mgr.completeInterruption()

        #expect(mgr.activeIndex == 1)
        #expect(mgr.activeContext?.label == "Personal")
        #expect(mgr.activeContext?.currentTodo?.text == "Email")
    }
}
