import Testing
import Foundation
@testable import Effortless

@Suite("SessionManager — Transition Events")
@MainActor
struct SessionManagerTransitionTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeManager(dir: URL) -> (SessionManager, TransitionLogger) {
        let stateFile = dir.appendingPathComponent("state.json")
        let tLogger = TransitionLogger(directory: dir)
        let mgr = SessionManager(skipRestore: true, stateFileURL: stateFile, transitionLogger: tLogger)
        return (mgr, tLogger)
    }

    @Test("adding first context logs start transition")
    func startTransition() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Build feature", minutes: 25)

        let events = tLog.loadAll()
        #expect(events.count == 1)
        #expect(events[0].type == .start)
        #expect(events[0].from == nil)
        #expect(events[0].to.contextLabel == "Work")
        #expect(events[0].to.todoText == "Build feature")
        #expect(events[0].interruptionDepth == 0)
    }

    @Test("adding second context does not log start")
    func secondContextNoStart() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Build feature", minutes: 25)
        mgr.addContext(label: "Email", intention: "Reply to boss", minutes: 10)

        let events = tLog.loadAll()
        #expect(events.count == 1) // only the start event
        #expect(events[0].type == .start)
    }

    @Test("switchTo logs contextSwitch transition")
    func contextSwitchTransition() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Build feature", minutes: 25)
        mgr.addContext(label: "Email", intention: "Reply to boss", minutes: 10)
        mgr.switchTo(index: 1)

        let events = tLog.loadAll()
        #expect(events.count == 2) // start + contextSwitch
        let cs = events[1]
        #expect(cs.type == .contextSwitch)
        #expect(cs.from?.contextLabel == "Work")
        #expect(cs.to.contextLabel == "Email")
        #expect(cs.interruptionDepth == 0)
    }

    @Test("complete logs completion transition")
    func completionTransition() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "First task", minutes: 25)
        mgr.addTodoToActiveContext(text: "Second task", minutes: 15)
        mgr.complete()

        let events = tLog.loadAll()
        #expect(events.count == 2) // start + completion
        let comp = events[1]
        #expect(comp.type == .completion)
        #expect(comp.from?.todoText == "First task")
        #expect(comp.to.todoText == "Second task")
    }

    @Test("beginInterruption logs interruption transition")
    func interruptionTransition() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Build feature", minutes: 25)
        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)

        let events = tLog.loadAll()
        #expect(events.count == 2) // start + interruption
        let intr = events[1]
        #expect(intr.type == .interruption)
        #expect(intr.from?.todoText == "Build feature")
        #expect(intr.to.todoText == "Check Amazon")
        #expect(intr.interruptionDepth == 1) // we're now 1 deep
    }

    @Test("completeInterruption logs completion back to original")
    func interruptionReturnTransition() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Build feature", minutes: 25)
        mgr.interrupt()
        mgr.beginInterruption(intention: "Check Amazon", minutes: 5)
        mgr.completeInterruption()

        let events = tLog.loadAll()
        #expect(events.count == 3) // start + interruption + completion
        let ret = events[2]
        #expect(ret.type == .completion)
        #expect(ret.from?.todoText == "Check Amazon")
        #expect(ret.to.todoText == "Build feature")
        #expect(ret.interruptionDepth == 0) // back to main flow
    }

    @Test("nested interruption records correct depth")
    func nestedInterruptionDepth() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Build feature", minutes: 25)
        mgr.interrupt()
        mgr.beginInterruption(intention: "Check email", minutes: 5)
        mgr.interrupt()
        mgr.beginInterruption(intention: "Reply to thread", minutes: 3)

        let events = tLog.loadAll()
        #expect(events.count == 3) // start + interruption + nested interruption
        #expect(events[1].interruptionDepth == 1)
        #expect(events[2].interruptionDepth == 2)
    }

    @Test("completeExpired logs completion transition")
    func expiredCompletion() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "First task", minutes: 25)
        mgr.addTodoToActiveContext(text: "Second task", minutes: 15)
        mgr.completeExpired()

        let events = tLog.loadAll()
        #expect(events.count == 2) // start + completion
        #expect(events[1].type == .completion)
        #expect(events[1].from?.todoText == "First task")
        #expect(events[1].to.todoText == "Second task")
    }

    @Test("cycleNext logs contextSwitch")
    func cycleNextTransition() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Task A", minutes: 25)
        mgr.addContext(label: "Study", intention: "Task B", minutes: 30)
        mgr.cycleNext()

        let events = tLog.loadAll()
        #expect(events.count == 2) // start + contextSwitch
        #expect(events[1].type == .contextSwitch)
        #expect(events[1].from?.contextLabel == "Work")
        #expect(events[1].to.contextLabel == "Study")
    }

    // MARK: - Distraction Logging

    @Test("logDistraction records distraction event with text")
    func logDistractionRecordsEvent() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Build feature", minutes: 25)
        mgr.logDistraction("Facebook notification")

        let events = tLog.loadAll()
        #expect(events.count == 2) // start + distraction
        #expect(events[1].type == .distraction)
        #expect(events[1].distractionText == "Facebook notification")
        #expect(events[1].to.contextLabel == "Work")
        #expect(events[1].to.todoText == "Build feature")
        #expect(events[1].from == nil)
    }

    @Test("logDistraction with no active context is no-op")
    func logDistractionNoContext() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.logDistraction("Random thought")

        let events = tLog.loadAll()
        #expect(events.isEmpty)
    }

    @Test("multiple distractions attach to current intention")
    func multipleDistractions() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Build feature", minutes: 25)
        mgr.logDistraction("Twitter")
        mgr.logDistraction("Email ping")
        mgr.logDistraction("Snack craving")

        let events = tLog.loadAll()
        let distractions = events.filter { $0.type == .distraction }
        #expect(distractions.count == 3)
        #expect(distractions[0].distractionText == "Twitter")
        #expect(distractions[1].distractionText == "Email ping")
        #expect(distractions[2].distractionText == "Snack craving")
        // All attach to same intention
        #expect(distractions.allSatisfy { $0.to.todoText == "Build feature" })
    }

    @Test("distractions after completion attach to new intention")
    func distractionsAfterCompletion() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (mgr, tLog) = makeManager(dir: dir)

        mgr.addContext(label: "Work", intention: "Task A", minutes: 10)
        mgr.addTodoToActiveContext(text: "Task B", minutes: 15)
        mgr.logDistraction("Before completion")
        mgr.complete()
        mgr.logDistraction("After completion")

        let distractions = tLog.loadAll().filter { $0.type == .distraction }
        #expect(distractions.count == 2)
        #expect(distractions[0].to.todoText == "Task A")
        #expect(distractions[1].to.todoText == "Task B")
    }
}
