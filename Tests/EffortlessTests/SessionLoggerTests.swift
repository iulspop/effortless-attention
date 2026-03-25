import Testing
import Foundation
@testable import Effortless

@Suite("SessionLogger Integration")
struct SessionLoggerTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeSession(
        intention: String = "Test task",
        minutes: Int = 25,
        outcome: Session.Outcome = .completed
    ) -> Session {
        Session(
            id: UUID(),
            label: "Test",
            intention: intention,
            timeboxMinutes: minutes,
            elapsedSeconds: Double(minutes * 60),
            todos: [TodoItem(text: intention, timeboxMinutes: minutes)],
            startedAt: Date(),
            endedAt: Date(),
            outcome: outcome
        )
    }

    @Test("log and loadAll round-trip")
    func roundTrip() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = SessionLogger(directory: dir)
        let session = makeSession(intention: "Write tests")
        logger.log(session)

        let loaded = logger.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].intention == "Write tests")
        #expect(loaded[0].outcome == .completed)
    }

    @Test("multiple sessions logged in order")
    func multipleSessionsOrder() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = SessionLogger(directory: dir)
        logger.log(makeSession(intention: "First"))
        logger.log(makeSession(intention: "Second"))
        logger.log(makeSession(intention: "Third"))

        let loaded = logger.loadAll()
        #expect(loaded.count == 3)
        #expect(loaded[0].intention == "First")
        #expect(loaded[1].intention == "Second")
        #expect(loaded[2].intention == "Third")
    }

    @Test("loadAll returns empty when no file exists")
    func loadAllEmpty() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = SessionLogger(directory: dir)
        #expect(logger.loadAll().isEmpty)
    }

    @Test("session outcomes are preserved")
    func outcomesPreserved() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = SessionLogger(directory: dir)
        logger.log(makeSession(outcome: .completed))
        logger.log(makeSession(outcome: .interrupted))
        logger.log(makeSession(outcome: .expired))

        let loaded = logger.loadAll()
        #expect(loaded[0].outcome == .completed)
        #expect(loaded[1].outcome == .interrupted)
        #expect(loaded[2].outcome == .expired)
    }

    @Test("session data fields are preserved")
    func dataFieldsPreserved() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let logger = SessionLogger(directory: dir)
        let session = Session(
            id: UUID(),
            label: "Deep Work",
            intention: "Build feature X",
            timeboxMinutes: 90,
            elapsedSeconds: 5400,
            todos: [
                TodoItem(text: "Build feature X", timeboxMinutes: 90, completed: true),
                TodoItem(text: "Review PR", timeboxMinutes: 15)
            ],
            startedAt: Date(),
            endedAt: Date(),
            outcome: .completed
        )
        logger.log(session)

        let loaded = logger.loadAll()
        #expect(loaded[0].label == "Deep Work")
        #expect(loaded[0].intention == "Build feature X")
        #expect(loaded[0].timeboxMinutes == 90)
        #expect(loaded[0].elapsedSeconds == 5400)
        #expect(loaded[0].todos.count == 2)
    }
}
