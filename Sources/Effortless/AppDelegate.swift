import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var altarWindow: NSWindow?
    private var chaliceWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let sessionManager = SessionManager()
    private let appearanceManager = AppearanceManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menubar-only app
        NSApp.setActivationPolicy(.accessory)

        appearanceManager.apply()
        setupMenuBar()
        showAltar()
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

        switch sessionManager.state {
        case .idle:
            let titleItem = NSMenuItem(title: "No intention set", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Set Intention…", action: #selector(showAltar), keyEquivalent: "n"))

        case .active(let session):
            let intentionItem = NSMenuItem(title: session.intention, action: nil, keyEquivalent: "")
            intentionItem.isEnabled = false
            menu.addItem(intentionItem)

            let timeItem = NSMenuItem(title: sessionManager.remainingTimeFormatted, action: nil, keyEquivalent: "")
            timeItem.isEnabled = false
            menu.addItem(timeItem)

            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Complete", action: #selector(completeSession), keyEquivalent: "d"))
            menu.addItem(NSMenuItem(title: "Interrupt", action: #selector(interruptSession), keyEquivalent: "i"))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Effortless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func updateMenuBarTitle() {
        if case .active = sessionManager.state {
            statusItem.button?.title = " \(sessionManager.remainingTimeFormatted)"
        } else {
            statusItem.button?.title = ""
        }
    }

    // MARK: - The Altar (Full-Screen Overlay)

    @objc func showAltar() {
        guard altarWindow == nil else { return }

        guard let screen = NSScreen.main else { return }

        let altarView = AltarView(onBegin: { [weak self] intention, minutes in
            self?.beginSession(intention: intention, minutes: minutes)
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

    private func showChalice() {
        guard chaliceWindow == nil else { return }
        guard let screen = NSScreen.main else { return }

        let chaliceView = ChaliceView(sessionManager: sessionManager)

        let windowWidth: CGFloat = 280
        let windowHeight: CGFloat = 80
        let padding: CGFloat = 20
        let frame = NSRect(
            x: screen.visibleFrame.maxX - windowWidth - padding,
            y: screen.visibleFrame.maxY - windowHeight - padding,
            width: windowWidth,
            height: windowHeight
        )

        let window = ChaliceWindow(
            contentRect: frame,
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
        window.orderFront(nil)

        chaliceWindow = window
    }

    private func hideChalice() {
        chaliceWindow?.orderOut(nil)
        chaliceWindow?.contentView = nil
        chaliceWindow = nil
    }

    // MARK: - Settings

    @objc private func showSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appearance: appearanceManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 140),
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

    // MARK: - Session Actions

    private func beginSession(intention: String, minutes: Int) {
        sessionManager.begin(intention: intention, minutes: minutes)
        dismissAltar()
        if appearanceManager.chaliceDisplay == .menuBarAndFloat {
            showChalice()
        }
    }

    @objc private func completeSession() {
        sessionManager.complete()
        hideChalice()
        showAltar()
    }

    @objc private func interruptSession() {
        sessionManager.interrupt()
        hideChalice()
        showAltar()
    }

    @objc private func sessionStateChanged() {
        updateMenu()
        updateMenuBarTitle()

        if case .idle = sessionManager.state {
            hideChalice()
            showAltar()
        }
    }

    @objc private func chaliceDisplayChanged() {
        guard case .active = sessionManager.state else { return }
        if appearanceManager.chaliceDisplay == .menuBarAndFloat {
            showChalice()
        } else {
            hideChalice()
        }
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
    private var cornerIndex = 0
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
