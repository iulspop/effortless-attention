import SwiftUI

struct ChaliceView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var isHovering = false

    private var isEscapeHatch: Bool {
        sessionManager.isInInterruption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always-visible compact view
            HStack(spacing: 14) {
                Image(systemName: isEscapeHatch ? "bolt.circle" : "cup.and.saucer")
                    .font(.system(size: 16, weight: .ultraLight))
                    .foregroundColor(isEscapeHatch ? .orange : .secondary)

                if let ctx = sessionManager.activeContext {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(ctx.label)
                                .font(.system(size: 11, weight: .semibold, design: .serif))
                                .foregroundColor(isEscapeHatch ? .orange : .secondary)
                                .textCase(.uppercase)

                            if sessionManager.interruptionDepth > 1 {
                                Text("×\(sessionManager.interruptionDepth)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.orange.opacity(0.8))
                            }
                        }

                        if let current = ctx.currentTodo {
                            Text(current.text)
                                .font(.system(size: 13, weight: .regular, design: .serif))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(sessionManager.remainingTimeFormatted)
                                .font(.system(size: 12, weight: .light, design: .monospaced))
                                .foregroundColor(isEscapeHatch ? .orange : .secondary)
                        } else {
                            Text("No active intention")
                                .font(.system(size: 13, weight: .light, design: .serif))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            // Expanded todo list on hover
            if isHovering, let ctx = sessionManager.activeContext, ctx.todos.count > 1 {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ctx.todos) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: todo.completed ? "checkmark.circle.fill" : (todo.id == ctx.currentTodo?.id ? "arrow.right.circle.fill" : "circle"))
                                .foregroundColor(todo.completed ? .green : (todo.id == ctx.currentTodo?.id ? .accentColor : .secondary))
                                .font(.system(size: 12))

                            Text(todo.text)
                                .font(.system(size: 12, weight: .regular, design: .serif))
                                .foregroundColor(todo.completed ? .secondary : .primary)
                                .strikethrough(todo.completed)
                                .lineLimit(1)

                            Spacer()

                            Text("\(todo.timeboxMinutes)m")
                                .font(.system(size: 10, weight: .light, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                if isEscapeHatch {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.08))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                }
            }
            .shadow(color: isEscapeHatch ? Color.orange.opacity(0.12) : Color.black.opacity(0.08), radius: 12, y: 4)
        )
        .onHover { hovering in
            isHovering = hovering
            // Notify window to resize after SwiftUI layout settles
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .chaliceHoverChanged, object: NSNumber(value: hovering))
            }
        }
    }
}

extension Notification.Name {
    static let chaliceHoverChanged = Notification.Name("chaliceHoverChanged")
}
