import Foundation
import Testing
@testable import Effortless

@Suite("AllowlistStore")
struct AllowlistStoreTests {

    private func makeStore() -> AllowlistStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return AllowlistStore(directory: dir)
    }

    @Test func emptyByDefault() {
        let store = makeStore()
        let entries = store.entries(forContextId: UUID(), intention: "some task")
        #expect(entries.isEmpty)
    }

    @Test func addAndRetrieve() {
        let store = makeStore()
        let id = UUID()
        store.add("Safari - GitHub", forContextId: id, intention: "code review")
        let entries = store.entries(forContextId: id, intention: "code review")
        #expect(entries == ["Safari - GitHub"])
    }

    @Test func noDuplicates() {
        let store = makeStore()
        let id = UUID()
        store.add("Terminal - zsh", forContextId: id, intention: "deploy")
        store.add("Terminal - zsh", forContextId: id, intention: "deploy")
        let entries = store.entries(forContextId: id, intention: "deploy")
        #expect(entries.count == 1)
    }

    @Test func separateIntentions() {
        let store = makeStore()
        let id = UUID()
        store.add("Safari - GitHub", forContextId: id, intention: "code review")
        store.add("Slack - #general", forContextId: id, intention: "standup")

        #expect(store.entries(forContextId: id, intention: "code review") == ["Safari - GitHub"])
        #expect(store.entries(forContextId: id, intention: "standup") == ["Slack - #general"])
    }

    @Test func separateContexts() {
        let store = makeStore()
        let id1 = UUID()
        let id2 = UUID()
        store.add("Safari - GitHub", forContextId: id1, intention: "task A")
        store.add("Slack - #general", forContextId: id2, intention: "task B")

        #expect(store.entries(forContextId: id1, intention: "task A") == ["Safari - GitHub"])
        #expect(store.entries(forContextId: id2, intention: "task B") == ["Slack - #general"])
    }

    @Test func removeEntry() {
        let store = makeStore()
        let id = UUID()
        store.add("Safari - GitHub", forContextId: id, intention: "task")
        store.add("Terminal - zsh", forContextId: id, intention: "task")
        store.remove("Safari - GitHub", forContextId: id, intention: "task")

        let entries = store.entries(forContextId: id, intention: "task")
        #expect(entries == ["Terminal - zsh"])
    }

    @Test func persistsAcrossInstances() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let id = UUID()

        let store1 = AllowlistStore(directory: dir)
        store1.add("Chrome - YouTube", forContextId: id, intention: "research")

        let store2 = AllowlistStore(directory: dir)
        #expect(store2.entries(forContextId: id, intention: "research") == ["Chrome - YouTube"])
    }
}
