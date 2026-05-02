import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var exerciseName: String
        var setProgress: String
        var restEndsAt: Date?
    }

    var workoutName: String
}
#endif

@MainActor
final class WorkoutLiveActivityManager: ObservableObject {
    #if canImport(ActivityKit)
    private var activity: Activity<WorkoutActivityAttributes>?
    #endif

    func start(workoutName: String, exerciseName: String, setProgress: String) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = WorkoutActivityAttributes(workoutName: workoutName)
        let state = WorkoutActivityAttributes.ContentState(exerciseName: exerciseName, setProgress: setProgress, restEndsAt: nil)

        do {
            activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil), pushType: nil)
        } catch {
            activity = nil
        }
        #endif
    }

    func update(exerciseName: String, setProgress: String, restEndsAt: Date?) {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let state = WorkoutActivityAttributes.ContentState(exerciseName: exerciseName, setProgress: setProgress, restEndsAt: restEndsAt)

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        #endif
    }
}
