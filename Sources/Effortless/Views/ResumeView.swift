import SwiftUI

struct ResumeView: View {
    @ObservedObject var sessionManager: SessionManager
    let onResume: () -> Void
    let onSwitchToAltar: () -> Void

    @State private var selectedIndex: Int = 0
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

                VStack(spacing: 12) {
                    Text("Welcome back")
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundColor(.primary)

                    Text("Pick up where you left off")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundColor(.secondary)
                }

                Spacer().frame(height: 48)

                // Context list
                VStack(spacing: 4) {
                    ForEach(Array(sessionManager.contexts.enumerated()), id: \.element.id) { index, ctx in
                        let isSelected = index == selectedIndex
                        let hasWork = ctx.hasActiveIntention

                        HStack(spacing: 16) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ctx.label)
                                    .font(.system(size: 13, weight: .semibold, design: .serif))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)

                                if let todo = ctx.currentTodo {
                                    Text(todo.text)
                                        .font(.system(size: 16, weight: .regular, design: .serif))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                } else {
                                    Text("No active intention")
                                        .font(.system(size: 16, weight: .light, design: .serif))
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                            }

                            Spacer()



                            if !hasWork {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(.green.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                            resumeSelected()
                        }
                    }
                }
                .frame(maxWidth: 500)

                Spacer().frame(height: 32)

                Text("↑↓ select  ·  Enter resume  ·  ⌃⌥⌘A edit")
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(timer) { currentTime = $0 }
        .onAppear {
            selectedIndex = sessionManager.activeIndex
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func resumeSelected() {
        sessionManager.resume(index: selectedIndex)
        onResume()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: // ↑
                selectedIndex = max(0, selectedIndex - 1)
                return nil
            case 125: // ↓
                selectedIndex = min(sessionManager.contexts.count - 1, selectedIndex + 1)
                return nil
            case 36: // Enter
                resumeSelected()
                return nil
            default:
                // 1-9 jump to context
                let numKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
                if let num = numKeyCodes[event.keyCode],
                   num >= 1, num <= sessionManager.contexts.count {
                    selectedIndex = num - 1
                    resumeSelected()
                    return nil
                }
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
