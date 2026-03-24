import Foundation

struct SessionLogger {
    private var logDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Effortless", isDirectory: true)
    }

    private var logFile: URL {
        logDirectory.appendingPathComponent("sessions.json")
    }

    func log(_ session: Session) {
        var sessions = loadAll()
        sessions.append(session)
        save(sessions)
    }

    func loadAll() -> [Session] {
        guard FileManager.default.fileExists(atPath: logFile.path) else { return [] }
        guard let data = try? Data(contentsOf: logFile) else { return [] }
        return (try? JSONDecoder().decode([Session].self, from: data)) ?? []
    }

    private func save(_ sessions: [Session]) {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: logFile)
    }
}
