import Testing
@testable import Effortless

// MARK: - TodoItem Tests

@Suite("TodoItem")
struct TodoItemTests {
    @Test("timeboxSeconds converts minutes to seconds")
    func timeboxSeconds() {
        let todo = TodoItem(text: "test", timeboxMinutes: 5)
        #expect(todo.timeboxSeconds == 300)
    }

    @Test("timeboxSeconds with zero minutes")
    func timeboxSecondsZero() {
        let todo = TodoItem(text: "test", timeboxMinutes: 0)
        #expect(todo.timeboxSeconds == 0)
    }

    @Test("remainingSeconds with no elapsed time")
    func remainingSecondsFull() {
        let todo = TodoItem(text: "test", timeboxMinutes: 5)
        #expect(todo.remainingSeconds == 300)
    }

    @Test("remainingSeconds with partial elapsed time")
    func remainingSecondsPartial() {
        var todo = TodoItem(text: "test", timeboxMinutes: 5)
        todo.elapsedSeconds = 120
        #expect(todo.remainingSeconds == 180)
    }

    @Test("remainingSeconds never goes below zero")
    func remainingSecondsFloor() {
        var todo = TodoItem(text: "test", timeboxMinutes: 5)
        todo.elapsedSeconds = 500
        #expect(todo.remainingSeconds == 0)
    }

    @Test("isExpired when elapsed exceeds timebox")
    func isExpiredTrue() {
        var todo = TodoItem(text: "test", timeboxMinutes: 1)
        todo.elapsedSeconds = 61
        #expect(todo.isExpired)
    }

    @Test("isExpired when elapsed equals timebox")
    func isExpiredExact() {
        var todo = TodoItem(text: "test", timeboxMinutes: 1)
        todo.elapsedSeconds = 60
        #expect(todo.isExpired)
    }

    @Test("not expired when time remaining")
    func isNotExpired() {
        var todo = TodoItem(text: "test", timeboxMinutes: 5)
        todo.elapsedSeconds = 10
        #expect(!todo.isExpired)
    }

    @Test("defaults: elapsedSeconds starts at zero, completed starts false")
    func defaults() {
        let todo = TodoItem(text: "test", timeboxMinutes: 5)
        #expect(todo.elapsedSeconds == 0)
        #expect(!todo.completed)
    }
}

// MARK: - CognitiveContext Tests

@Suite("CognitiveContext")
struct CognitiveContextTests {
    @Test("currentTodo returns first uncompleted todo")
    func currentTodo() {
        var completed = TodoItem(text: "done", timeboxMinutes: 5, completed: true)
        completed.elapsedSeconds = 300
        let active = TodoItem(text: "active", timeboxMinutes: 10)
        let ctx = CognitiveContext(label: "Work", todos: [completed, active])
        #expect(ctx.currentTodo?.text == "active")
    }

    @Test("currentTodo returns nil when all completed")
    func currentTodoAllCompleted() {
        let t1 = TodoItem(text: "done1", timeboxMinutes: 5, completed: true)
        let t2 = TodoItem(text: "done2", timeboxMinutes: 5, completed: true)
        let ctx = CognitiveContext(label: "Work", todos: [t1, t2])
        #expect(ctx.currentTodo == nil)
    }

    @Test("currentTodo returns nil when no todos")
    func currentTodoEmpty() {
        let ctx = CognitiveContext(label: "Work", todos: [])
        #expect(ctx.currentTodo == nil)
    }

    @Test("currentTodoIndex returns correct index")
    func currentTodoIndex() {
        let t1 = TodoItem(text: "done", timeboxMinutes: 5, completed: true)
        let t2 = TodoItem(text: "active", timeboxMinutes: 10)
        let ctx = CognitiveContext(label: "Work", todos: [t1, t2])
        #expect(ctx.currentTodoIndex == 1)
    }

    @Test("hasActiveIntention true when uncompleted todo exists")
    func hasActiveIntention() {
        let todo = TodoItem(text: "active", timeboxMinutes: 10)
        let ctx = CognitiveContext(label: "Work", todos: [todo])
        #expect(ctx.hasActiveIntention)
    }

    @Test("hasActiveIntention false when all completed")
    func hasNoActiveIntention() {
        let todo = TodoItem(text: "done", timeboxMinutes: 5, completed: true)
        let ctx = CognitiveContext(label: "Work", todos: [todo])
        #expect(!ctx.hasActiveIntention)
    }

    @Test("remainingSeconds delegates to current todo")
    func remainingSeconds() {
        var todo = TodoItem(text: "active", timeboxMinutes: 5)
        todo.elapsedSeconds = 120
        let ctx = CognitiveContext(label: "Work", todos: [todo])
        #expect(ctx.remainingSeconds == 180)
    }

    @Test("remainingSeconds is zero when no active todo")
    func remainingSecondsNoTodo() {
        let ctx = CognitiveContext(label: "Work", todos: [])
        #expect(ctx.remainingSeconds == 0)
    }

    @Test("todosCompleted counts only completed")
    func todosCompleted() {
        let t1 = TodoItem(text: "done", timeboxMinutes: 5, completed: true)
        let t2 = TodoItem(text: "active", timeboxMinutes: 10)
        let t3 = TodoItem(text: "done2", timeboxMinutes: 5, completed: true)
        let ctx = CognitiveContext(label: "Work", todos: [t1, t2, t3])
        #expect(ctx.todosCompleted == 2)
    }

    @Test("todosTotal counts all todos")
    func todosTotal() {
        let t1 = TodoItem(text: "one", timeboxMinutes: 5)
        let t2 = TodoItem(text: "two", timeboxMinutes: 10)
        let ctx = CognitiveContext(label: "Work", todos: [t1, t2])
        #expect(ctx.todosTotal == 2)
    }
}
