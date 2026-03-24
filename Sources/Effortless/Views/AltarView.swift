import SwiftUI

struct AltarView: View {
    var onBegin: (String, Int) -> Void

    @State private var intention: String = ""
    @State private var selectedMinutes: Int = 30
    @FocusState private var isTextFieldFocused: Bool

    private let timeboxOptions = [15, 30, 45, 60, 90]

    var body: some View {
        ZStack {
            // Background — warm white, full screen
            Color(nsColor: NSColor(white: 0.97, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Chalice icon
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(Color(nsColor: NSColor(white: 0.55, alpha: 1.0)))
                    .padding(.bottom, 48)

                // The question
                Text("What will you give your attention to?")
                    .font(.system(size: 24, weight: .light, design: .serif))
                    .foregroundColor(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))
                    .padding(.bottom, 32)

                // Intention input
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
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        beginIfValid()
                    }
                    .padding(.bottom, 40)

                // Timebox selector
                Text("For how long?")
                    .font(.system(size: 15, weight: .light, design: .serif))
                    .foregroundColor(Color(nsColor: NSColor(white: 0.45, alpha: 1.0)))
                    .padding(.bottom, 16)

                HStack(spacing: 12) {
                    ForEach(timeboxOptions, id: \.self) { minutes in
                        TimeboxButton(
                            minutes: minutes,
                            isSelected: selectedMinutes == minutes,
                            action: { selectedMinutes = minutes }
                        )
                    }
                }
                .padding(.bottom, 48)

                // Begin button
                Button(action: beginIfValid) {
                    Text("Begin")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundColor(intention.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color(nsColor: NSColor(white: 0.7, alpha: 1.0))
                            : Color(nsColor: NSColor(white: 0.2, alpha: 1.0))
                        )
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    intention.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? Color(nsColor: NSColor(white: 0.85, alpha: 1.0))
                                        : Color(nsColor: NSColor(white: 0.4, alpha: 1.0)),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(intention.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }

    private func beginIfValid() {
        let trimmed = intention.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onBegin(trimmed, selectedMinutes)
    }
}

struct TimeboxButton: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(formatMinutes(minutes))
                .font(.system(size: 14, weight: isSelected ? .medium : .light, design: .serif))
                .foregroundColor(
                    isSelected
                        ? Color(nsColor: NSColor(white: 0.15, alpha: 1.0))
                        : Color(nsColor: NSColor(white: 0.5, alpha: 1.0))
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.white : Color.clear)
                        .shadow(color: isSelected ? Color.black.opacity(0.06) : .clear, radius: 4, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func formatMinutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let remainder = m % 60
        if remainder == 0 { return "\(h)h" }
        return "\(h)h \(remainder)m"
    }
}
