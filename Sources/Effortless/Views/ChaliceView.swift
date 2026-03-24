import SwiftUI

struct ChaliceView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always-visible compact view
            HStack(spacing: 14) {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 16, weight: .ultraLight))
                    .foregroundColor(.secondary)

                if let ctx = sessionManager.activeContext {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ctx.label)
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        if let current = ctx.currentTodo {
                            Text(current.text)
                                .font(.system(size: 13, weight: .regular, design: .serif))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(sessionManager.remainingTimeFormatted)
                                .font(.system(size: 12, weight: .light, design: .monospaced))
                                .foregroundColor(.secondary)
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
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
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
