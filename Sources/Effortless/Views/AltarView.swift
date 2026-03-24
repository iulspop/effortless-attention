import SwiftUI

extension Notification.Name {
    static let altarAddToQueue = Notification.Name("altarAddToQueue")
}

struct AltarView: View {
    @ObservedObject var sessionManager: SessionManager
    var onDismiss: () -> Void

    @State private var isCreatingNew = false
    @State private var selectedIndex: Int? = nil
    @State private var keyMonitor: Any? = nil

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Whether the workspace (not a text field) should handle keyboard shortcuts
    private var isWorkspaceMode: Bool {
        !sessionManager.contexts.isEmpty && !isCreatingNew
    }

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

                if sessionManager.contexts.isEmpty && !isCreatingNew {
                    // No contexts — simple flow (no label prompt)
                    QuickContextFlow(onCreated: { intention, minutes in
                        sessionManager.addContext(label: "Context", intention: intention, minutes: minutes)
                        onDismiss()
                    })
                } else {
                    workspaceView
                }

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

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept if a text field has focus
            if let firstResponder = NSApp.keyWindow?.firstResponder,
               firstResponder is NSTextView || firstResponder is NSTextField {
                return event
            }

            guard isWorkspaceMode else { return event }

            switch event.keyCode {
            case 126: // ↑
                moveSelection(-1)
                return nil
            case 125: // ↓
                moveSelection(1)
                return nil
            case 45: // N
                isCreatingNew = true
                return nil
            case 36: // Enter
                NotificationCenter.default.post(name: .altarAddToQueue, object: nil)
                return nil
            case 53: // Escape
                if !sessionManager.contexts.isEmpty {
                    if let sel = selectedIndex {
                        sessionManager.switchTo(index: sel)
                    }
                    onDismiss()
                    return nil
                }
                return event
            default:
                // 1-9 jump to context
                let numKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
                if let num = numKeyCodes[event.keyCode],
                   num >= 1, num <= sessionManager.contexts.count {
                    selectedIndex = num - 1
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

    // MARK: - Workspace (has contexts)

    private var workspaceView: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: context list
            contextSidebar
                .frame(width: 240)

            Divider()
                .padding(.vertical, 20)

            // Right: detail view
            if isCreatingNew {
                NewContextFlow(onCreated: { label, intention, minutes in
                    sessionManager.addContext(label: label, intention: intention, minutes: minutes)
                    isCreatingNew = false
                    selectedIndex = sessionManager.contexts.count - 1
                }, onCancel: {
                    isCreatingNew = false
                })
                .frame(maxWidth: .infinity)
            } else if let idx = selectedIndex, idx < sessionManager.contexts.count {
                ContextDetailView(
                    sessionManager: sessionManager,
                    contextIndex: idx,
                    onDismiss: onDismiss
                )
                .frame(maxWidth: .infinity)
                .id(idx)
            } else {
                Text("Select a context")
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 900, maxHeight: 500)
    }

    private func moveSelection(_ delta: Int) {
        let count = sessionManager.contexts.count
        guard count > 0 else { return }
        let current = selectedIndex ?? 0
        let next = (current + delta + count) % count
        selectedIndex = next
    }

    private var contextSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(sessionManager.contexts.enumerated()), id: \.element.id) { index, ctx in
                contextRow(ctx, index: index)
            }

            Spacer().frame(height: 12)

            Button(action: { isCreatingNew = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("New Context")
                    Spacer()
                    Text("n")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 24)

            // Dismiss button — available if any contexts exist
            if !sessionManager.contexts.isEmpty {
                Button(action: {
                    if let sel = selectedIndex {
                        sessionManager.switchTo(index: sel)
                    }
                    onDismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                        Text("Return to session")
                        Spacer()
                        Text("esc")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
    }

    private func contextRow(_ ctx: CognitiveContext, index: Int) -> some View {
        let isActive = index == sessionManager.activeIndex
        let isSelected = index == selectedIndex

        return Button(action: {
            selectedIndex = index
            isCreatingNew = false
        }) {
            HStack(spacing: 8) {
                // Position number
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(ctx.label)
                            .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .serif))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if isActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                    }

                    if let current = ctx.currentTodo {
                        Text(current.text)
                            .font(.system(size: 11, weight: .light, design: .serif))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("No intention")
                            .font(.system(size: 11, weight: .light, design: .serif))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }

                Spacer()

                if ctx.todosTotal > 0 {
                    Text("\(ctx.todosCompleted)/\(ctx.todosTotal)")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Context Flow (first launch — no label prompt)

struct QuickContextFlow: View {
    var onCreated: (String, Int) -> Void

    enum Step { case outcome, minutes }

    @State private var step: Step = .outcome
    @State private var intention: String = ""
    @State private var minutesText: String = ""
    @FocusState private var isOutcomeFocused: Bool
    @FocusState private var isMinutesFocused: Bool

    private let quickOptions: [(key: String, minutes: Int)] = [
        ("q", 5), ("w", 25), ("e", 90)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.secondary)
                .padding(.bottom, 48)

            switch step {
            case .outcome:
                outcomeStep
            case .minutes:
                minutesStep
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isOutcomeFocused = true
            }
        }
    }

    private var outcomeStep: some View {
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
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
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

    private func selectQuickOption(_ minutes: Int) {
        let trimmed = intention.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreated(trimmed, minutes)
    }

    private func submitMinutes() {
        let trimmed = intention.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces)), minutes > 0 else { return }
        onCreated(trimmed, minutes)
    }
}

// MARK: - New Context Creation Flow (with label)

struct NewContextFlow: View {
    var onCreated: (String, String, Int) -> Void
    var onCancel: (() -> Void)? = nil

    enum Step { case label, outcome, minutes }

    @State private var step: Step = .label
    @State private var label: String = ""
    @State private var intention: String = ""
    @State private var minutesText: String = ""
    @FocusState private var isLabelFocused: Bool
    @FocusState private var isOutcomeFocused: Bool
    @FocusState private var isMinutesFocused: Bool

    private let quickOptions: [(key: String, minutes: Int)] = [
        ("q", 5), ("w", 25), ("e", 90)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.secondary)
                .padding(.bottom, 48)

            switch step {
            case .label:
                labelStep
            case .outcome:
                outcomeStep
            case .minutes:
                minutesStep
            }

            if onCancel != nil {
                Button("Cancel") { onCancel?() }
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                    .padding(.top, 32)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isLabelFocused = true
            }
        }
    }

    private var labelStep: some View {
        VStack(spacing: 0) {
            Text("Name this context")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundColor(.primary)
                .padding(.bottom, 32)

            TextField("", text: $label)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(maxWidth: 400)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                )
                .focused($isLabelFocused)
                .onSubmit {
                    let trimmed = label.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    step = .outcome
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isOutcomeFocused = true
                    }
                }
        }
    }

    private var outcomeStep: some View {
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
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
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

    private func selectQuickOption(_ minutes: Int) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let trimmedIntention = intention.trimmingCharacters(in: .whitespaces)
        guard !trimmedLabel.isEmpty, !trimmedIntention.isEmpty else { return }
        onCreated(trimmedLabel, trimmedIntention, minutes)
    }

    private func submitMinutes() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let trimmedIntention = intention.trimmingCharacters(in: .whitespaces)
        guard !trimmedLabel.isEmpty, !trimmedIntention.isEmpty else { return }
        guard let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces)), minutes > 0 else { return }
        onCreated(trimmedLabel, trimmedIntention, minutes)
    }
}

// MARK: - Context Detail View

struct ContextDetailView: View {
    @ObservedObject var sessionManager: SessionManager
    let contextIndex: Int
    var onDismiss: () -> Void

    enum AddStep { case idle, text, minutes }

    @State private var addStep: AddStep = .idle
    @State private var newTodoText: String = ""
    @State private var newTodoMinutes: String = ""
    @FocusState private var isTodoTextFocused: Bool
    @FocusState private var isTodoMinutesFocused: Bool

    private let quickOptions: [(key: String, minutes: Int)] = [
        ("q", 5), ("w", 25), ("e", 90)
    ]

    private var context: CognitiveContext? {
        guard contextIndex >= 0, contextIndex < sessionManager.contexts.count else { return nil }
        return sessionManager.contexts[contextIndex]
    }

    var body: some View {
        if let ctx = context {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Label (editable)
                    EditableText(
                        text: ctx.label,
                        font: .system(size: 20, weight: .semibold, design: .serif),
                        onCommit: { sessionManager.updateLabel($0, at: contextIndex) }
                    )

                    // Current intention
                    if let current = ctx.currentTodo {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Intention")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)

                            HStack {
                                Text(current.text)
                                    .font(.system(size: 16, weight: .regular, design: .serif))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(formatTime(current.remainingSeconds))
                                    .font(.system(size: 14, weight: .light, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No active intention — add one below")
                            .font(.system(size: 14, weight: .light, design: .serif))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Todo queue
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Queue")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        ForEach(ctx.todos) { todo in
                            HStack(spacing: 8) {
                                Image(systemName: todo.completed ? "checkmark.circle.fill" : (todo.id == ctx.currentTodo?.id ? "arrow.right.circle.fill" : "circle"))
                                    .foregroundColor(todo.completed ? .green : (todo.id == ctx.currentTodo?.id ? .accentColor : .secondary))
                                    .font(.system(size: 16))

                                EditableText(
                                    text: todo.text,
                                    font: .system(size: 14, weight: .regular, design: .serif),
                                    strikethrough: todo.completed,
                                    color: todo.completed ? .secondary : .primary,
                                    onCommit: { sessionManager.updateTodoText($0, todoId: todo.id, at: contextIndex) }
                                )

                                Spacer()

                                Text("\(todo.timeboxMinutes)m")
                                    .font(.system(size: 12, weight: .light, design: .monospaced))
                                    .foregroundColor(.secondary)

                                if !todo.completed {
                                    Button(action: {
                                        sessionManager.removeTodo(todoId: todo.id, at: contextIndex)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        // Add new todo
                        switch addStep {
                        case .idle:
                            Button(action: {
                                addStep = .text
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isTodoTextFocused = true
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                    Text("Add to queue…")
                                        .font(.system(size: 14, weight: .regular, design: .serif))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)

                        case .text:
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                                TextField("What's the intention?", text: $newTodoText)
                                    .font(.system(size: 14, weight: .regular, design: .serif))
                                    .textFieldStyle(.plain)
                                    .focused($isTodoTextFocused)
                                    .onSubmit {
                                        let trimmed = newTodoText.trimmingCharacters(in: .whitespaces)
                                        guard !trimmed.isEmpty else { return }
                                        addStep = .minutes
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            isTodoMinutesFocused = true
                                        }
                                    }
                                    .onExitCommand { cancelAdd() }
                            }
                            .padding(.top, 4)

                        case .minutes:
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 14))
                                    Text("Minutes for \"\(newTodoText)\":")
                                        .font(.system(size: 13, weight: .light, design: .serif))
                                        .foregroundColor(.secondary)
                                    TextField("", text: $newTodoMinutes)
                                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                                        .textFieldStyle(.plain)
                                        .frame(width: 50)
                                        .focused($isTodoMinutesFocused)
                                        .onSubmit { submitNewTodo() }
                                        .onExitCommand { cancelAdd() }
                                }

                                HStack(spacing: 12) {
                                    ForEach(Array(quickOptions.enumerated()), id: \.offset) { _, option in
                                        Button(action: { submitNewTodoQuick(option.minutes) }) {
                                            HStack(spacing: 4) {
                                                Text(option.key)
                                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                Text("\(option.minutes)m")
                                                    .font(.system(size: 12, weight: .light, design: .serif))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 4)
                            .onKeyPress(characters: .init(charactersIn: "qwe")) { press in
                                let key = String(press.characters)
                                if let option = quickOptions.first(where: { $0.key == key }) {
                                    submitNewTodoQuick(option.minutes)
                                    return .handled
                                }
                                return .ignored
                            }
                        }
                    }

                    Spacer().frame(height: 12)

                    // Delete context
                    Button(action: {
                        sessionManager.removeContext(at: contextIndex)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Remove context")
                        }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
            .onReceive(NotificationCenter.default.publisher(for: .altarAddToQueue)) { _ in
                if addStep == .idle {
                    addStep = .text
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTodoTextFocused = true
                    }
                }
            }
        }
    }

    private func cancelAdd() {
        newTodoText = ""
        newTodoMinutes = ""
        addStep = .idle
    }

    private func submitNewTodo() {
        let text = newTodoText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard let minutes = Int(newTodoMinutes.trimmingCharacters(in: .whitespaces)), minutes > 0 else { return }
        sessionManager.addTodo(text: text, minutes: minutes, at: contextIndex)
        newTodoText = ""
        newTodoMinutes = ""
        addStep = .idle
    }

    private func submitNewTodoQuick(_ minutes: Int) {
        let text = newTodoText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sessionManager.addTodo(text: text, minutes: minutes, at: contextIndex)
        newTodoText = ""
        newTodoMinutes = ""
        addStep = .idle
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Editable Text Helper

struct EditableText: View {
    let text: String
    let font: Font
    var strikethrough: Bool = false
    var color: Color = .primary
    let onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField("", text: $editText)
                .font(font)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    let trimmed = editText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onCommit(trimmed)
                    }
                    isEditing = false
                }
                .onExitCommand { isEditing = false }
                .onAppear {
                    editText = text
                    isFocused = true
                }
        } else {
            Text(text)
                .font(font)
                .strikethrough(strikethrough)
                .foregroundColor(color)
                .onTapGesture {
                    isEditing = true
                }
                .help("Click to edit")
        }
    }
}
