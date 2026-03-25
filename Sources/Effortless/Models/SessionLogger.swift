import Foundation

struct SessionLogger {
    private let directory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = appSupport.appendingPathComponent("Effortless", isDirectory: true)
    }

    init(directory: URL) {
        self.directory = directory
    }

    private var logFile: URL {
        directory.appendingPathComponent("sessions.json")
    }

    func log(_ session: Session) {
        var sessions = loadAll()
        sessions.append(session)
        save(sessions)
    }

    func loadAll() -> [Session] {
        guard FileManager.default.fileExists(atPath: logFile.path) else { return [] }
        guard let data = try? Data(contentsOf: logFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Session].self, from: data)) ?? []
    }

    private func save(_ sessions: [Session]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: logFile)
    }
}
