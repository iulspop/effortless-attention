import AppKit
import Carbon
import HotKey

struct HotkeyBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    var hotKeyKeyCombo: KeyCombo {
        KeyCombo(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    private var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

private func keyName(for keyCode: UInt32) -> String {
    let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
        50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 109: "F10", 111: "F12", 103: "F11",
        105: "F13", 107: "F14", 113: "F15",
        118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    return names[keyCode] ?? "Key\(keyCode)"
}

enum HotkeyAction: String, CaseIterable {
    case complete
    case interrupt
    case openAltar
    case togglePause
    case cycleNext
    case cyclePrev

    var displayName: String {
        switch self {
        case .complete: "Complete Session"
        case .interrupt: "Interrupt Session"
        case .openAltar: "Open Altar"
        case .togglePause: "Pause / Resume"
        case .cycleNext: "Next Context"
        case .cyclePrev: "Previous Context"
        }
    }

    var defaultsKey: String { "hotkey_\(rawValue)" }
}

@MainActor
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var bindings: [HotkeyAction: HotkeyBinding] = [:]

    private var hotKeys: [HotkeyAction: HotKey] = [:]
    private var handlers: [HotkeyAction: () -> Void] = [:]
    private var contextJumpHotKeys: [HotKey] = []
    var onContextJump: ((Int) -> Void)?

    private init() {
        loadBindings()
        setupContextJumpHotKeys()
    }

    func setHandler(for action: HotkeyAction, handler: @escaping () -> Void) {
        handlers[action] = handler
        registerHotKey(for: action)
    }

    func setBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
        bindings[action] = binding
        saveBinding(binding, for: action)
        registerHotKey(for: action)
    }

    func clearBinding(for action: HotkeyAction) {
        bindings[action] = nil
        hotKeys[action] = nil
        UserDefaults.standard.removeObject(forKey: action.defaultsKey)
    }

    private func registerHotKey(for action: HotkeyAction) {
        hotKeys[action] = nil

        guard let binding = bindings[action] else { return }

        let hotKey = HotKey(keyCombo: binding.hotKeyKeyCombo)
        hotKey.keyDownHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?.handlers[action]?()
            }
        }
        hotKeys[action] = hotKey
    }

    private func setupContextJumpHotKeys() {
        let mods = UInt32(NSEvent.ModifierFlags([.control, .option, .command]).rawValue)
        // Key codes for 1, 2, 3
        let numberKeyCodes: [UInt32] = [18, 19, 20]

        for (index, keyCode) in numberKeyCodes.enumerated() {
            let binding = HotkeyBinding(keyCode: keyCode, modifiers: mods)
            let hotKey = HotKey(keyCombo: binding.hotKeyKeyCombo)
            let contextIndex = index
            hotKey.keyDownHandler = { [weak self] in
                MainActor.assumeIsolated {
                    self?.onContextJump?(contextIndex)
                }
            }
            contextJumpHotKeys.append(hotKey)
        }
    }

    private func loadBindings() {
        for action in HotkeyAction.allCases {
            if let data = UserDefaults.standard.data(forKey: action.defaultsKey),
               let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
                bindings[action] = binding
            } else {
                // Set defaults
                bindings[action] = defaultBinding(for: action)
            }
        }
    }

    private func saveBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: action.defaultsKey)
        }
    }

    private func defaultBinding(for action: HotkeyAction) -> HotkeyBinding {
        let mods = UInt32(NSEvent.ModifierFlags([.control, .option, .command]).rawValue)
        switch action {
        case .complete:
            return HotkeyBinding(keyCode: 2, modifiers: mods)  // ⌃⌥⌘D
        case .interrupt:
            return HotkeyBinding(keyCode: 34, modifiers: mods) // ⌃⌥⌘I
        case .openAltar:
            return HotkeyBinding(keyCode: 0, modifiers: mods)  // ⌃⌥⌘A
        case .togglePause:
            return HotkeyBinding(keyCode: 35, modifiers: mods) // ⌃⌥⌘P
        case .cycleNext:
            return HotkeyBinding(keyCode: 124, modifiers: mods) // ⌃⌥⌘→
        case .cyclePrev:
            return HotkeyBinding(keyCode: 123, modifiers: mods) // ⌃⌥⌘←
        }
    }
}
