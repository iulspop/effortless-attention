import AppKit
import ServiceManagement

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

    @Published var launchAtLogin: Bool {
        didSet {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    /// Idle timeout in minutes before auto-pause. 0 = disabled.
    @Published var idleTimeoutMinutes: Int {
        didSet {
            UserDefaults.standard.set(idleTimeoutMinutes, forKey: "idleTimeoutMinutes")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        self.mode = AppearanceMode(rawValue: saved) ?? .system
        let savedDisplay = UserDefaults.standard.string(forKey: "chaliceDisplay") ?? "menuBarAndFloat"
        self.chaliceDisplay = ChaliceDisplayMode(rawValue: savedDisplay) ?? .menuBarAndFloat
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        let savedIdle = UserDefaults.standard.integer(forKey: "idleTimeoutMinutes")
        self.idleTimeoutMinutes = savedIdle > 0 ? savedIdle : 5  // default 5 minutes
    }

    func apply() {
        NSApp.appearance = mode.nsAppearance
    }
}

extension Notification.Name {
    static let chaliceDisplayChanged = Notification.Name("chaliceDisplayChanged")
}
