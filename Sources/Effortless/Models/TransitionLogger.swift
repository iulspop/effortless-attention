import Foundation

struct TransitionLogger {
    private let directory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = appSupport.appendingPathComponent("Effortless", isDirectory: true)
    }

    init(directory: URL) {
        self.directory = directory
    }

    private var logFile: URL {
        directory.appendingPathComponent("transitions.json")
    }

    func log(_ event: TransitionEvent) {
        var events = loadAll()
        events.append(event)
        save(events)
    }

    func loadAll() -> [TransitionEvent] {
        guard FileManager.default.fileExists(atPath: logFile.path) else { return [] }
        guard let data = try? Data(contentsOf: logFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TransitionEvent].self, from: data)) ?? []
    }

    func loadToday() -> [TransitionEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return loadAll().filter { $0.timestamp >= startOfDay }
    }

    private func save(_ events: [TransitionEvent]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: logFile)
    }
}
