import Foundation

/// Persists per-intention "not distracted" allowlists to disk.
/// When the user dismisses a nudge with "not distracted", the app/window entry
/// is saved here so the LLM prompt includes it in future assessments.
/// Keyed by contextId + intention so feedback only applies to that specific intention.
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

    private func key(contextId: UUID, intention: String) -> String {
        "\(contextId.uuidString):\(intention)"
    }

    /// Get all allowed entries for a specific intention in a context.
    func entries(forContextId contextId: UUID, intention: String) -> [String] {
        let all = loadAll()
        return all[key(contextId: contextId, intention: intention)] ?? []
    }

    /// Add an entry to an intention's allowlist.
    func add(_ entry: String, forContextId contextId: UUID, intention: String) {
        var all = loadAll()
        let k = key(contextId: contextId, intention: intention)
        var list = all[k] ?? []
        if !list.contains(entry) {
            list.append(entry)
        }
        all[k] = list
        save(all)
    }

    /// Remove an entry from an intention's allowlist.
    func remove(_ entry: String, forContextId contextId: UUID, intention: String) {
        var all = loadAll()
        let k = key(contextId: contextId, intention: intention)
        var list = all[k] ?? []
        list.removeAll { $0 == entry }
        all[k] = list
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
