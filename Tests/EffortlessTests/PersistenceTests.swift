import Testing
import Foundation
@testable import Effortless

@Suite("Persistence Integration")
@MainActor
struct PersistenceTests {

    /// Creates a temp directory and returns its URL. Caller should clean up.
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("persist and restore contexts round-trip")
    func roundTrip() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let stateFile = dir.appendingPathComponent("state.json")

        // Create manager, add contexts
        let tLogger = TransitionLogger(directory: dir)
        let mgr1 = SessionManager(skipRestore: true, stateFileURL: stateFile, transitionLogger: tLogger)
        mgr1.addContext(label: "Work", intention: "Write code", minutes: 25)
        mgr1.addContext(label: "Personal", intention: "Read book", minutes: 15)
        mgr1.addTodoToActiveContext(text: "Write tests", minutes: 10)
        mgr1.switchTo(index: 1)

        // State file should exist
        #expect(FileManager.default.fileExists(atPath: stateFile.path))

        // Create new manager that restores from same file
        let mgr2 = SessionManager(skipRestore: false, stateFileURL: stateFile, transitionLogger: tLogger)

        #expect(mgr2.contexts.count == 2)
        #expect(mgr2.contexts[0].label == "Work")
        #expect(mgr2.contexts[0].todos.count == 2)
        #expect(mgr2.contexts[1].label == "Personal")
        #expect(mgr2.activeIndex == 1)
    }

    @Test("persist preserves pause state")
    func persistsPauseState() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let stateFile = dir.appendingPathComponent("state.json")

        let tLogger = TransitionLogger(directory: dir)
        let mgr1 = SessionManager(skipRestore: true, stateFileURL: stateFile, transitionLogger: tLogger)
        mgr1.addContext(label: "Work", intention: "Task", minutes: 25)
        mgr1.pause()

        let mgr2 = SessionManager(skipRestore: false, stateFileURL: stateFile, transitionLogger: tLogger)
        #expect(mgr2.isPaused)
    }

    @Test("empty contexts persists empty state (does not delete file)")
    func emptyContextsPersistsEmptyState() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let stateFile = dir.appendingPathComponent("state.json")

        let tLogger = TransitionLogger(directory: dir)
        let mgr = SessionManager(skipRestore: true, stateFileURL: stateFile, transitionLogger: tLogger)
        mgr.addContext(label: "Work", intention: "Task", minutes: 25)
        #expect(FileManager.default.fileExists(atPath: stateFile.path))

        mgr.removeContext(at: 0)
        #expect(FileManager.default.fileExists(atPath: stateFile.path))

        // Restoring from the empty-state file should yield empty contexts
        let mgr2 = SessionManager(skipRestore: false, stateFileURL: stateFile, transitionLogger: tLogger)
        #expect(mgr2.contexts.isEmpty)
    }

    @Test("backward compatibility: old JSON without isPaused decodes with default false")
    func backwardCompatibility() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let stateFile = dir.appendingPathComponent("state.json")

        // Write old-format JSON (no isPaused field)
        let oldJSON = """
        {
            "contexts": [
                {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "label": "Legacy",
                    "todos": [
                        {
                            "id": "22222222-2222-2222-2222-222222222222",
                            "text": "Old task",
                            "timeboxMinutes": 10,
                            "elapsedSeconds": 0,
                            "completed": false
                        }
                    ],
                    "createdAt": 0
                }
            ],
            "activeIndex": 0
        }
        """
        try oldJSON.data(using: .utf8)!.write(to: stateFile)

        let tLogger = TransitionLogger(directory: dir)
        let mgr = SessionManager(skipRestore: false, stateFileURL: stateFile, transitionLogger: tLogger)
        #expect(mgr.contexts.count == 1)
        #expect(mgr.contexts[0].label == "Legacy")
        #expect(!mgr.isPaused)
    }

    @Test("restore from non-existent file starts empty")
    func restoreNoFile() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let stateFile = dir.appendingPathComponent("nonexistent.json")

        let tLogger = TransitionLogger(directory: dir)
        let mgr = SessionManager(skipRestore: false, stateFileURL: stateFile, transitionLogger: tLogger)
        #expect(mgr.contexts.isEmpty)
        #expect(mgr.activeIndex == 0)
    }

    @Test("restore from corrupt file starts empty")
    func restoreCorruptFile() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let stateFile = dir.appendingPathComponent("state.json")

        try "not valid json {{{".data(using: .utf8)!.write(to: stateFile)

        let tLogger = TransitionLogger(directory: dir)
        let mgr = SessionManager(skipRestore: false, stateFileURL: stateFile, transitionLogger: tLogger)
        #expect(mgr.contexts.isEmpty)
    }

    @Test("restore clamps activeIndex if out of range")
    func restoreClampsIndex() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let stateFile = dir.appendingPathComponent("state.json")

        // Write JSON with activeIndex beyond contexts length
        let json = """
        {
            "contexts": [
                {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "label": "Only",
                    "todos": [
                        {
                            "id": "22222222-2222-2222-2222-222222222222",
                            "text": "Task",
                            "timeboxMinutes": 5,
                            "elapsedSeconds": 0,
                            "completed": false
                        }
                    ],
                    "createdAt": 0
                }
            ],
            "activeIndex": 99
        }
        """
        try json.data(using: .utf8)!.write(to: stateFile)

        let tLogger = TransitionLogger(directory: dir)
        let mgr = SessionManager(skipRestore: false, stateFileURL: stateFile, transitionLogger: tLogger)
        #expect(mgr.activeIndex == 0) // clamped to contexts.count - 1
    }
}
