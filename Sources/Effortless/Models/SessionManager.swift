import Foundation
import Combine

extension Notification.Name {
    static let sessionStateChanged = Notification.Name("sessionStateChanged")
}

@MainActor
class SessionManager: ObservableObject {
    enum State {
        case idle
        case active(Session)
    }

    @Published var state: State = .idle
    @Published var remainingTimeFormatted: String = ""

    private var timer: Timer?
    private let logger = SessionLogger()

    var currentSession: Session? {
        if case .active(let session) = state { return session }
        return nil
    }

    func begin(intention: String, minutes: Int) {
        let session = Session(
            id: UUID(),
            intention: intention,
            timeboxMinutes: minutes,
            startedAt: Date()
        )
        state = .active(session)
        startTimer()
        notifyChange()
    }

    func complete() {
        guard case .active(var session) = state else { return }
        session.endedAt = Date()
        session.outcome = .completed
        logger.log(session)
        stopTimer()
        state = .idle
        notifyChange()
    }

    func interrupt() {
        guard case .active(var session) = state else { return }
        session.endedAt = Date()
        session.outcome = .interrupted
        logger.log(session)
        stopTimer()
        state = .idle
        notifyChange()
    }

    private func expire() {
        guard case .active(var session) = state else { return }
        session.endedAt = Date()
        session.outcome = .expired
        logger.log(session)
        stopTimer()
        state = .idle
        notifyChange()
    }

    private func startTimer() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        remainingTimeFormatted = ""
    }

    private func tick() {
        guard case .active(let session) = state else { return }

        if session.isExpired {
            expire()
            return
        }

        let remaining = Int(session.remainingSeconds)
        let minutes = remaining / 60
        let seconds = remaining % 60
        remainingTimeFormatted = String(format: "%d:%02d", minutes, seconds)
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .sessionStateChanged, object: nil)
    }
}
