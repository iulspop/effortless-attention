import Foundation
import Testing
@testable import Effortless

@Suite("NudgeManager")
@MainActor
struct NudgeManagerTests {

    private func makeManager() -> NudgeManager {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = AllowlistStore(directory: dir)
        let mgr = NudgeManager(appearanceManager: .shared, allowlistStore: store)
        mgr.intentionProvider = {
            (intention: "Write PR review", contextLabel: "Work", contextId: UUID())
        }
        return mgr
    }

    @Test func startsIdle() {
        let mgr = makeManager()
        #expect(mgr.state == .idle)
    }

    @Test func stopResetsToIdle() {
        let mgr = makeManager()
        mgr.stop()
        #expect(mgr.state == .idle)
    }

    @Test func userMarkedNotDistractedFromIdle() {
        // Should be no-op when idle
        let mgr = makeManager()
        mgr.userMarkedNotDistracted()
        #expect(mgr.state == .idle)
    }

    @Test func userPickedStopTransitionsToGrace() {
        let mgr = makeManager()
        mgr.userPickedStop()
        #expect(mgr.state == .grace)
    }

    @Test func userPickedInterruptResetsToIdle() {
        let mgr = makeManager()
        mgr.userPickedInterrupt()
        #expect(mgr.state == .idle)
    }
}
