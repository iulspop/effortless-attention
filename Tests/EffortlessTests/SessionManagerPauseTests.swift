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

@Suite("SessionManager — Pause/Resume")
@MainActor
struct SessionManagerPauseTests {

    @Test("pause sets isPaused to true")
    func pauseSetsFlag() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 25)
        mgr.pause()

        #expect(mgr.isPaused)
    }

    @Test("pause is no-op when already paused")
    func pauseIdempotent() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 25)
        mgr.pause()
        mgr.pause() // no-op
        #expect(mgr.isPaused)
    }

    @Test("resume clears isPaused")
    func resumeClears() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 25)
        mgr.pause()
        mgr.resume()

        #expect(!mgr.isPaused)
    }

    @Test("resume is no-op when not paused")
    func resumeIdempotent() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 25)
        mgr.resume() // not paused, no-op
        #expect(!mgr.isPaused)
    }

    @Test("resume with index switches active context")
    func resumeWithIndex() {
        let mgr = makeManager()
        mgr.addContext(label: "A", intention: "Task A", minutes: 5)
        mgr.addContext(label: "B", intention: "Task B", minutes: 10)
        mgr.pause()
        mgr.resume(index: 1)

        #expect(!mgr.isPaused)
        #expect(mgr.activeIndex == 1)
    }

    @Test("togglePause pauses when running")
    func togglePausePauses() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 25)
        mgr.togglePause()
        #expect(mgr.isPaused)
    }

    @Test("togglePause resumes when paused")
    func togglePauseResumes() {
        let mgr = makeManager()
        mgr.addContext(label: "Work", intention: "Task", minutes: 25)
        mgr.pause()
        mgr.togglePause()
        #expect(!mgr.isPaused)
    }
}
