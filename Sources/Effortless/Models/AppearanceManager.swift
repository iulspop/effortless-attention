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

enum ChaliceDisplayMode: String, CaseIterable {
    case menuBarOnly = "menuBarOnly"
    case menuBarAndFloat = "menuBarAndFloat"

    var displayName: String {
        switch self {
        case .menuBarOnly: "Menu Bar Only"
        case .menuBarAndFloat: "Menu Bar + Float"
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

    @Published var chaliceDisplay: ChaliceDisplayMode {
        didSet {
            UserDefaults.standard.set(chaliceDisplay.rawValue, forKey: "chaliceDisplay")
            NotificationCenter.default.post(name: .chaliceDisplayChanged, object: nil)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        self.mode = AppearanceMode(rawValue: saved) ?? .system
        let savedDisplay = UserDefaults.standard.string(forKey: "chaliceDisplay") ?? "menuBarAndFloat"
        self.chaliceDisplay = ChaliceDisplayMode(rawValue: savedDisplay) ?? .menuBarAndFloat
    }

    func apply() {
        NSApp.appearance = mode.nsAppearance
    }
}

extension Notification.Name {
    static let chaliceDisplayChanged = Notification.Name("chaliceDisplayChanged")
}
