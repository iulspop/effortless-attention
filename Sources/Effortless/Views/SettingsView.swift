import SwiftUI

struct SettingsView: View {
    @ObservedObject var appearance: AppearanceManager
    @ObservedObject var hotkeyManager: HotkeyManager
    @State private var showNudgeInfo = false

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

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Toggle("Distraction Nudge", isOn: $appearance.nudgeEnabled)
                        .font(.system(size: 13, weight: .regular))

                    Button(action: { showNudgeInfo.toggle() }) {
                        Text("ⓘ")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showNudgeInfo, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Requires Ollama running locally.")
                                .font(.system(size: 12, weight: .medium))
                            Text("Install:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                            Text("brew install ollama")
                                .font(.system(size: 11, design: .monospaced))
                            Text("Start on login:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                            Text("brew services start ollama")
                                .font(.system(size: 11, design: .monospaced))
                            Text("Pull a model:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                            Text("ollama pull gemma2:2b")
                                .font(.system(size: 11, design: .monospaced))
                            Divider()
                            Text("Or install the desktop app from\nollama.com — it auto-starts on login.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                    }
                }

                if appearance.nudgeEnabled {
                    HStack(spacing: 8) {
                        Text("Ollama model")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        TextField("Model name", text: $appearance.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }

                    HStack(spacing: 8) {
                        Text("Escalation delay")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Picker("", selection: $appearance.gentleNudgeDelay) {
                            Text("1s").tag(1)
                            Text("5s").tag(5)
                            Text("15s").tag(15)
                            Text("30s").tag(30)
                            Text("60s").tag(60)
                            Text("120s").tag(120)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 80)
                    }

                    HStack(spacing: 8) {
                        Text("Grace after stop")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Picker("", selection: $appearance.gracePeriodAfterStop) {
                            Text("5s").tag(5)
                            Text("15s").tag(15)
                            Text("30s").tag(30)
                            Text("60s").tag(60)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 80)
                    }

                    Toggle("Flash screen on escalation", isOn: $appearance.nudgeFlashEnabled)
                        .font(.system(size: 12))
                    Toggle("Play sound on escalation", isOn: $appearance.nudgeSoundEnabled)
                        .font(.system(size: 12))
                }
            }

            Divider()

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
