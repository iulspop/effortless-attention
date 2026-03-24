import SwiftUI

struct AltarView: View {
    var onBegin: (String, Int) -> Void

    enum Step { case outcome, minutes }

    @State private var step: Step = .outcome
    @State private var intention: String = ""
    @State private var minutesText: String = ""
    @FocusState private var isOutcomeFocused: Bool
    @FocusState private var isMinutesFocused: Bool

    private let quickOptions: [(key: String, minutes: Int)] = [
        ("1", 5), ("2", 25), ("3", 90)
    ]

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(white: 0.97, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(Color(nsColor: NSColor(white: 0.55, alpha: 1.0)))
                    .padding(.bottom, 48)

                switch step {
                case .outcome:
                    outcomeStep
                case .minutes:
                    minutesStep
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isOutcomeFocused = true
            }
        }
    }

    // MARK: - Step 1: Outcome

    private var outcomeStep: some View {
        VStack(spacing: 0) {
            Text("What outcome do you seek?")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundColor(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))
                .padding(.bottom, 32)

            TextField("", text: $intention)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundColor(Color(nsColor: NSColor(white: 0.15, alpha: 1.0)))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(maxWidth: 500)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                )
                .focused($isOutcomeFocused)
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

    // MARK: - Step 2: Minutes

    private var minutesStep: some View {
        VStack(spacing: 0) {
            Text("How many minutes to hit that target?")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundColor(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))
                .padding(.bottom, 32)

            TextField("", text: $minutesText)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundColor(Color(nsColor: NSColor(white: 0.15, alpha: 1.0)))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(maxWidth: 200)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                )
                .focused($isMinutesFocused)
                .onSubmit {
                    submitMinutes()
                }
                .padding(.bottom, 32)

            HStack(spacing: 16) {
                ForEach(Array(quickOptions.enumerated()), id: \.offset) { _, option in
                    Button(action: { selectQuickOption(option.minutes) }) {
                        HStack(spacing: 6) {
                            Text(option.key)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(nsColor: NSColor(white: 0.55, alpha: 1.0)))
                                .frame(width: 18, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(nsColor: NSColor(white: 0.75, alpha: 1.0)), lineWidth: 1)
                                )
                            Text("\(option.minutes) min")
                                .font(.system(size: 14, weight: .light, design: .serif))
                                .foregroundColor(Color(nsColor: NSColor(white: 0.4, alpha: 1.0)))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onKeyPress(characters: .init(charactersIn: "123")) { press in
            let key = String(press.characters)
            if let option = quickOptions.first(where: { $0.key == key }) {
                selectQuickOption(option.minutes)
                return .handled
            }
            return .ignored
        }
    }

    private func selectQuickOption(_ minutes: Int) {
        let trimmed = intention.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onBegin(trimmed, minutes)
    }

    private func submitMinutes() {
        let trimmed = intention.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces)), minutes > 0 else { return }
        onBegin(trimmed, minutes)
    }
}
