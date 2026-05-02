import Combine
import SwiftUI
import UserNotifications

@MainActor
final class RestTimerManager: ObservableObject {
    @Published private(set) var restEndsAt: Date?
    @Published private(set) var restStartedAt: Date?
    private let tenSecondWarningSubject = PassthroughSubject<Void, Never>()
    private var warnedForCurrentRest = false

    var tenSecondWarningPublisher: AnyPublisher<Void, Never> {
        tenSecondWarningSubject.eraseToAnyPublisher()
    }

    var isResting: Bool {
        remainingSeconds > 0
    }

    var remainingSeconds: Int {
        guard let restEndsAt else { return 0 }
        return max(0, Int(restEndsAt.timeIntervalSinceNow.rounded()))
    }

    var remainingCountdownText: String {
        let remaining = remainingSeconds
        return "\(remaining / 60):\(String(format: "%02d", remaining % 60))"
    }

    var progress: Double {
        guard let restEndsAt, let restStartedAt else { return 0 }
        let duration = max(1, restEndsAt.timeIntervalSince(restStartedAt))
        return min(1, max(0, Double(remainingSeconds) / duration))
    }

    var remainingText: String {
        isResting ? remainingCountdownText : "Ready"
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func start(seconds: TimeInterval) {
        let start = Date()
        restStartedAt = start
        restEndsAt = start.addingTimeInterval(seconds)
        warnedForCurrentRest = false

        NotificationCenter.default.post(
            name: .watchRestStarted,
            object: nil,
            userInfo: ["remainingSeconds": Int(seconds.rounded())]
        )

        let content = UNMutableNotificationContent()
        content.title = "Rest Complete"
        content.body = "Next set is ready."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "rest-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func add(seconds: TimeInterval) {
        guard let restEndsAt else { return }
        self.restEndsAt = max(Date(), restEndsAt.addingTimeInterval(seconds))
        if remainingSeconds > 10 {
            warnedForCurrentRest = false
        }
    }

    func notifyIfNeeded(remaining: Int) {
        guard remaining == 10, !warnedForCurrentRest else { return }
        warnedForCurrentRest = true
        tenSecondWarningSubject.send()
    }

    func clear() {
        restEndsAt = nil
        restStartedAt = nil
        warnedForCurrentRest = false
    }
}

extension Notification.Name {
    static let watchRestStarted = Notification.Name("watchRestStarted")
}
