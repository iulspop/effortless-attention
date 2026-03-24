import AppKit

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    @Published var mode: AppearanceMode {
        didSet {
            apply()
            UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        self.mode = AppearanceMode(rawValue: saved) ?? .system
    }

    func apply() {
        NSApp.appearance = mode.nsAppearance
    }
}
