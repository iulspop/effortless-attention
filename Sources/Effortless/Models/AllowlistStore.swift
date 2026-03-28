import Foundation

/// Persists per-context "not distracted" allowlists to disk.
/// When the user dismisses a nudge with "not distracted", the app/window entry
/// is saved here so the LLM prompt includes it in future assessments.
struct AllowlistStore {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("Effortless", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("context-allowlists.json")
    }

    /// Get all allowed entries for a context.
    func entries(forContextId contextId: UUID) -> [String] {
        let all = loadAll()
        return all[contextId.uuidString] ?? []
    }

    /// Add an entry to a context's allowlist.
    func add(_ entry: String, forContextId contextId: UUID) {
        var all = loadAll()
        var list = all[contextId.uuidString] ?? []
        if !list.contains(entry) {
            list.append(entry)
        }
        all[contextId.uuidString] = list
        save(all)
    }

    /// Remove an entry from a context's allowlist.
    func remove(_ entry: String, forContextId contextId: UUID) {
        var all = loadAll()
        var list = all[contextId.uuidString] ?? []
        list.removeAll { $0 == entry }
        all[contextId.uuidString] = list
        save(all)
    }

    private func loadAll() -> [String: [String]] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save(_ dict: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
