import SwiftUI
import AppKit

struct KeyRecorderView: View {
    let action: HotkeyAction
    @ObservedObject var hotkeyManager: HotkeyManager
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(action.displayName)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                if isRecording {
                    isRecording = false
                } else {
                    isRecording = true
                }
            }) {
                if isRecording {
                    Text("Press keys…")
                        .foregroundColor(.accentColor)
                        .frame(width: 120)
                } else if let binding = hotkeyManager.bindings[action] {
                    Text(binding.displayString)
                        .frame(width: 120)
                } else {
                    Text("Not Set")
                        .foregroundColor(.secondary)
                        .frame(width: 120)
                }
            }
            .buttonStyle(.bordered)
            .background(
                KeyRecorderHelper(
                    isRecording: $isRecording,
                    onKeyCombo: { keyCode, modifiers in
                        let binding = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
                        hotkeyManager.setBinding(binding, for: action)
                        isRecording = false
                    }
                )
            )

            Button(action: {
                hotkeyManager.clearBinding(for: action)
                isRecording = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear shortcut")
        }
    }
}

/// Invisible NSViewRepresentable that captures key events when recording
struct KeyRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onKeyCombo: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyCombo = onKeyCombo
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKeyCombo = onKeyCombo
        if isRecording {
            nsView.startRecording()
        } else {
            nsView.stopRecording()
        }
    }
}

class KeyCaptureView: NSView {
    var onKeyCombo: ((UInt32, UInt32) -> Void)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    func startRecording() {
        stopRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier key
            if !modifiers.isEmpty && event.keyCode != 0xFF {
                self?.onKeyCombo?(UInt32(event.keyCode), UInt32(modifiers.rawValue))
            }
            return nil // swallow the event
        }
    }

    func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
