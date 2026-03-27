import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var altarWindow: NSWindow?
    private var chaliceWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var resumeWindow: NSWindow?
    private var expiryWindow: NSWindow?
    private var interruptionWindow: NSWindow?
    private var mirrorWindow: NSWindow?
    private var idleTimer: Timer?
    private let sessionManager = SessionManager()
    private let transitionLogger = TransitionLogger()
    private let appearanceManager = AppearanceManager.shared
    private let hotkeyManager = HotkeyManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menubar-only app
        NSApp.setActivationPolicy(.accessory)

        appearanceManager.apply()
        setupMenuBar()
        setupHotkeys()

        if sessionManager.isPaused && !sessionManager.contexts.isEmpty {
            // Restored in paused state — show resume screen
            updateMenu()
            updateMenuBarTitle()
            showResumeScreen()
        } else if !sessionManager.contexts.isEmpty && sessionManager.hasActiveIntention {
            // Restored from disk with active intention — go straight to session
            updateMenu()
            updateMenuBarTitle()
            if appearanceManager.chaliceDisplay == .menuBarAndFloat {
                showChalice()
                chaliceWindow?.alphaValue = 0
                DispatchQueue.main.async { [weak self] in
                    if let frame = self?.chaliceFrame() {
                        self?.chaliceWindow?.setFrame(frame, display: true)
                    }
                    self?.chaliceWindow?.alphaValue = 1
                }
            }
        } else {
            showAltar()
        }

        // Listen for when queue empties mid-session
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(needsIntention),
            name: .needsIntention,
            object: nil
        )

        // Listen for timer expiry
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timerExpired),
            name: .timerExpired,
            object: nil
        )

        // Listen for interruption escape hatch prompt
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(needsInterruptionIntention),
            name: .needsInterruptionIntention,
            object: nil
        )

        // Start idle auto-pause monitor
        startIdleMonitor()
    }

    // MARK: - Menu Bar (The Chalice)

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "Effortless")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        updateMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionStateChanged),
            name: .sessionStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(chaliceDisplayChanged),
            name: .chaliceDisplayChanged,
            object: nil
        )
    }

    private func updateMenu() {
        let menu = NSMenu()

        if sessionManager.contexts.isEmpty {
            let titleItem = NSMenuItem(title: "No intention set", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Set Intention…", action: #selector(showAltar), keyEquivalent: "n"))
        } else {
            for (index, ctx) in sessionManager.contexts.enumerated() {
                let isActive = index == sessionManager.activeIndex
                let prefix = isActive ? "● " : "  "
                let timeStr = ctx.hasActiveIntention ? formatTime(ctx.remainingSeconds) : "idle"
                let title = "\(prefix)\(ctx.label)  \(timeStr)"
                let item = NSMenuItem(title: title, action: #selector(switchToContextFromMenu(_:)), keyEquivalent: "")
                item.tag = index
                if isActive {
                    item.state = .on
                }
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Open Altar…", action: #selector(showAltar), keyEquivalent: "a"))
            if sessionManager.isPaused {
                menu.addItem(NSMenuItem(title: "Resume", action: #selector(menuTogglePause), keyEquivalent: "p"))
            } else {
                menu.addItem(NSMenuItem(title: "Pause", action: #selector(menuTogglePause), keyEquivalent: "p"))
                if sessionManager.hasActiveIntention {
                    if sessionManager.isInInterruption {
                        menu.addItem(NSMenuItem(title: "Complete Interruption", action: #selector(completeSession), keyEquivalent: "d"))
                    } else {
                        menu.addItem(NSMenuItem(title: "Complete", action: #selector(completeSession), keyEquivalent: "d"))
                    }
                    menu.addItem(NSMenuItem(title: "Interrupt", action: #selector(interruptSession), keyEquivalent: "i"))
                }
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Mirror…", action: #selector(showMirror), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Effortless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func updateMenuBarTitle() {
        if sessionManager.isPaused {
            statusItem.button?.title = " ⏸ Paused"
        } else if sessionManager.isInInterruption, let ctx = sessionManager.activeContext, ctx.hasActiveIntention {
            statusItem.button?.title = " ⚡ \(ctx.currentTodo?.text ?? "Interruption") \(sessionManager.remainingTimeFormatted)"
        } else if let ctx = sessionManager.activeContext, ctx.hasActiveIntention {
            statusItem.button?.title = " \(ctx.label) \(sessionManager.remainingTimeFormatted)"
        } else {
            statusItem.button?.title = ""
        }
    }

    @objc private func switchToContextFromMenu(_ sender: NSMenuItem) {
        sessionManager.switchTo(index: sender.tag)
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager.setHandler(for: .complete) { [weak self] in
            self?.completeSession()
        }
        hotkeyManager.setHandler(for: .interrupt) { [weak self] in
            self?.interruptSession()
        }
        hotkeyManager.setHandler(for: .openAltar) { [weak self] in
            guard let self else { return }
            if self.sessionManager.isPaused && self.resumeWindow != nil {
                // In resume mode → switch to full altar
                self.dismissResumeScreen()
                self.showAltar()
            } else {
                self.toggleAltar()
            }
        }
        hotkeyManager.setHandler(for: .togglePause) { [weak self] in
            self?.togglePause()
        }
        hotkeyManager.setHandler(for: .cycleNext) { [weak self] in
            self?.sessionManager.cycleNext()
        }
        hotkeyManager.setHandler(for: .cyclePrev) { [weak self] in
            self?.sessionManager.cyclePrev()
        }
        hotkeyManager.setHandler(for: .openMirror) { [weak self] in
            self?.toggleMirror()
        }
        hotkeyManager.onContextJump = { [weak self] index in
            self?.sessionManager.switchTo(index: index)
        }
    }

    // MARK: - The Altar (Full-Screen Overlay)

    private func toggleAltar() {
        if altarWindow != nil {
            // Dismiss if any contexts exist (even without active intention)
            if !sessionManager.contexts.isEmpty {
                dismissAltar()
                if appearanceManager.chaliceDisplay == .menuBarAndFloat {
                    showChalice()
                }
            }
        } else {
            showAltar()
        }
    }

    @objc func showAltar() {
        guard altarWindow == nil else { return }
        guard let screen = NSScreen.main else { return }

        // Dismiss mirror if open — only one fullscreen surface at a time
        if mirrorWindow != nil { dismissMirror() }

        let altarView = AltarView(sessionManager: sessionManager, onDismiss: { [weak self] in
            self?.dismissAltar()
            if self?.appearanceManager.chaliceDisplay == .menuBarAndFloat {
                self?.showChalice()
            }
        })

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: altarView)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)

        // Ensure the app is active so the window receives input
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)

        // Lock down: disable Mission Control, Exposé, app switching, Dock
        NSApp.presentationOptions = [
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication,
            .disableAppleMenu,
            .disableMenuBarTransparency,
            .hideMenuBar,
            .hideDock
        ]

        altarWindow = window
        hideChalice()
    }

    private func dismissAltar() {
        // Restore normal presentation
        NSApp.presentationOptions = []

        altarWindow?.orderOut(nil)
        altarWindow?.contentView = nil
        altarWindow = nil
    }

    // MARK: - The Chalice (Floating Overlay)

    private func chaliceFrame() -> NSRect? {
        guard let screen = NSScreen.main else { return nil }
        let windowWidth: CGFloat = 280
        let windowHeight: CGFloat = 120
        let padding: CGFloat = 20
        return NSRect(
            x: screen.visibleFrame.maxX - windowWidth - padding,
            y: screen.visibleFrame.minY + padding,
            width: windowWidth,
            height: windowHeight
        )
    }

    private func showChalice() {
        if let existing = chaliceWindow {
            // Reposition to correct location (screen geometry may have changed)
            if let frame = chaliceFrame() {
                existing.setFrame(frame, display: false)
            }
            existing.level = .floating
            existing.orderFrontRegardless()
            existing.contentView?.needsDisplay = true
            existing.contentView?.needsLayout = true
            existing.displayIfNeeded()
            return
        }

        let chaliceView = ChaliceView(sessionManager: sessionManager)

        let window = ChaliceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: chaliceView)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        // Position using setFrame (same path as reposition/cycling)
        if let frame = chaliceFrame() {
            window.setFrame(frame, display: true)
        }
        window.orderFront(nil)

        chaliceWindow = window

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(chaliceHoverChanged(_:)),
            name: .chaliceHoverChanged,
            object: nil
        )
    }

    @objc private func chaliceHoverChanged(_ notification: Notification) {
        guard let window = chaliceWindow,
              let _ = (notification.object as? NSNumber)?.boolValue else { return }
        guard let hostingView = window.contentView as? NSHostingView<ChaliceView> else { return }

        let fittingSize = hostingView.fittingSize
        let width: CGFloat = 280
        let height = max(120, fittingSize.height)

        // Grow upward from current bottom edge
        let newY = window.frame.origin.y + window.frame.height - height
        let newFrame = NSRect(x: window.frame.origin.x, y: newY, width: width, height: height)
        window.setFrame(newFrame, display: true)
    }

    private func hideChalice() {
        chaliceWindow?.orderOut(nil)
    }

    // MARK: - Settings

    @objc private func showSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appearance: appearanceManager, hotkeyManager: hotkeyManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: settingsView)
        window.title = "Effortless Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    // MARK: - Mirror

    private func toggleMirror() {
        if mirrorWindow != nil {
            dismissMirror()
        } else {
            showMirror()
        }
    }

    @objc private func showMirror() {
        if mirrorWindow != nil { return }
        guard let screen = NSScreen.main else { return }

        // Dismiss altar if open — only one fullscreen surface at a time
        if altarWindow != nil { dismissAltar() }

        let events = transitionLogger.loadToday()
        let mirrorView = MirrorView(events: events) { [weak self] in
            self?.dismissMirror()
        }

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: mirrorView)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)

        NSApp.presentationOptions = [
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication,
            .disableAppleMenu,
            .disableMenuBarTransparency,
            .hideMenuBar,
            .hideDock
        ]

        mirrorWindow = window
        hideChalice()
    }

    private func dismissMirror() {
        NSApp.presentationOptions = []
        mirrorWindow?.orderOut(nil)
        mirrorWindow?.contentView = nil
        mirrorWindow = nil

        if appearanceManager.chaliceDisplay == .menuBarAndFloat,
           sessionManager.hasActiveIntention, !sessionManager.isPaused {
            showChalice()
        }
    }

    // MARK: - Pause / Resume

    private func togglePause() {
        guard !sessionManager.contexts.isEmpty else { return }

        if sessionManager.isPaused {
            // Resume from pause
            sessionManager.resume()
            dismissResumeScreen()
            if appearanceManager.chaliceDisplay == .menuBarAndFloat {
                showChalice()
            }
        } else {
            // Pause
            sessionManager.pause()
            hideChalice()
            showResumeScreen()
        }
        updateMenu()
        updateMenuBarTitle()
    }

    private func showResumeScreen() {
        guard resumeWindow == nil else { return }
        guard let screen = NSScreen.main else { return }

        let resumeView = ResumeView(
            sessionManager: sessionManager,
            onResume: { [weak self] in
                guard let self else { return }
                self.dismissResumeScreen()
                if self.appearanceManager.chaliceDisplay == .menuBarAndFloat {
                    self.showChalice()
                }
                self.updateMenu()
                self.updateMenuBarTitle()
            },
            onSwitchToAltar: { [weak self] in
                guard let self else { return }
                self.dismissResumeScreen()
                self.showAltar()
            }
        )

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: resumeView)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)

        // Lock down same as altar
        NSApp.presentationOptions = [
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication,
            .disableAppleMenu,
            .disableMenuBarTransparency,
            .hideMenuBar,
            .hideDock
        ]

        resumeWindow = window
    }

    private func dismissResumeScreen() {
        NSApp.presentationOptions = []
        resumeWindow?.orderOut(nil)
        resumeWindow?.contentView = nil
        resumeWindow = nil
    }

    // MARK: - Idle Auto-Pause

    private func startIdleMonitor() {
        stopIdleMonitor()
        let minutes = appearanceManager.idleTimeoutMinutes
        guard minutes > 0 else { return } // 0 = disabled

        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.sessionManager.isPaused, self.sessionManager.hasActiveIntention else { return }
                let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
                let idleSecondsKb = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
                let idle = min(idleSeconds, idleSecondsKb)
                if idle >= Double(minutes) * 60 {
                    self.togglePause()
                }
            }
        }
    }

    private func stopIdleMonitor() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - Session Actions

    @objc private func menuTogglePause() {
        togglePause()
    }

    @objc private func completeSession() {
        if sessionManager.isInInterruption {
            sessionManager.completeInterruption()
        } else {
            sessionManager.complete()
        }
    }

    @objc private func interruptSession() {
        // If already showing the interruption prompt, ignore
        guard interruptionWindow == nil else { return }
        sessionManager.interrupt()
    }

    @objc private func needsInterruptionIntention() {
        hideChalice()
        showInterruptionPrompt()
    }

    @objc private func sessionStateChanged() {
        updateMenu()
        updateMenuBarTitle()

        if sessionManager.contexts.isEmpty {
            hideChalice()
            showAltar()
        } else {
            // Restart idle monitor when session state changes
            startIdleMonitor()
        }
    }

    @objc private func needsIntention() {
        // Queue empty on active context — open altar to prompt
        hideChalice()
        showAltar()
    }

    @objc private func timerExpired() {
        hideChalice()
        showExpiryAltar()
    }

    private func showExpiryAltar() {
        guard expiryWindow == nil else { return }
        guard let screen = NSScreen.main else { return }

        let todoText = sessionManager.activeContext?.currentTodo?.text ?? "your intention"

        let expiryView = TimerExpiryView(
            intentionText: todoText,
            onExtend: { [weak self] minutes in
                self?.sessionManager.extendTime(minutes: minutes)
                self?.dismissExpiryAltar()
                if self?.appearanceManager.chaliceDisplay == .menuBarAndFloat {
                    self?.showChalice()
                }
                self?.updateMenu()
                self?.updateMenuBarTitle()
            },
            onComplete: { [weak self] in
                self?.sessionManager.completeExpired()
                self?.dismissExpiryAltar()
            }
        )

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: expiryView)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)

        NSApp.presentationOptions = [
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication,
            .disableAppleMenu,
            .disableMenuBarTransparency,
            .hideMenuBar,
            .hideDock
        ]

        expiryWindow = window
    }

    private func dismissExpiryAltar() {
        NSApp.presentationOptions = []
        expiryWindow?.orderOut(nil)
        expiryWindow?.contentView = nil
        expiryWindow = nil
    }

    // MARK: - Interruption Prompt (Escape Hatch)

    private func showInterruptionPrompt() {
        guard interruptionWindow == nil else { return }
        guard let screen = NSScreen.main else { return }

        let promptView = InterruptionPromptView(
            interruptionDepth: sessionManager.interruptionDepth - 1, // depth before this interrupt
            onConfirm: { [weak self] intention, minutes in
                self?.sessionManager.beginInterruption(intention: intention, minutes: minutes)
                self?.dismissInterruptionPrompt()
                if self?.appearanceManager.chaliceDisplay == .menuBarAndFloat {
                    self?.showChalice()
                }
                self?.updateMenu()
                self?.updateMenuBarTitle()
            },
            onCancel: { [weak self] in
                self?.sessionManager.cancelInterrupt()
                self?.dismissInterruptionPrompt()
                if self?.appearanceManager.chaliceDisplay == .menuBarAndFloat {
                    self?.showChalice()
                }
            }
        )

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: promptView)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)

        NSApp.presentationOptions = [
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication,
            .disableAppleMenu,
            .disableMenuBarTransparency,
            .hideMenuBar,
            .hideDock
        ]

        interruptionWindow = window
    }

    private func dismissInterruptionPrompt() {
        NSApp.presentationOptions = []
        interruptionWindow?.orderOut(nil)
        interruptionWindow?.contentView = nil
        interruptionWindow = nil
    }

    @objc private func chaliceDisplayChanged() {
        guard !sessionManager.contexts.isEmpty else { return }
        if appearanceManager.chaliceDisplay == .menuBarAndFloat {
            showChalice()
        } else {
            hideChalice()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Borderless windows refuse key status by default — override so text fields work.
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Floating chalice window: click+release cycles corners, click+drag moves freely.
class ChaliceWindow: NSWindow {
    private var mouseDownLocation: NSPoint?
    private var dragThreshold: CGFloat = 5
    private var isDragging = false
    /// Corners cycle: top-right → bottom-right → bottom-left → top-left
    private var cornerIndex = 1 // start at bottom-right
    private let padding: CGFloat = 20

    override var canBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let current = NSEvent.mouseLocation
        let distance = hypot(current.x - start.x, current.y - start.y)

        if distance > dragThreshold {
            isDragging = true
            // Standard window drag
            let origin = NSPoint(
                x: frame.origin.x + event.deltaX,
                y: frame.origin.y - event.deltaY
            )
            setFrameOrigin(origin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            cycleCorner()
        }
        mouseDownLocation = nil
        isDragging = false
    }

    private func cycleCorner() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let w = frame.width
        let h = frame.height

        cornerIndex = (cornerIndex + 1) % 4

        let origin: NSPoint
        switch cornerIndex {
        case 0: // top-right
            origin = NSPoint(x: area.maxX - w - padding, y: area.maxY - h - padding)
        case 1: // bottom-right
            origin = NSPoint(x: area.maxX - w - padding, y: area.minY + padding)
        case 2: // bottom-left
            origin = NSPoint(x: area.minX + padding, y: area.minY + padding)
        case 3: // top-left
            origin = NSPoint(x: area.minX + padding, y: area.maxY - h - padding)
        default:
            origin = frame.origin
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrameOrigin(origin)
        }
    }
}
