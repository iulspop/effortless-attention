import AppKit
import Foundation

/// Orchestrates the nudge escalation: gentle → flash → sharp.
/// Driven by AttentionMonitor events and OllamaClient judgments.
@MainActor
class NudgeManager: ObservableObject {

    enum NudgeState: Equatable {
        case idle
        case gentle(app: String, windowTitle: String)  // showing gentle nudge
        case flash                                       // 5-second flash warning
        case sharp                                       // fullscreen stop/interrupt prompt
        case grace                                       // user picked "Stop", brief grace period
    }

    @Published private(set) var state: NudgeState = .idle

    var onGentleNudge: ((String, String) -> Void)?    // (app, intention)
    var onDismissGentleNudge: (() -> Void)?
    var onFlash: (() -> Void)?
    var onSharpPrompt: (() -> Void)?
    var onDismissSharpPrompt: (() -> Void)?

    private let attentionMonitor = AttentionMonitor()
    private let appearanceManager: AppearanceManager
    private let allowlistStore: AllowlistStore
    private var ollamaClient: OllamaClient

    /// Provides current intention for LLM queries.
    var intentionProvider: (() -> (intention: String, contextLabel: String, contextId: UUID)?)?

    /// Track last-known intention so we can detect when it changes.
    private var lastKnownIntention: String?

    private var escalationTimer: Timer?
    private var flashTimer: Timer?
    private var graceTimer: Timer?
    private var pendingAssessment: Task<Void, Never>?

    /// The last context the LLM judged as distracting — used to avoid re-querying.
    private var lastDistractingContext: AttentionMonitor.AppContext?

    init(appearanceManager: AppearanceManager = .shared,
         allowlistStore: AllowlistStore = AllowlistStore()) {
        self.appearanceManager = appearanceManager
        self.allowlistStore = allowlistStore
        self.ollamaClient = OllamaClient(model: appearanceManager.ollamaModel)
    }

    private var isRunning = false

    func start() {
        
        guard appearanceManager.nudgeEnabled else { return }
        guard !isRunning else { return }  // Already running — don't stack monitors
        isRunning = true

        let configuredModel = appearanceManager.ollamaModel
        if configuredModel.isEmpty || configuredModel == "auto" {
            // Auto-detect: pick the first (smallest) available model
            Task {
                let models = await OllamaClient.availableModels()
                guard let first = models.first else {
                    isRunning = false
                    return
                }
                self.ollamaClient = OllamaClient(model: first)
                self.beginMonitoring()
            }
        } else {
            ollamaClient = OllamaClient(model: configuredModel)
            beginMonitoring()
        }
    }

    private func beginMonitoring() {
        lastKnownIntention = intentionProvider?()?.intention
        attentionMonitor.onChange = { [weak self] ctx in
            self?.handleContextChange(ctx)
        }
        attentionMonitor.start()
    }

    func stop() {
        attentionMonitor.stop()
        cancelAllTimers()
        pendingAssessment?.cancel()
        pendingAssessment = nil
        transitionTo(.idle)
        isRunning = false
    }

    /// Called when session state changes. Resets nudge state if the intention changed.
    func intentionDidChange() {
        guard isRunning else { return }
        let currentIntention = intentionProvider?()?.intention
        if currentIntention != lastKnownIntention {
            lastKnownIntention = currentIntention
            // Intention changed — old nudge/assessment is stale
            pendingAssessment?.cancel()
            pendingAssessment = nil
            lastDistractingContext = nil
            cancelAllTimers()
            if state != .idle {
                transitionTo(.idle)
            }
            // Re-assess current app against new intention
            checkCurrentContext()
        }
    }

    // MARK: - User Actions

    /// User dismissed gentle nudge with "not distracted".
    /// Adds context to LLM prompt history (not a hard bypass) so the LLM can learn.
    func userMarkedNotDistracted() {
        guard case .gentle(let app, let windowTitle) = state else { return }
        // Save as LLM prompt context — not a hard bypass
        if let info = intentionProvider?() {
            let entry = "\(app) - \(windowTitle)"
            allowlistStore.add(entry, forContextId: info.contextId)
        }
        lastDistractingContext = nil
        transitionTo(.idle)
        // Reset so next poll re-fires even if user stays on same app
        attentionMonitor.resetLastContext()
    }

    /// User picked "Stop" on sharp prompt — return to intention with grace period.
    func userPickedStop() {
        transitionTo(.grace)
        graceTimer = Timer.scheduledTimer(withTimeInterval: Double(appearanceManager.gracePeriodAfterStop), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.graceTimer = nil
                // Re-check after grace period
                self?.checkCurrentContext()
            }
        }
    }

    /// User picked "Log Interruption" on sharp prompt — delegate handles escape hatch.
    func userPickedInterrupt() {
        lastDistractingContext = nil
        transitionTo(.idle)
    }

    // MARK: - Context Change Handling

    private func handleContextChange(_ ctx: AttentionMonitor.AppContext) {
        // Hard lock during flash/sharp/grace — user must interact with the prompt
        switch state {
        case .flash, .sharp, .grace:
            return
        case .gentle:
            // During gentle nudge, re-assess — if user went back on-task, dismiss
            pendingAssessment?.cancel()
            reassessDuringGentle(ctx)
            return
        default: break
        }

        // Cancel any pending LLM assessment
        pendingAssessment?.cancel()

        // If user returned to a non-distracting app, reset
        if ctx == lastDistractingContext {
            return
        }

        // Always ask LLM — allowlist entries are just prompt context, not hard bypass
        assessDistraction(ctx)
    }

    private func checkCurrentContext() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = app.bundleIdentifier
        let ownBundleId = Bundle.main.bundleIdentifier ?? "com.iulspop.effortless"
        if bundleId == ownBundleId { return }

        let appName = app.localizedName ?? "Unknown"
        let windowTitle = AttentionMonitor.windowTitle(for: app) ?? ""
        let ctx = AttentionMonitor.AppContext(appName: appName, windowTitle: windowTitle, bundleId: bundleId)
        handleContextChange(ctx)
    }

    /// During gentle nudge, check if user switched to an on-task app. If so, dismiss nudge.
    private func reassessDuringGentle(_ ctx: AttentionMonitor.AppContext) {
        guard let info = intentionProvider?() else { return }


        let query = OllamaClient.DistractionQuery(
            intention: info.intention,
            contextLabel: info.contextLabel,
            activeApp: ctx.appName,
            windowTitle: ctx.windowTitle,
            allowedItems: allowlistStore.entries(forContextId: info.contextId)
        )

        pendingAssessment = Task {
            guard let result = await ollamaClient.assess(query) else { return }
            guard !Task.isCancelled else { return }


            if !result.isDistracted {
                // User went back on-task — dismiss gentle nudge
                lastDistractingContext = nil
                transitionTo(.idle)
            }
            // If still distracted, do nothing — escalation timer keeps running
        }
    }

    private func assessDistraction(_ ctx: AttentionMonitor.AppContext) {
        guard let info = intentionProvider?() else {
            return
        }


        let query = OllamaClient.DistractionQuery(
            intention: info.intention,
            contextLabel: info.contextLabel,
            activeApp: ctx.appName,
            windowTitle: ctx.windowTitle,
            allowedItems: allowlistStore.entries(forContextId: info.contextId)
        )

        pendingAssessment = Task {
            guard let result = await ollamaClient.assess(query) else {
                return
            }
            guard !Task.isCancelled else {
                return
            }


            if result.isDistracted {
                lastDistractingContext = ctx
                beginGentleNudge(app: ctx.appName, windowTitle: ctx.windowTitle)
            } else {
                // LLM says not distracted — clear tracking so future changes are assessed
                lastDistractingContext = nil
                if state != .idle {
                    transitionTo(.idle)
                }
            }
        }
    }

    // MARK: - Escalation States

    private func beginGentleNudge(app: String, windowTitle: String) {
        guard let info = intentionProvider?() else { return }
        transitionTo(.gentle(app: app, windowTitle: windowTitle))
        let displayName = windowTitle.isEmpty ? app : windowTitle
        onGentleNudge?(displayName, info.intention)

        // Start escalation timer
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

        // Clean up old state
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
