import SwiftUI

struct SettingsView: View {
    @ObservedObject var appearance: AppearanceManager
    @ObservedObject var hotkeyManager: HotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 18, weight: .medium, design: .serif))

            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)

                Picker("", selection: $appearance.mode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Active Session Display")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)

                Picker("", selection: $appearance.chaliceDisplay) {
                    ForEach(ChaliceDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch at login", isOn: $appearance.launchAtLogin)
                    .font(.system(size: 13, weight: .regular))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Idle Auto-Pause")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Picker("", selection: $appearance.idleTimeoutMinutes) {
                        Text("Disabled").tag(0)
                        Text("2 min").tag(2)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 120)

                    Text("of inactivity")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)

                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    KeyRecorderView(action: action, hotkeyManager: hotkeyManager)
                }
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
