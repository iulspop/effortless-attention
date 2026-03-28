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
        loadDay(for: Date())
    }

    func loadDay(for date: Date) -> [TransitionEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return loadAll().filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
    }

    /// Returns all unique days that have transition events, sorted newest first.
    func availableDays() -> [Date] {
        let calendar = Calendar.current
        let all = loadAll()
        var seen = Set<DateComponents>()
        var days: [Date] = []
        for event in all {
            let comps = calendar.dateComponents([.year, .month, .day], from: event.timestamp)
            if seen.insert(comps).inserted {
                days.append(calendar.startOfDay(for: event.timestamp))
            }
        }
        return days.sorted(by: >)
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
