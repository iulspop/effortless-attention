import Testing
import Foundation
@testable import Effortless

@MainActor
private func makeManager() -> SessionManager {
    SessionManager(skipRestore: true)
}

@Suite("SessionManager — Editing Operations")
@MainActor
struct SessionManagerEditingTests {

    // MARK: - updateLabel

    @Test("updateLabel changes context label")
    func updateLabel() {
        let mgr = makeManager()
        mgr.addContext(label: "Old", intention: "Task", minutes: 5)
        mgr.updateLabel("New", at: 0)
        #expect(mgr.contexts[0].label == "New")
    }

    @Test("updateLabel out of bounds is no-op")
    func updateLabelOutOfBounds() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 5)
        mgr.updateLabel("New", at: 5)
        #expect(mgr.contexts[0].label == "Work")
    }

    // MARK: - updateTodoText

    @Test("updateTodoText changes todo text by ID")
    func updateTodoText() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Old text", minutes: 5)
        let todoId = mgr.contexts[0].todos[0].id
        mgr.updateTodoText("New text", todoId: todoId, at: 0)
        #expect(mgr.contexts[0].todos[0].text == "New text")
    }

    @Test("updateTodoText with non-existent ID is no-op")
    func updateTodoTextBadId() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 5)
        mgr.updateTodoText("New text", todoId: UUID(), at: 0)
        #expect(mgr.contexts[0].todos[0].text == "Task")
    }

    // MARK: - updateTodoTimebox

    @Test("updateTodoTimebox changes timebox minutes")
    func updateTodoTimebox() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 5)
        let todoId = mgr.contexts[0].todos[0].id
        mgr.updateTodoTimebox(25, todoId: todoId, at: 0)
        #expect(mgr.contexts[0].todos[0].timeboxMinutes == 25)
    }

    @Test("updateTodoTimebox ignores zero or negative")
    func updateTodoTimeboxInvalid() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 10)
        let todoId = mgr.contexts[0].todos[0].id
        mgr.updateTodoTimebox(0, todoId: todoId, at: 0)
        #expect(mgr.contexts[0].todos[0].timeboxMinutes == 10)
        mgr.updateTodoTimebox(-5, todoId: todoId, at: 0)
        #expect(mgr.contexts[0].todos[0].timeboxMinutes == 10)
    }

    // MARK: - moveTodo

    @Test("moveTodo swaps todo down")
    func moveTodoDown() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "First", minutes: 5)
        mgr.addTodoToActiveContext(text: "Second", minutes: 10)
        let firstId = mgr.contexts[0].todos[0].id
        mgr.moveTodo(todoId: firstId, direction: 1, at: 0)

        #expect(mgr.contexts[0].todos[0].text == "Second")
        #expect(mgr.contexts[0].todos[1].text == "First")
    }

    @Test("moveTodo swaps todo up")
    func moveTodoUp() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "First", minutes: 5)
        mgr.addTodoToActiveContext(text: "Second", minutes: 10)
        let secondId = mgr.contexts[0].todos[1].id
        mgr.moveTodo(todoId: secondId, direction: -1, at: 0)

        #expect(mgr.contexts[0].todos[0].text == "Second")
        #expect(mgr.contexts[0].todos[1].text == "First")
    }

    @Test("moveTodo at boundary is no-op")
    func moveTodoBoundary() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "First", minutes: 5)
        mgr.addTodoToActiveContext(text: "Second", minutes: 10)

        // Try to move first up (already at top)
        let firstId = mgr.contexts[0].todos[0].id
        mgr.moveTodo(todoId: firstId, direction: -1, at: 0)
        #expect(mgr.contexts[0].todos[0].text == "First")

        // Try to move last down (already at bottom)
        let secondId = mgr.contexts[0].todos[1].id
        mgr.moveTodo(todoId: secondId, direction: 1, at: 0)
        #expect(mgr.contexts[0].todos[1].text == "Second")
    }

    @Test("moveTodo with non-existent ID is no-op")
    func moveTodoBadId() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 5)
        mgr.moveTodo(todoId: UUID(), direction: 1, at: 0)
        #expect(mgr.contexts[0].todos[0].text == "Task")
    }

    // MARK: - removeTodo

    @Test("removeTodo removes by ID")
    func removeTodo() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 5)
        mgr.addTodoToActiveContext(text: "Task 2", minutes: 10)
        let todoId = mgr.contexts[0].todos[0].id
        mgr.removeTodo(todoId: todoId, at: 0)

        #expect(mgr.contexts[0].todos.count == 1)
        #expect(mgr.contexts[0].todos[0].text == "Task 2")
    }

    @Test("removeTodo with non-existent ID is no-op")
    func removeTodoBadId() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 5)
        mgr.removeTodo(todoId: UUID(), at: 0)
        #expect(mgr.contexts[0].todos.count == 1)
    }

    @Test("removeTodo current todo advances to next")
    func removeCurrentTodoAdvances() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task 1", minutes: 5)
        mgr.addTodoToActiveContext(text: "Task 2", minutes: 10)
        let currentId = mgr.contexts[0].currentTodo!.id
        mgr.removeTodo(todoId: currentId, at: 0)

        #expect(mgr.contexts[0].currentTodo?.text == "Task 2")
    }

    // MARK: - moveContext

    @Test("moveContext swaps adjacent contexts")
    func moveContextSwaps() {
        let mgr = makeManager()
        mgr.addContext(label: "A", intention: "t1", minutes: 5)
        mgr.addContext(label: "B", intention: "t2", minutes: 5)
        mgr.addContext(label: "C", intention: "t3", minutes: 5)

        mgr.moveContext(from: 0, direction: 1)
        #expect(mgr.contexts[0].label == "B")
        #expect(mgr.contexts[1].label == "A")
        #expect(mgr.contexts[2].label == "C")
    }

    @Test("moveContext tracks activeIndex when active context moves")
    func moveContextTracksActive() {
        let mgr = makeManager()
        mgr.addContext(label: "A", intention: "t1", minutes: 5)
        mgr.addContext(label: "B", intention: "t2", minutes: 5)
        // Active is 0 (A)
        #expect(mgr.activeIndex == 0)

        mgr.moveContext(from: 0, direction: 1)
        // A moved to index 1, activeIndex should follow
        #expect(mgr.activeIndex == 1)
        #expect(mgr.contexts[mgr.activeIndex].label == "A")
    }

    @Test("moveContext tracks activeIndex when displaced context is active")
    func moveContextTracksDisplaced() {
        let mgr = makeManager()
        mgr.addContext(label: "A", intention: "t1", minutes: 5)
        mgr.addContext(label: "B", intention: "t2", minutes: 5)
        mgr.switchTo(index: 1) // active = B at index 1

        mgr.moveContext(from: 0, direction: 1) // A moves to 1, B moves to 0
        #expect(mgr.activeIndex == 0)
        #expect(mgr.contexts[mgr.activeIndex].label == "B")
    }

    @Test("moveContext ignores out of bounds")
    func moveContextOutOfBounds() {
        let mgr = makeManager()
        mgr.addContext(label: "A", intention: "t1", minutes: 5)
        mgr.addContext(label: "B", intention: "t2", minutes: 5)

        mgr.moveContext(from: 0, direction: -1) // can't go up
        #expect(mgr.contexts[0].label == "A")

        mgr.moveContext(from: 1, direction: 1) // can't go down
        #expect(mgr.contexts[1].label == "B")
    }
}
