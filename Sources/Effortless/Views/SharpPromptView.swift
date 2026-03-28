import SwiftUI

/// Fullscreen overlay forcing the user to either stop (return to intention) or log an interruption.
struct SharpPromptView: View {
    let intention: String
    let onStop: () -> Void
    let onInterrupt: () -> Void

    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Text("Your attention has drifted.")
                    .font(.system(size: 28, weight: .light, design: .serif))
                    .foregroundColor(.white.opacity(0.9))

                Text("You set out to:")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundColor(.white.opacity(0.5))

                Text(intention)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                VStack(spacing: 16) {
                    Button(action: onStop) {
                        Text("Return to intention")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .foregroundColor(.black)
                            .frame(width: 240, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button(action: onInterrupt) {
                        Text("Log interruption")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 240, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 36 { // Enter → return to intention
                onStop()
                return nil
            }
            if event.keyCode == 53 { // Escape → log interruption
                onInterrupt()
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
}
