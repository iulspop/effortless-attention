import AppKit
import Foundation

/// Orchestrates the nudge escalation: gentle → flash → sharp.
/// Pure polling architecture: every few seconds, ask the LLM if the user is distracted.
/// No event-driven dedup, no stale state, no races.
@MainActor
class NudgeManager: ObservableObject {

    enum NudgeState: Equatable {
        case idle
        case gentle(app: String, windowTitle: String)
        case flash
        case sharp
        case grace
    }

    @Published private(set) var state: NudgeState = .idle

    var onGentleNudge: ((String, String) -> Void)?
    var onDismissGentleNudge: (() -> Void)?
    var onFlash: (() -> Void)?
    var onSharpPrompt: (() -> Void)?
    var onDismissSharpPrompt: (() -> Void)?

    /// Provides current intention for LLM queries.
    var intentionProvider: (() -> (intention: String, contextLabel: String, contextId: UUID)?)?

    private let appearanceManager: AppearanceManager
    private let allowlistStore: AllowlistStore
    private var ollamaClient: OllamaClient

    private var pollTimer: Timer?
    private var escalationTimer: Timer?
    private var flashTimer: Timer?
    private var graceTimer: Timer?
    private var pendingAssessment: Task<Void, Never>?

    private(set) var isStarted = false

    /// Our own bundle ID so we can ignore self-activation.
    private let ownBundleId = Bundle.main.bundleIdentifier ?? "com.iulspop.effortless"

    init(appearanceManager: AppearanceManager = .shared,
         allowlistStore: AllowlistStore = AllowlistStore()) {
        self.appearanceManager = appearanceManager
        self.allowlistStore = allowlistStore
        self.ollamaClient = OllamaClient(model: appearanceManager.ollamaModel)
    }

    func start() {
        guard appearanceManager.nudgeEnabled else { return }
        guard !isStarted else { return }
        isStarted = true

        let configuredModel = appearanceManager.ollamaModel
        if configuredModel.isEmpty || configuredModel == "auto" {
            Task {
                let models = await OllamaClient.availableModels()
                guard let first = models.first else {
                    isStarted = false
                    return
                }
                self.ollamaClient = OllamaClient(model: first)
                self.startPolling()
            }
        } else {
            ollamaClient = OllamaClient(model: configuredModel)
            startPolling()
        }
    }

    func stop() {
        stopPolling()
        cancelAllTimers()
        pendingAssessment?.cancel()
        pendingAssessment = nil
        transitionTo(.idle)
        isStarted = false
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        // Fire immediately
        poll()
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Core loop: called every 3 seconds.
    private func poll() {
        guard isStarted else { return }

        // Don't poll during escalation — user must interact with the prompt
        switch state {
        case .flash, .sharp, .grace:
            return
        default:
            break
        }

        // Need an active intention to assess against
        guard let info = intentionProvider?() else {
            // No intention — dismiss any nudge
            if state != .idle {
                transitionTo(.idle)
            }
            return
        }

        // Get frontmost app
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = app.bundleIdentifier
        if bundleId == ownBundleId || app.localizedName == "Effortless" { return }

        let appName = app.localizedName ?? "Unknown"
        let windowTitle = AttentionMonitor.windowTitle(for: app) ?? ""

        // Cancel any in-flight assessment — we'll start a fresh one
        pendingAssessment?.cancel()

        let query = OllamaClient.DistractionQuery(
            intention: info.intention,
            contextLabel: info.contextLabel,
            activeApp: appName,
            windowTitle: windowTitle,
            allowedItems: allowlistStore.entries(forContextId: info.contextId)
        )

        pendingAssessment = Task {
            guard let result = await ollamaClient.assess(query) else { return }
            guard !Task.isCancelled else { return }

            if result.isDistracted {
                switch self.state {
                case .idle:
                    // Start gentle nudge
                    self.beginGentleNudge(app: appName, windowTitle: windowTitle)
                case .gentle:
                    // Already nudging — escalation timer handles progression
                    break
                default:
                    break
                }
            } else {
                // Not distracted — dismiss any gentle nudge
                if case .gentle = self.state {
                    self.transitionTo(.idle)
                }
            }
        }
    }

    // MARK: - User Actions

    /// User dismissed gentle nudge with "not distracted".
    func userMarkedNotDistracted() {
        guard case .gentle(let app, let windowTitle) = state else { return }
        if let info = intentionProvider?() {
            let entry = "\(app) - \(windowTitle)"
            allowlistStore.add(entry, forContextId: info.contextId)
        }
        transitionTo(.idle)
    }

    /// User picked "Stop" on sharp prompt — return to intention with grace period.
    func userPickedStop() {
        transitionTo(.grace)
        graceTimer = Timer.scheduledTimer(withTimeInterval: Double(appearanceManager.gracePeriodAfterStop), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.graceTimer = nil
                self?.transitionTo(.idle)
                // Next poll() will re-assess
            }
        }
    }

    /// User picked "Log Interruption" on sharp prompt — delegate handles escape hatch.
    func userPickedInterrupt() {
        transitionTo(.idle)
    }

    // MARK: - Escalation States

    private func beginGentleNudge(app: String, windowTitle: String) {
        guard let info = intentionProvider?() else { return }
        transitionTo(.gentle(app: app, windowTitle: windowTitle))
        let displayName = windowTitle.isEmpty ? app : windowTitle
        onGentleNudge?(displayName, info.intention)

        escalationTimer = Timer.scheduledTimer(withTimeInterval: Double(appearanceManager.gentleNudgeDelay), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.escalationTimer = nil
                self?.escalateToFlash()
            }
        }
    }

    private func escalateToFlash() {
        transitionTo(.flash)

        if appearanceManager.nudgeSoundEnabled {
            NSSound.beep()
        }

        onFlash?()

        flashTimer = Timer.scheduledTimer(withTimeInterval: Double(appearanceManager.flashToSharpDelay), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flashTimer = nil
                self?.escalateToSharp()
            }
        }
    }

    private func escalateToSharp() {
        transitionTo(.sharp)
        onSharpPrompt?()
    }

    // MARK: - State Management

    private func transitionTo(_ newState: NudgeState) {
        let oldState = state
        state = newState

        switch oldState {
        case .gentle:
            cancelTimer(&escalationTimer)
            if case .gentle = newState {} else { onDismissGentleNudge?() }
        case .flash:
            cancelTimer(&flashTimer)
        case .sharp:
            if case .sharp = newState {} else { onDismissSharpPrompt?() }
        case .grace:
            cancelTimer(&graceTimer)
        case .idle:
            break
        }
    }

    private func cancelAllTimers() {
        cancelTimer(&escalationTimer)
        cancelTimer(&flashTimer)
        cancelTimer(&graceTimer)
    }

    private func cancelTimer(_ timer: inout Timer?) {
        timer?.invalidate()
        timer = nil
    }
}
