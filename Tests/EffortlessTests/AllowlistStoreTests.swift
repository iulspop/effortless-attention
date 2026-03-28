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
        let entries = store.entries(forContextId: UUID())
        #expect(entries.isEmpty)
    }

    @Test func addAndRetrieve() {
        let store = makeStore()
        let id = UUID()
        store.add("Safari - GitHub", forContextId: id)
        let entries = store.entries(forContextId: id)
        #expect(entries == ["Safari - GitHub"])
    }

    @Test func noDuplicates() {
        let store = makeStore()
        let id = UUID()
        store.add("Terminal - zsh", forContextId: id)
        store.add("Terminal - zsh", forContextId: id)
        let entries = store.entries(forContextId: id)
        #expect(entries.count == 1)
    }

    @Test func separateContexts() {
        let store = makeStore()
        let id1 = UUID()
        let id2 = UUID()
        store.add("Safari - GitHub", forContextId: id1)
        store.add("Slack - #general", forContextId: id2)

        #expect(store.entries(forContextId: id1) == ["Safari - GitHub"])
        #expect(store.entries(forContextId: id2) == ["Slack - #general"])
    }

    @Test func removeEntry() {
        let store = makeStore()
        let id = UUID()
        store.add("Safari - GitHub", forContextId: id)
        store.add("Terminal - zsh", forContextId: id)
        store.remove("Safari - GitHub", forContextId: id)

        let entries = store.entries(forContextId: id)
        #expect(entries == ["Terminal - zsh"])
    }

    @Test func persistsAcrossInstances() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let id = UUID()

        let store1 = AllowlistStore(directory: dir)
        store1.add("Chrome - YouTube", forContextId: id)

        let store2 = AllowlistStore(directory: dir)
        #expect(store2.entries(forContextId: id) == ["Chrome - YouTube"])
    }
}
