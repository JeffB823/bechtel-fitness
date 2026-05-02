import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published private(set) var isReachable = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendCurrentSet(
        workoutName: String,
        exerciseName: String,
        setProgress: String,
        weight: Double,
        reps: Int,
        restEndsAt: Date?
    ) {
        guard WCSession.isSupported() else { return }
        let payload = WatchCurrentSetState(
            isWorkoutActive: true,
            workoutName: workoutName,
            exerciseName: exerciseName,
            setProgress: setProgress,
            weight: weight,
            reps: reps,
            restEndsAt: restEndsAt,
            updatedAt: .now
        ).payload
        sendPayload(payload)
    }

    func sendWorkoutEnded() {
        guard WCSession.isSupported() else { return }
        sendPayload(WatchCurrentSetState.inactive.payload)
    }

    func requestLogSet() {
        guard WCSession.isSupported() else { return }
        WCSession.default.sendMessage(WatchBridgePayload.action(.logSet), replyHandler: nil)
    }

    private func sendPayload(_ payload: [String: Any]) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil)
        }
        try? WCSession.default.updateApplicationContext(payload)
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            switch WatchBridgePayload.messageType(from: message) {
            case .logSet:
                NotificationCenter.default.post(name: .watchLogSetRequested, object: nil)
            case .skipSet:
                NotificationCenter.default.post(name: .watchSkipSetRequested, object: nil)
            case .requestState:
                NotificationCenter.default.post(name: .watchStateSyncRequested, object: nil)
            default:
                break
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

extension Notification.Name {
    static let watchLogSetRequested = Notification.Name("watchLogSetRequested")
    static let watchSkipSetRequested = Notification.Name("watchSkipSetRequested")
    static let watchStateSyncRequested = Notification.Name("watchStateSyncRequested")
}
