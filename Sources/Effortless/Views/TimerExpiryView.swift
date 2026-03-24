import SwiftUI

struct TimerExpiryView: View {
    let intentionText: String
    let onExtend: (Int) -> Void
    let onComplete: () -> Void

    @State private var keyMonitor: Any? = nil
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(nsColor: NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text(currentTime, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .light, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 80)

                Spacer()

                VStack(spacing: 16) {
                    Text("🏆")
                        .font(.system(size: 48))

                    Text("Time's up")
                        .font(.system(size: 32, weight: .light, design: .serif))
                        .foregroundColor(.primary)

                    Text(intentionText)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .frame(maxWidth: 500)
                }

                Spacer().frame(height: 60)

                VStack(spacing: 20) {
                    Text("Need more time?")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        extendButton(minutes: 5, key: "Q")
                        extendButton(minutes: 15, key: "W")
                        extendButton(minutes: 25, key: "E")
                    }

                    Spacer().frame(height: 12)

                    Button(action: onComplete) {
                        Text("Mark Complete")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .frame(width: 200, height: 40)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Text("Enter to complete")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(timer) { currentTime = $0 }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func extendButton(minutes: Int, key: String) -> some View {
        Button(action: { onExtend(minutes) }) {
            VStack(spacing: 4) {
                Text("+\(minutes) min")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                Text(key)
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 100, height: 50)
        }
        .buttonStyle(.bordered)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 12: // Q
                onExtend(5)
                return nil
            case 13: // W
                onExtend(15)
                return nil
            case 14: // E
                onExtend(25)
                return nil
            case 36: // Enter
                onComplete()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
