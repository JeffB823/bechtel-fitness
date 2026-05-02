import Foundation

enum WatchBridgeMessageType: String {
    case currentSetState
    case requestState
    case logSet
    case skipSet
    case endWorkout
}

struct WatchCurrentSetState: Equatable {
    var isWorkoutActive: Bool
    var workoutName: String
    var exerciseName: String
    var setProgress: String
    var weight: Double
    var reps: Int
    var restEndsAt: Date?
    var updatedAt: Date

    static let inactive = WatchCurrentSetState(
        isWorkoutActive: false,
        workoutName: "Workout",
        exerciseName: "No active workout",
        setProgress: "Start on iPhone",
        weight: 0,
        reps: 0,
        restEndsAt: nil,
        updatedAt: .now
    )

    var payload: [String: Any] {
        var payload: [String: Any] = [
            WatchBridgePayload.typeKey: WatchBridgeMessageType.currentSetState.rawValue,
            WatchBridgePayload.isWorkoutActiveKey: isWorkoutActive,
            WatchBridgePayload.workoutNameKey: workoutName,
            WatchBridgePayload.exerciseNameKey: exerciseName,
            WatchBridgePayload.setProgressKey: setProgress,
            WatchBridgePayload.weightKey: weight,
            WatchBridgePayload.repsKey: reps,
            WatchBridgePayload.updatedAtKey: updatedAt.timeIntervalSince1970
        ]

        if let restEndsAt {
            payload[WatchBridgePayload.restEndsAtKey] = restEndsAt.timeIntervalSince1970
        }

        return payload
    }

    init(
        isWorkoutActive: Bool,
        workoutName: String,
        exerciseName: String,
        setProgress: String,
        weight: Double,
        reps: Int,
        restEndsAt: Date?,
        updatedAt: Date
    ) {
        self.isWorkoutActive = isWorkoutActive
        self.workoutName = workoutName
        self.exerciseName = exerciseName
        self.setProgress = setProgress
        self.weight = weight
        self.reps = reps
        self.restEndsAt = restEndsAt
        self.updatedAt = updatedAt
    }

    init?(payload: [String: Any]) {
        guard WatchBridgePayload.messageType(from: payload) == .currentSetState else {
            return nil
        }

        let isWorkoutActive = payload[WatchBridgePayload.isWorkoutActiveKey] as? Bool ?? false
        let workoutName = payload[WatchBridgePayload.workoutNameKey] as? String ?? "Workout"
        let exerciseName = payload[WatchBridgePayload.exerciseNameKey] as? String ?? "No active workout"
        let setProgress = payload[WatchBridgePayload.setProgressKey] as? String ?? "Start on iPhone"
        let weight = payload[WatchBridgePayload.weightKey] as? Double ?? 0
        let reps = payload[WatchBridgePayload.repsKey] as? Int ?? 0

        let restEndsAt: Date?
        if let timestamp = payload[WatchBridgePayload.restEndsAtKey] as? Double {
            restEndsAt = Date(timeIntervalSince1970: timestamp)
        } else {
            restEndsAt = nil
        }

        let updatedAt: Date
        if let timestamp = payload[WatchBridgePayload.updatedAtKey] as? Double {
            updatedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            updatedAt = .now
        }

        self.init(
            isWorkoutActive: isWorkoutActive,
            workoutName: workoutName,
            exerciseName: exerciseName,
            setProgress: setProgress,
            weight: weight,
            reps: reps,
            restEndsAt: restEndsAt,
            updatedAt: updatedAt
        )
    }
}

enum WatchBridgePayload {
    static let typeKey = "type"
    static let isWorkoutActiveKey = "isWorkoutActive"
    static let workoutNameKey = "workoutName"
    static let exerciseNameKey = "exerciseName"
    static let setProgressKey = "setProgress"
    static let weightKey = "weight"
    static let repsKey = "reps"
    static let restEndsAtKey = "restEndsAt"
    static let updatedAtKey = "updatedAt"

    static func messageType(from payload: [String: Any]) -> WatchBridgeMessageType? {
        guard let rawValue = payload[typeKey] as? String else {
            return nil
        }
        return WatchBridgeMessageType(rawValue: rawValue)
    }

    static func action(_ type: WatchBridgeMessageType) -> [String: Any] {
        [typeKey: type.rawValue]
    }
}
