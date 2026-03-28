import AppKit
import ApplicationServices

/// Watches the user's active app and window title, firing a callback on every change.
@MainActor
class AttentionMonitor {
    struct AppContext: Equatable, Sendable {
        let appName: String
        let windowTitle: String
        let bundleId: String?
    }

    var onChange: ((AppContext) -> Void)?

    private var workspaceObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var lastContext: AppContext?

    /// Our own bundle ID so we can ignore self-activation.
    private let ownBundleId = Bundle.main.bundleIdentifier ?? "com.iulspop.effortless"

    func start() {
        // Listen for app activation events
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.handleAppSwitch(app)
        }

        // Poll window title every 2s — AX title change observers are unreliable
        // and require per-app registration. Polling is simple and low-cost.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkCurrentContext()
        }

        // Fire initial check
        checkCurrentContext()
    }

    func stop() {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        lastContext = nil
    }

    /// Reset context tracking so the next poll fires onChange even for the same app.
    func resetLastContext() {
        lastContext = nil
    }

    private func handleAppSwitch(_ app: NSRunningApplication) {
        let bundleId = app.bundleIdentifier
        // Ignore our own app activating (altar, mirror, etc.)
        if bundleId == ownBundleId { return }

        let appName = app.localizedName ?? "Unknown"
        // Window title may not be ready yet at activation time — fire with what we have,
        // the poll timer will pick up the title shortly after.
        let windowTitle = Self.windowTitle(for: app) ?? ""
        let ctx = AppContext(appName: appName, windowTitle: windowTitle, bundleId: bundleId)
        lastContext = ctx
        onChange?(ctx)
    }

    private func checkCurrentContext() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = app.bundleIdentifier
        if bundleId == ownBundleId { return }

        let appName = app.localizedName ?? "Unknown"
        let windowTitle = Self.windowTitle(for: app) ?? ""
        let ctx = AppContext(appName: appName, windowTitle: windowTitle, bundleId: bundleId)
        // Always fire if title changed (e.g. tab switch within same browser)
        if ctx != lastContext {
            lastContext = ctx
            onChange?(ctx)
        }
    }

    /// Request accessibility permission — opens System Settings if not granted.
    static func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Get the window title of an app's frontmost window via Accessibility API.
    static func windowTitle(for app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success, let window = focusedWindow else { return nil }

        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        guard titleResult == .success, let titleStr = title as? String else { return nil }

        return titleStr
    }
}
