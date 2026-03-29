import SwiftUI

struct SettingsView: View {
    @ObservedObject var appearance: AppearanceManager
    @ObservedObject var hotkeyManager: HotkeyManager
    @State private var showNudgeInfo = false
    @State private var showModelInfo = false
    @State private var updateStatus: UpdateStatus = .idle

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case available(String)
        case upToDate
        case updating
        case failed(String)
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings")
                    .font(.system(size: 18, weight: .medium, design: .serif))
                Spacer()
                Text("v\(currentVersion)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }

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
                        TextField("auto", text: $appearance.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Text("ⓘ")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .onTapGesture { showModelInfo.toggle() }
                            .popover(isPresented: $showModelInfo, arrowEdge: .trailing) {
                                Text("\"auto\" picks the smallest\navailable model from Ollama.\n\nOr type a specific model name\ne.g. gemma2:2b, llama3.2")
                                    .font(.system(size: 11))
                                    .padding(10)
                            }
                    }

                    HStack(spacing: 8) {
                        Text("Nudge → flash")
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
                        Text("Flash → sharp")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Picker("", selection: $appearance.flashToSharpDelay) {
                            Text("1s").tag(1)
                            Text("3s").tag(3)
                            Text("5s").tag(5)
                            Text("10s").tag(10)
                            Text("15s").tag(15)
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
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    switch updateStatus {
                    case .idle:
                        Button("Check for updates") { checkForUpdates() }
                            .font(.system(size: 12))
                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    case .available(let latest):
                        Text("v\(latest) available")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                        Button("Install & restart") { installUpdate() }
                            .font(.system(size: 12))
                    case .upToDate:
                        Text("Up to date")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    case .updating:
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    case .failed(let msg):
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                        Button("Retry") { checkForUpdates() }
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func checkForUpdates() {
        updateStatus = .checking
        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/iulspop/effortless-attention/releases/latest")!
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    updateStatus = .failed("Could not parse release info")
                    return
                }
                let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                if latest != currentVersion && currentVersion != "dev" {
                    updateStatus = .available(latest)
                } else {
                    updateStatus = .upToDate
                }
            } catch {
                updateStatus = .failed("Could not reach GitHub")
            }
        }
    }

    private func installUpdate() {
        updateStatus = .updating
        Task.detached {
            let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
                ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"
            let env = ProcessInfo.processInfo.environment

            // Sync tap first
            let update = Process()
            update.executableURL = URL(fileURLWithPath: brewPath)
            update.arguments = ["update"]
            update.environment = env
            update.standardOutput = FileHandle.nullDevice
            update.standardError = FileHandle.nullDevice
            try? update.run()
            update.waitUntilExit()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["upgrade", "effortless"]
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    // Relaunch the app
                    let appPath = Bundle.main.bundlePath
                    let relaunch = Process()
                    relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    relaunch.arguments = ["-n", appPath]
                    try relaunch.run()
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                } else {
                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    await MainActor.run {
                        updateStatus = .failed(output.contains("already installed") ? "Already up to date" : "brew upgrade failed")
                    }
                }
            } catch {
                await MainActor.run {
                    updateStatus = .failed("brew not found at /opt/homebrew/bin/brew")
                }
            }
        }
    }
}
