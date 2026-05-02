import Foundation
import SwiftData

enum ExerciseProgressionKind: String, Codable, CaseIterable {
    case upperBody
    case lowerBody
    case custom

    var label: String {
        switch self {
        case .upperBody:
            return "Upper +5 lb"
        case .lowerBody:
            return "Lower +10 lb"
        case .custom:
            return "Custom"
        }
    }

    var defaultIncrement: Double {
        switch self {
        case .upperBody:
            return 5
        case .lowerBody:
            return 10
        case .custom:
            return 5
        }
    }
}

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var progressionKindRawValue: String
    var progressionIncrement: Double

    init(id: UUID = UUID(), name: String, progressionKind: ExerciseProgressionKind, progressionIncrement: Double? = nil) {
        self.id = id
        self.name = name
        self.progressionKindRawValue = progressionKind.rawValue
        self.progressionIncrement = progressionIncrement ?? progressionKind.defaultIncrement
    }

    var progressionKind: ExerciseProgressionKind {
        get { ExerciseProgressionKind(rawValue: progressionKindRawValue) ?? .upperBody }
        set {
            progressionKindRawValue = newValue.rawValue
            progressionIncrement = newValue.defaultIncrement
        }
    }
}

@Model
final class WorkoutSetRecord {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var targetReps: Int
    var targetWeight: Double
    var targetRPE: Double?
    var actualReps: Int?
    var actualWeight: Double?
    var actualRPE: Double?
    var isWarmup: Bool
    var isSkipped: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        targetReps: Int,
        targetWeight: Double,
        targetRPE: Double? = nil,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        actualRPE: Double? = nil,
        isWarmup: Bool = false,
        isSkipped: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetRPE = targetRPE
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.actualRPE = actualRPE
        self.isWarmup = isWarmup
        self.isSkipped = isSkipped
        self.completedAt = completedAt
    }

    var displayWeight: Double {
        actualWeight ?? targetWeight
    }

    var displayReps: Int {
        actualReps ?? targetReps
    }

    var isCompleted: Bool {
        completedAt != nil && !isSkipped
    }

    var hitTarget: Bool {
        guard !isWarmup, !isSkipped, let actualReps else { return false }
        let actualWeight = actualWeight ?? targetWeight
        return actualReps >= targetReps && actualWeight >= targetWeight
    }

    var volume: Double {
        guard !isWarmup, !isSkipped else { return 0 }
        return Double(actualReps ?? 0) * (actualWeight ?? targetWeight)
    }
}

@Model
final class SessionExercise {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var exercise: Exercise?
    var exerciseNameSnapshot: String
    var notes: String
    @Relationship(deleteRule: .cascade) var sets: [WorkoutSetRecord]

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        exercise: Exercise?,
        exerciseNameSnapshot: String,
        notes: String = "",
        sets: [WorkoutSetRecord] = []
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exercise = exercise
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.notes = notes
        self.sets = sets
    }

    var orderedSets: [WorkoutSetRecord] {
        sets.sorted { $0.orderIndex < $1.orderIndex }
    }

    var workingSets: [WorkoutSetRecord] {
        orderedSets.filter { !$0.isWarmup }
    }

    var completedWorkingSets: [WorkoutSetRecord] {
        workingSets.filter(\.isCompleted)
    }

    var allWorkingSetsHitTarget: Bool {
        let workingSets = workingSets
        return !workingSets.isEmpty && workingSets.allSatisfy(\.hitTarget)
    }

    var lastSummaryCandidate: String? {
        let completed = completedWorkingSets
        guard let first = completed.first else { return nil }
        let sameReps = completed.allSatisfy { $0.displayReps == first.displayReps }
        let sameWeight = completed.allSatisfy { abs($0.displayWeight - first.displayWeight) < 0.01 }

        if sameReps && sameWeight {
            return "\(completed.count)x\(first.displayReps) @ \(first.displayWeight.cleanPounds)"
        }

        let parts = completed.map { "\($0.displayReps) @ \($0.displayWeight.cleanPounds)" }
        return parts.joined(separator: ", ")
    }

    var volume: Double {
        orderedSets.reduce(0) { $0 + $1.volume }
    }
}

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var name: String
    var templateName: String?
    var startedAt: Date
    var endedAt: Date?
    var healthKitExportedAt: Date?
    @Relationship(deleteRule: .cascade) var exercises: [SessionExercise]

    init(
        id: UUID = UUID(),
        name: String,
        templateName: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        exercises: [SessionExercise] = []
    ) {
        self.id = id
        self.name = name
        self.templateName = templateName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
    }

    var orderedExercises: [SessionExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var totalVolume: Double {
        orderedExercises.reduce(0) { $0 + $1.volume }
    }

    var completedSetCount: Int {
        orderedExercises.flatMap(\.orderedSets).filter(\.isCompleted).count
    }

    var totalSetCount: Int {
        orderedExercises.flatMap(\.orderedSets).count
    }

    var isFinished: Bool {
        endedAt != nil
    }
}

@Model
final class ExerciseTemplate {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var exercise: Exercise?
    var exerciseNameSnapshot: String
    var targetSetCount: Int
    var targetReps: Int
    var targetWeight: Double
    var targetRPE: Double?
    var notes: String

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        exercise: Exercise?,
        exerciseNameSnapshot: String,
        targetSetCount: Int,
        targetReps: Int,
        targetWeight: Double,
        targetRPE: Double? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exercise = exercise
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.targetSetCount = targetSetCount
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetRPE = targetRPE
        self.notes = notes
    }
}

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var subtitle: String
    @Relationship(deleteRule: .cascade) var exercises: [ExerciseTemplate]

    init(id: UUID = UUID(), name: String, subtitle: String = "", exercises: [ExerciseTemplate] = []) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.exercises = exercises
    }

    var orderedExercises: [ExerciseTemplate] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }
}

@Model
final class ExerciseHistory {
    @Attribute(.unique) var exerciseID: UUID
    var exerciseName: String
    var lastSummary: String
    var lastCompletedAt: Date
    var lastWorkingSetWeight: Double
    var lastWorkingSetReps: Int
    var allWorkingSetsHitTarget: Bool
    var suggestedNextWeight: Double
    var progressionIncrement: Double

    init(
        exerciseID: UUID,
        exerciseName: String,
        lastSummary: String,
        lastCompletedAt: Date,
        lastWorkingSetWeight: Double,
        lastWorkingSetReps: Int,
        allWorkingSetsHitTarget: Bool,
        suggestedNextWeight: Double,
        progressionIncrement: Double
    ) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.lastSummary = lastSummary
        self.lastCompletedAt = lastCompletedAt
        self.lastWorkingSetWeight = lastWorkingSetWeight
        self.lastWorkingSetReps = lastWorkingSetReps
        self.allWorkingSetsHitTarget = allWorkingSetsHitTarget
        self.suggestedNextWeight = suggestedNextWeight
        self.progressionIncrement = progressionIncrement
    }
}

extension Double {
    var cleanPounds: String {
        rounded() == self ? "\(Int(self))" : String(format: "%.1f", self)
    }
}
