import SwiftUI

struct InterruptionPromptView: View {
    var interruptionDepth: Int
    var onConfirm: (String, Int) -> Void
    var onCancel: () -> Void

    enum Step { case intention, minutes }

    @State private var step: Step = .intention
    @State private var showNestingGuardrail = false
    @State private var intention: String = ""
    @State private var minutesText: String = ""
    @State private var keyMonitor: Any? = nil
    @FocusState private var isIntentionFocused: Bool
    @FocusState private var isMinutesFocused: Bool

    private let quickOptions: [(key: String, minutes: Int)] = [
        ("q", 5), ("w", 25), ("e", 90)
    ]

    var body: some View {
        ZStack {
            // Warm-tinted background — escape hatch visual
            Color(nsColor: NSColor.windowBackgroundColor)
                .ignoresSafeArea()
                .overlay(
                    Color.orange.opacity(0.06)
                        .ignoresSafeArea()
                )

            VStack(spacing: 0) {
                Spacer()

                if showNestingGuardrail {
                    nestingGuardrailView
                } else {
                    promptFlow
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            installKeyMonitor()
            if interruptionDepth > 0 {
                showNestingGuardrail = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isIntentionFocused = true
                }
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                onCancel()
                return nil
            }
            if showNestingGuardrail && event.keyCode == 36 { // Return
                showNestingGuardrail = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isIntentionFocused = true
                }
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func proceedPastGuardrail() {
        showNestingGuardrail = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isIntentionFocused = true
        }
    }

    private var nestingGuardrailView: some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.orange)

            Text("You're already in an interruption.")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundColor(.primary)

            Text("Nesting depth: \(interruptionDepth)")
                .font(.system(size: 16, weight: .light, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 24) {
                Button(action: onCancel) {
                    Text("Go back (Esc)")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: proceedPastGuardrail) {
                    Text("Interrupt anyway (Enter)")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var promptFlow: some View {
        VStack(spacing: 0) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.orange)
                .padding(.bottom, 48)

            switch step {
            case .intention:
                intentionStep
            case .minutes:
                minutesStep
            }
        }
    }

    private var intentionStep: some View {
        VStack(spacing: 0) {
            Text("What outcome do you seek?")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundColor(.primary)
                .padding(.bottom, 32)

            TextField("", text: $intention)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(maxWidth: 500)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: Color.orange.opacity(0.06), radius: 8, y: 2)
                )
                .focused($isIntentionFocused)
                .onSubmit {
                    let trimmed = intention.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    step = .minutes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isMinutesFocused = true
                    }
                }
        }
    }

    private var minutesStep: some View {
        VStack(spacing: 0) {
            Text("How many minutes to hit that target?")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundColor(.primary)
                .padding(.bottom, 32)

            TextField("", text: $minutesText)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(maxWidth: 200)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: Color.orange.opacity(0.06), radius: 8, y: 2)
                )
                .focused($isMinutesFocused)
                .onSubmit { submitMinutes() }
                .padding(.bottom, 32)

            HStack(spacing: 16) {
                ForEach(Array(quickOptions.enumerated()), id: \.offset) { _, option in
                    Button(action: { selectQuickOption(option.minutes) }) {
                        HStack(spacing: 6) {
                            Text(option.key)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 18, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                                )
                            Text("\(option.minutes) min")
                                .font(.system(size: 14, weight: .light, design: .serif))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onKeyPress(characters: .init(charactersIn: "qwe")) { press in
            let key = String(press.characters)
            if let option = quickOptions.first(where: { $0.key == key }) {
                selectQuickOption(option.minutes)
                return .handled
            }
            return .ignored
        }
    }

    private func submitMinutes() {
        let trimmed = minutesText.trimmingCharacters(in: .whitespaces)
        guard let mins = Int(trimmed), mins > 0 else { return }
        onConfirm(intention.trimmingCharacters(in: .whitespaces), mins)
    }

    private func selectQuickOption(_ minutes: Int) {
        onConfirm(intention.trimmingCharacters(in: .whitespaces), minutes)
    }
}
