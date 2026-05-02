import Foundation
import SwiftData

@MainActor
struct WorkoutRepository {
    let context: ModelContext

    func seedIfNeeded() {
        let descriptor = FetchDescriptor<WorkoutTemplate>()
        guard (try? context.fetch(descriptor).isEmpty) == true else { return }

        let exerciseSpecs: [(String, ExerciseProgressionKind)] = [
            ("Back Squat", .lowerBody),
            ("Bench Press", .upperBody),
            ("Cable Row", .upperBody),
            ("Cable Lat Pulldown", .upperBody),
            ("Romanian Deadlift", .lowerBody),
            ("Cable Curl", .upperBody),
            ("Triceps Pressdown", .upperBody),
            ("Split Squat", .lowerBody),
            ("Cable Face Pull", .upperBody)
        ]

        let exercises = exerciseSpecs.map { Exercise(name: $0.0, progressionKind: $0.1) }
        exercises.forEach(context.insert)

        func exercise(_ name: String) -> Exercise {
            exercises.first { $0.name == name }!
        }

        let strengthA = WorkoutTemplate(name: "Strength A", subtitle: "Squat, press, row")
        strengthA.exercises = [
            ExerciseTemplate(orderIndex: 0, exercise: exercise("Back Squat"), exerciseNameSnapshot: "Back Squat", targetSetCount: 3, targetReps: 5, targetWeight: 135, targetRPE: 8, notes: "Add 10 lb next time if all 3 working sets hit 5 reps."),
            ExerciseTemplate(orderIndex: 1, exercise: exercise("Bench Press"), exerciseNameSnapshot: "Bench Press", targetSetCount: 3, targetReps: 5, targetWeight: 95, targetRPE: 8, notes: "Keep shoulder blades pinned. Add 5 lb after a clean session."),
            ExerciseTemplate(orderIndex: 2, exercise: exercise("Cable Row"), exerciseNameSnapshot: "Cable Row", targetSetCount: 3, targetReps: 10, targetWeight: 80, targetRPE: 8, notes: "Pause hard at the ribs; substitute close-grip cable row as needed.")
        ]

        let strengthB = WorkoutTemplate(name: "Strength B", subtitle: "Hinge, pull, accessories")
        strengthB.exercises = [
            ExerciseTemplate(orderIndex: 0, exercise: exercise("Romanian Deadlift"), exerciseNameSnapshot: "Romanian Deadlift", targetSetCount: 3, targetReps: 8, targetWeight: 115, targetRPE: 8, notes: "Control the eccentric and stop when hamstrings are loaded."),
            ExerciseTemplate(orderIndex: 1, exercise: exercise("Cable Lat Pulldown"), exerciseNameSnapshot: "Cable Lat Pulldown", targetSetCount: 3, targetReps: 10, targetWeight: 80, targetRPE: 8, notes: "Use your pulldown bar attachment. Chest tall, elbows down."),
            ExerciseTemplate(orderIndex: 2, exercise: exercise("Triceps Pressdown"), exerciseNameSnapshot: "Triceps Pressdown", targetSetCount: 3, targetReps: 12, targetWeight: 45, targetRPE: 8, notes: "Keep elbows tucked; swap bar/rope attachment freely.")
        ]

        let accessory = WorkoutTemplate(name: "Accessory Pump", subtitle: "Joint-friendly cable work")
        accessory.exercises = [
            ExerciseTemplate(orderIndex: 0, exercise: exercise("Split Squat"), exerciseNameSnapshot: "Split Squat", targetSetCount: 3, targetReps: 8, targetWeight: 40, targetRPE: 8, notes: "Use dumbbells if available or bodyweight tempo if legs are cooked."),
            ExerciseTemplate(orderIndex: 1, exercise: exercise("Cable Face Pull"), exerciseNameSnapshot: "Cable Face Pull", targetSetCount: 3, targetReps: 15, targetWeight: 35, targetRPE: 7, notes: "High pulley, pull toward forehead, rotate thumbs back."),
            ExerciseTemplate(orderIndex: 2, exercise: exercise("Cable Curl"), exerciseNameSnapshot: "Cable Curl", targetSetCount: 3, targetReps: 12, targetWeight: 35, targetRPE: 8, notes: "Use bar attachment. Full stretch and clean squeeze.")
        ]

        [strengthA, strengthB, accessory].forEach(context.insert)
        try? context.save()
    }

    func startWorkout(from template: WorkoutTemplate) -> WorkoutSession {
        let session = WorkoutSession(name: template.name, templateName: template.name)
        session.exercises = template.orderedExercises.map { exerciseTemplate in
            let exercise = exerciseTemplate.exercise
            let suggestedWeight = suggestedWeight(for: exercise, fallback: exerciseTemplate.targetWeight)
            let sets = (0..<exerciseTemplate.targetSetCount).map {
                WorkoutSetRecord(
                    orderIndex: $0,
                    targetReps: exerciseTemplate.targetReps,
                    targetWeight: suggestedWeight,
                    targetRPE: exerciseTemplate.targetRPE
                )
            }

            return SessionExercise(
                orderIndex: exerciseTemplate.orderIndex,
                exercise: exercise,
                exerciseNameSnapshot: exercise?.name ?? exerciseTemplate.exerciseNameSnapshot,
                notes: exerciseTemplate.notes,
                sets: sets
            )
        }

        context.insert(session)
        try? context.save()
        return session
    }

    func duplicateMostRecentSession(named name: String) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.name == name && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let previous = try? context.fetch(descriptor).first else { return nil }
        let session = WorkoutSession(name: previous.name, templateName: previous.templateName)
        session.exercises = previous.orderedExercises.map { previousExercise in
            let exercise = previousExercise.exercise
            let suggestedWeight = suggestedWeight(for: exercise, fallback: previousExercise.workingSets.first?.displayWeight ?? 0)
            let sets = previousExercise.orderedSets.map {
                WorkoutSetRecord(
                    orderIndex: $0.orderIndex,
                    targetReps: $0.targetReps,
                    targetWeight: $0.isWarmup ? $0.targetWeight : suggestedWeight,
                    targetRPE: $0.targetRPE,
                    isWarmup: $0.isWarmup
                )
            }

            return SessionExercise(
                orderIndex: previousExercise.orderIndex,
                exercise: exercise,
                exerciseNameSnapshot: previousExercise.exerciseNameSnapshot,
                notes: previousExercise.notes,
                sets: sets
            )
        }

        context.insert(session)
        try? context.save()
        return session
    }

    func finish(_ session: WorkoutSession) {
        session.endedAt = Date()
        updateExerciseHistory(from: session)
        try? context.save()
    }

    func addSet(to exercise: SessionExercise) {
        let previous = exercise.orderedSets.last
        let nextSet = WorkoutSetRecord(
            orderIndex: (previous?.orderIndex ?? -1) + 1,
            targetReps: previous?.targetReps ?? 0,
            targetWeight: previous?.targetWeight ?? 0,
            targetRPE: previous?.targetRPE,
            isWarmup: previous?.isWarmup ?? false
        )
        exercise.sets.append(nextSet)
        try? context.save()
    }

    func lastSummary(for exercise: Exercise?) -> String? {
        guard let exercise, let history = history(for: exercise.id) else { return nil }
        return "Last: \(history.lastSummary)"
    }

    func suggestedWeight(for exercise: Exercise?, fallback: Double) -> Double {
        guard let exercise, let history = history(for: exercise.id) else { return fallback }
        return history.allWorkingSetsHitTarget ? history.suggestedNextWeight : history.lastWorkingSetWeight
    }

    private func history(for exerciseID: UUID) -> ExerciseHistory? {
        var descriptor = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.exerciseID == exerciseID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func updateExerciseHistory(from session: WorkoutSession) {
        for sessionExercise in session.orderedExercises {
            guard let exercise = sessionExercise.exercise,
                  let summary = sessionExercise.lastSummaryCandidate,
                  let topSet = sessionExercise.completedWorkingSets.last
            else { continue }

            let increment = exercise.progressionIncrement
            let hitTargets = sessionExercise.allWorkingSetsHitTarget
            let nextWeight = hitTargets ? topSet.displayWeight + increment : topSet.displayWeight

            if let existing = history(for: exercise.id) {
                existing.exerciseName = exercise.name
                existing.lastSummary = summary
                existing.lastCompletedAt = session.endedAt ?? Date()
                existing.lastWorkingSetWeight = topSet.displayWeight
                existing.lastWorkingSetReps = topSet.displayReps
                existing.allWorkingSetsHitTarget = hitTargets
                existing.suggestedNextWeight = nextWeight
                existing.progressionIncrement = increment
            } else {
                context.insert(
                    ExerciseHistory(
                        exerciseID: exercise.id,
                        exerciseName: exercise.name,
                        lastSummary: summary,
                        lastCompletedAt: session.endedAt ?? Date(),
                        lastWorkingSetWeight: topSet.displayWeight,
                        lastWorkingSetReps: topSet.displayReps,
                        allWorkingSetsHitTarget: hitTargets,
                        suggestedNextWeight: nextWeight,
                        progressionIncrement: increment
                    )
                )
            }
        }
    }
}
