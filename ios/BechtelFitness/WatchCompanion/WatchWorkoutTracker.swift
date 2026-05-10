import Foundation
import WatchConnectivity

@MainActor
final class WatchWorkoutTracker: NSObject, ObservableObject {
    @Published private(set) var currentState: WatchCurrentSetState = .inactive
    @Published private(set) var isReachable = false

    override init() {
        super.init()
        activate()
    }

    var workoutName: String {
        currentState.workoutName
    }

    var exerciseName: String {
        currentState.exerciseName
    }

    var setProgress: String {
        currentState.setProgress
    }

    var weightText: String {
        currentState.weight > 0 ? "\(Int(currentState.weight)) lb" : "--"
    }

    var repsText: String {
        currentState.reps > 0 ? "\(currentState.reps)" : "--"
    }

    var isWorkoutActive: Bool {
        currentState.isWorkoutActive
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func requestState() {
        sendAction(.requestState)
    }

    func logSet() {
        sendAction(.logSet)
    }

    func skipSet() {
        sendAction(.skipSet)
    }

    func restRemainingText(at date: Date) -> String {
        guard let restEndsAt = currentState.restEndsAt else { return "Ready" }
        let remaining = max(0, Int(restEndsAt.timeIntervalSince(date).rounded()))
        if remaining == 0 {
            return "Ready"
        }
        return "\(remaining / 60):\(String(format: "%02d", remaining % 60))"
    }

    private func sendAction(_ type: WatchBridgeMessageType) {
        guard WCSession.isSupported() else { return }
        let payload = WatchBridgePayload.action(type)

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil)
        }
    }

    private func applyPayload(_ payload: [String: Any]) {
        guard let state = WatchCurrentSetState(payload: payload) else { return }
        currentState = state
    }
}

extension WatchWorkoutTracker: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            isReachable = session.isReachable
            requestState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            if session.isReachable {
                requestState()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            applyPayload(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            applyPayload(applicationContext)
        }
    }
}
