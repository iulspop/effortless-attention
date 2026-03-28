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
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
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

    // MARK: - Nudge System Settings

    @Published var nudgeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(nudgeEnabled, forKey: "nudgeEnabled")
            NotificationCenter.default.post(name: .nudgeSettingsChanged, object: nil)
        }
    }

    @Published var ollamaModel: String {
        didSet {
            UserDefaults.standard.set(ollamaModel, forKey: "ollamaModel")
        }
    }

    /// Seconds before gentle nudge escalates to flash warning.
    @Published var gentleNudgeDelay: Int {
        didSet {
            UserDefaults.standard.set(gentleNudgeDelay, forKey: "gentleNudgeDelay")
        }
    }

    /// Seconds of grace after user picks "Stop" before re-checking.
    @Published var gracePeriodAfterStop: Int {
        didSet {
            UserDefaults.standard.set(gracePeriodAfterStop, forKey: "gracePeriodAfterStop")
        }
    }

    @Published var nudgeFlashEnabled: Bool {
        didSet {
            UserDefaults.standard.set(nudgeFlashEnabled, forKey: "nudgeFlashEnabled")
        }
    }

    @Published var nudgeSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(nudgeSoundEnabled, forKey: "nudgeSoundEnabled")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        self.mode = AppearanceMode(rawValue: saved) ?? .system
        let savedDisplay = UserDefaults.standard.string(forKey: "chaliceDisplay") ?? "menuBarAndFloat"
        self.chaliceDisplay = ChaliceDisplayMode(rawValue: savedDisplay) ?? .menuBarAndFloat
        // UserDefaults tracks the user's *intent* — SMAppService status can reset
        // between debug builds, so we re-register on every launch if user wants it.
        let userWantsLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? false
        if userWantsLogin {
            try? SMAppService.mainApp.register()
        }
        self.launchAtLogin = userWantsLogin
        let savedIdle = UserDefaults.standard.integer(forKey: "idleTimeoutMinutes")
        self.idleTimeoutMinutes = savedIdle > 0 ? savedIdle : 5  // default 5 minutes

        // Nudge settings
        self.nudgeEnabled = UserDefaults.standard.bool(forKey: "nudgeEnabled") // default false
        self.ollamaModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? "gemma2:2b"
        let savedGentleDelay = UserDefaults.standard.integer(forKey: "gentleNudgeDelay")
        self.gentleNudgeDelay = savedGentleDelay > 0 ? savedGentleDelay : 5
        let savedGrace = UserDefaults.standard.integer(forKey: "gracePeriodAfterStop")
        self.gracePeriodAfterStop = savedGrace > 0 ? savedGrace : 5
        self.nudgeFlashEnabled = UserDefaults.standard.object(forKey: "nudgeFlashEnabled") as? Bool ?? true
        self.nudgeSoundEnabled = UserDefaults.standard.object(forKey: "nudgeSoundEnabled") as? Bool ?? true
    }

    func apply() {
        NSApp.appearance = mode.nsAppearance
    }
}

extension Notification.Name {
    static let chaliceDisplayChanged = Notification.Name("chaliceDisplayChanged")
    static let nudgeSettingsChanged = Notification.Name("nudgeSettingsChanged")
}
