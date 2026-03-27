import Testing
import Foundation
@testable import Effortless

@Suite("TransitionLogger")
struct TransitionLoggerTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeSnapshot(label: String = "Work", text: String = "Build feature") -> CognitiveSnapshot {
        CognitiveSnapshot(contextId: UUID(), contextLabel: label, todoId: UUID(), todoText: text)
    }

    @Test("log and loadAll round-trip")
    func roundTrip() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = TransitionLogger(directory: dir)
        let event = TransitionEvent(type: .start, from: nil, to: makeSnapshot())
        logger.log(event)

        let loaded = logger.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].type == .start)
        #expect(loaded[0].from == nil)
        #expect(loaded[0].to.contextLabel == "Work")
    }

    @Test("multiple events append in order")
    func appendOrder() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = TransitionLogger(directory: dir)
        let snap1 = makeSnapshot(text: "First")
        let snap2 = makeSnapshot(text: "Second")
        let snap3 = makeSnapshot(text: "Third")

        logger.log(TransitionEvent(type: .start, from: nil, to: snap1))
        logger.log(TransitionEvent(type: .completion, from: snap1, to: snap2))
        logger.log(TransitionEvent(type: .contextSwitch, from: snap2, to: snap3))

        let loaded = logger.loadAll()
        #expect(loaded.count == 3)
        #expect(loaded[0].to.todoText == "First")
        #expect(loaded[1].to.todoText == "Second")
        #expect(loaded[2].to.todoText == "Third")
    }

    @Test("loadAll returns empty when no file exists")
    func loadAllEmpty() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = TransitionLogger(directory: dir)
        #expect(logger.loadAll().isEmpty)
    }

    @Test("all transition types preserved")
    func typesPreserved() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = TransitionLogger(directory: dir)
        let snap = makeSnapshot()

        logger.log(TransitionEvent(type: .start, from: nil, to: snap))
        logger.log(TransitionEvent(type: .completion, from: snap, to: snap))
        logger.log(TransitionEvent(type: .interruption, from: snap, to: snap))
        logger.log(TransitionEvent(type: .contextSwitch, from: snap, to: snap))

        let loaded = logger.loadAll()
        #expect(loaded[0].type == .start)
        #expect(loaded[1].type == .completion)
        #expect(loaded[2].type == .interruption)
        #expect(loaded[3].type == .contextSwitch)
    }

    @Test("interruptionDepth preserved")
    func depthPreserved() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = TransitionLogger(directory: dir)
        let snap = makeSnapshot()

        logger.log(TransitionEvent(type: .interruption, from: snap, to: snap, interruptionDepth: 0))
        logger.log(TransitionEvent(type: .interruption, from: snap, to: snap, interruptionDepth: 1))
        logger.log(TransitionEvent(type: .completion, from: snap, to: snap, interruptionDepth: 2))

        let loaded = logger.loadAll()
        #expect(loaded[0].interruptionDepth == 0)
        #expect(loaded[1].interruptionDepth == 1)
        #expect(loaded[2].interruptionDepth == 2)
    }

    @Test("loadToday filters to current day")
    func loadTodayFilters() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = TransitionLogger(directory: dir)
        let snap = makeSnapshot()

        // Yesterday's event
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        logger.log(TransitionEvent(timestamp: yesterday, type: .start, from: nil, to: snap))

        // Today's event
        logger.log(TransitionEvent(type: .completion, from: snap, to: snap))

        let all = logger.loadAll()
        #expect(all.count == 2)

        let today = logger.loadToday()
        #expect(today.count == 1)
        #expect(today[0].type == .completion)
    }

    @Test("snapshot fields preserved")
    func snapshotFields() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = TransitionLogger(directory: dir)
        let contextId = UUID()
        let todoId = UUID()
        let from = CognitiveSnapshot(contextId: contextId, contextLabel: "Deep Work", todoId: todoId, todoText: "Write report")
        let to = CognitiveSnapshot(contextId: UUID(), contextLabel: "Email", todoId: UUID(), todoText: "Reply to boss")

        logger.log(TransitionEvent(type: .contextSwitch, from: from, to: to))

        let loaded = logger.loadAll()
        #expect(loaded[0].from?.contextId == contextId)
        #expect(loaded[0].from?.contextLabel == "Deep Work")
        #expect(loaded[0].from?.todoId == todoId)
        #expect(loaded[0].from?.todoText == "Write report")
        #expect(loaded[0].to.contextLabel == "Email")
        #expect(loaded[0].to.todoText == "Reply to boss")
    }
}
