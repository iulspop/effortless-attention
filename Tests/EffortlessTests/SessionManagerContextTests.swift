import Testing
import Foundation
@testable import Effortless

@Suite("SessionManager — Context Lifecycle")
@MainActor
struct SessionManagerContextTests {
    /// Create a clean SessionManager for testing (no disk restore, no real timer effects)
    private func makeSUT() -> SessionManager {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let tempFile = tempDir.appendingPathComponent("state.json")
        let tLogger = TransitionLogger(directory: tempDir)
        return SessionManager(skipRestore: true, stateFileURL: tempFile, transitionLogger: tLogger)
    }

    // MARK: - addContext

    @Test func addFirstContextSetsActiveIndex() {
        let sm = makeSUT()
        sm.addContext(label: "Work", intention: "Build feature", minutes: 25)

        #expect(sm.contexts.count == 1)
        #expect(sm.activeIndex == 0)
        #expect(sm.contexts[0].label == "Work")
        #expect(sm.contexts[0].todos.count == 1)
        #expect(sm.contexts[0].todos[0].text == "Build feature")
        #expect(sm.contexts[0].todos[0].timeboxMinutes == 25)
    }

    @Test func addSecondContextAppends() {
        let sm = makeSUT()
        sm.addContext(label: "Work", intention: "Task 1", minutes: 25)
        sm.addContext(label: "Study", intention: "Task 2", minutes: 15)

        #expect(sm.contexts.count == 2)
        #expect(sm.activeIndex == 0) // stays on first
        #expect(sm.contexts[1].label == "Study")
    }

    // MARK: - addTodoToActiveContext

    @Test func addTodoToActiveContextAppends() {
        let sm = makeSUT()
        sm.addContext(label: "Work", intention: "First", minutes: 25)
        sm.addTodoToActiveContext(text: "Second", minutes: 10)

        #expect(sm.contexts[0].todos.count == 2)
        #expect(sm.contexts[0].todos[1].text == "Second")
        #expect(sm.contexts[0].todos[1].timeboxMinutes == 10)
    }

    @Test func addTodoToActiveContextGuardsEmpty() {
        let sm = makeSUT()
        sm.addTodoToActiveContext(text: "Orphan", minutes: 5)
        #expect(sm.contexts.isEmpty)
    }

    // MARK: - addTodo(at:)

    @Test func addTodoAtSpecificContext() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "Task A", minutes: 5)
        sm.addContext(label: "B", intention: "Task B", minutes: 5)
        sm.addTodo(text: "Extra for B", minutes: 10, at: 1)

        #expect(sm.contexts[1].todos.count == 2)
        #expect(sm.contexts[1].todos[1].text == "Extra for B")
    }

    @Test func addTodoAtInvalidIndexDoesNothing() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "Task A", minutes: 5)
        sm.addTodo(text: "Invalid", minutes: 10, at: 5)

        #expect(sm.contexts[0].todos.count == 1)
    }

    // MARK: - switchTo

    @Test func switchToChangesActiveIndex() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)
        sm.addContext(label: "B", intention: "T2", minutes: 5)

        sm.switchTo(index: 1)
        #expect(sm.activeIndex == 1)
    }

    @Test func switchToSameIndexIsNoop() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)

        sm.switchTo(index: 0) // same index
        #expect(sm.activeIndex == 0)
    }

    @Test func switchToInvalidIndexIsNoop() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)

        sm.switchTo(index: 99)
        #expect(sm.activeIndex == 0)
    }

    @Test func switchToNegativeIndexIsNoop() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)

        sm.switchTo(index: -1)
        #expect(sm.activeIndex == 0)
    }

    // MARK: - cycleNext / cyclePrev

    @Test func cycleNextWrapsAround() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)
        sm.addContext(label: "B", intention: "T2", minutes: 5)
        sm.addContext(label: "C", intention: "T3", minutes: 5)

        #expect(sm.activeIndex == 0)
        sm.cycleNext()
        #expect(sm.activeIndex == 1)
        sm.cycleNext()
        #expect(sm.activeIndex == 2)
        sm.cycleNext()
        #expect(sm.activeIndex == 0) // wraps
    }

    @Test func cyclePrevWrapsAround() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)
        sm.addContext(label: "B", intention: "T2", minutes: 5)
        sm.addContext(label: "C", intention: "T3", minutes: 5)

        #expect(sm.activeIndex == 0)
        sm.cyclePrev()
        #expect(sm.activeIndex == 2) // wraps to end
        sm.cyclePrev()
        #expect(sm.activeIndex == 1)
    }

    @Test func cycleNextNoopWithSingleContext() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)

        sm.cycleNext()
        #expect(sm.activeIndex == 0)
    }

    @Test func cyclePrevNoopWithSingleContext() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)

        sm.cyclePrev()
        #expect(sm.activeIndex == 0)
    }

    // MARK: - removeContext

    @Test func removeOnlyContextResetsState() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)

        sm.removeContext(at: 0)
        #expect(sm.contexts.isEmpty)
        #expect(sm.activeIndex == 0)
    }

    @Test func removeActiveContextAdjustsIndex() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)
        sm.addContext(label: "B", intention: "T2", minutes: 5)
        sm.addContext(label: "C", intention: "T3", minutes: 5)
        sm.switchTo(index: 1) // active = B

        sm.removeContext(at: 1) // remove B
        #expect(sm.contexts.count == 2)
        #expect(sm.activeIndex == 1) // now C (clamped)
        #expect(sm.contexts[sm.activeIndex].label == "C")
    }

    @Test func removeBeforeActiveAdjustsIndex() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)
        sm.addContext(label: "B", intention: "T2", minutes: 5)
        sm.addContext(label: "C", intention: "T3", minutes: 5)
        sm.switchTo(index: 2) // active = C

        sm.removeContext(at: 0) // remove A
        #expect(sm.contexts.count == 2)
        #expect(sm.activeIndex == 1) // decremented
        #expect(sm.contexts[sm.activeIndex].label == "C")
    }

    @Test func removeAfterActiveKeepsIndex() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)
        sm.addContext(label: "B", intention: "T2", minutes: 5)
        sm.addContext(label: "C", intention: "T3", minutes: 5)

        sm.removeContext(at: 2) // remove C, active = A (0)
        #expect(sm.contexts.count == 2)
        #expect(sm.activeIndex == 0)
        #expect(sm.contexts[sm.activeIndex].label == "A")
    }

    @Test func removeLastActiveContextClamps() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)
        sm.addContext(label: "B", intention: "T2", minutes: 5)
        sm.switchTo(index: 1) // active = B (last)

        sm.removeContext(at: 1) // remove B
        #expect(sm.contexts.count == 1)
        #expect(sm.activeIndex == 0) // clamped to last valid
    }

    @Test func removeContextInvalidIndexDoesNothing() {
        let sm = makeSUT()
        sm.addContext(label: "A", intention: "T1", minutes: 5)

        sm.removeContext(at: 5)
        #expect(sm.contexts.count == 1)
    }
}
