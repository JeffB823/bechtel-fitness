import SwiftData
import SwiftUI

struct LiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var session: WorkoutSession

    @StateObject private var restTimer = RestTimerManager()
    @StateObject private var liveActivity = WorkoutLiveActivityManager()
    @StateObject private var healthKit = HealthKitManager()
    @State private var exerciseIndex = 0
    @State private var setIndex = 0
    @State private var actualWeight = 0.0
    @State private var actualReps = 0
    @State private var actualRPE = 8.0
    @State private var editingField: LiveWorkoutEditingField?
    @State private var editingValue = ""

    private enum LiveWorkoutEditingField: String, Identifiable {
        case weight
        case reps
        case rpe

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weight: "Edit Weight"
            case .reps: "Edit Reps"
            case .rpe: "Edit RPE"
            }
        }
    }

    private var repository: WorkoutRepository {
        WorkoutRepository(context: modelContext)
    }

    private var currentExercise: SessionExercise? {
        guard session.orderedExercises.indices.contains(exerciseIndex) else { return nil }
        return session.orderedExercises[exerciseIndex]
    }

    private var currentSet: WorkoutSetRecord? {
        guard let currentExercise, currentExercise.orderedSets.indices.contains(setIndex) else { return nil }
        return currentExercise.orderedSets[setIndex]
    }

    private var setProgress: String {
        guard let currentExercise else { return "Complete" }
        return "Set \(setIndex + 1) of \(currentExercise.orderedSets.count)"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [AppTheme.navy, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.l) {
                header

                Spacer(minLength: AppTheme.Spacing.s)

                if let currentExercise, let currentSet {
                    currentSetPanel(exercise: currentExercise, set: currentSet)
                } else {
                    completePanel
                }

                Spacer(minLength: AppTheme.Spacing.s)
            }
            .padding(AppTheme.Spacing.xl)
        }
        .foregroundStyle(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
        }
        .task {
            restTimer.requestPermission()
            WatchConnectivityManager.shared.activate()
            syncInputs()
            if let currentExercise {
                liveActivity.start(workoutName: session.name, exerciseName: currentExercise.exerciseNameSnapshot, setProgress: setProgress)
            }
        }
        .onChange(of: exerciseIndex) { _, _ in syncInputs() }
        .onChange(of: setIndex) { _, _ in syncInputs() }
        .onReceive(NotificationCenter.default.publisher(for: .watchLogSetRequested)) { _ in
            logCurrentSet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchSkipSetRequested)) { _ in
            skipCurrentSet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchStateSyncRequested)) { _ in
            syncWatchState()
        }
        .onReceive(restTimer.tenSecondWarningPublisher) { _ in
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        .alert(editingField?.title ?? "Edit", isPresented: editingBinding) {
            TextField("Value", text: $editingValue)
                .keyboardType(.decimalPad)
            Button("Save") {
                saveEditedInput()
            }
            Button("Cancel", role: .cancel) {
                editingField = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.height < -60 {
                        logCurrentSet()
                    } else if value.translation.width < -60 {
                        skipCurrentSet()
                    }
                }
        )
    }

    private var header: some View {
        HStack {
            Button {
                WatchConnectivityManager.shared.sendWorkoutEnded()
                liveActivity.end()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                    .background(.white.opacity(0.12), in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(session.name)
                    .font(.headline)
                Text("\(session.completedSetCount)/\(session.totalSetCount) sets")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Text(setProgress)
                .font(.caption.weight(.heavy))
                .foregroundStyle(AppTheme.softGold)
                .lineLimit(1)

            Button {
                finishWorkout()
            } label: {
                Text("Finish")
                    .font(.subheadline.weight(.bold))
                    .frame(height: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("Finish workout")
            .accessibilityHint("Saves and exports the completed workout.")
        }
    }

    private func currentSetPanel(exercise: SessionExercise, set: WorkoutSetRecord) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(exercise.exerciseNameSnapshot)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)

                if let last = repository.lastSummary(for: exercise.exercise) {
                    Text(last.replacingOccurrences(of: "Last: ", with: "Last time: "))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.TextOnDark.small)
                        .lineLimit(2)
                }
            }

            RestTimerRing(restTimer: restTimer)
                .transition(accessibilityReduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))

            VStack(spacing: AppTheme.Spacing.m) {
                bumperInput(
                    title: "Weight",
                    value: "\(actualWeight.cleanPounds)",
                    suffix: "lb",
                    decrementLabel: "-5",
                    incrementLabel: "+5",
                    decrement: { updateWeight(by: -5) },
                    increment: { updateWeight(by: 5) },
                    edit: { beginEditing(.weight, value: actualWeight.cleanPounds) }
                )

                bumperInput(
                    title: "Reps",
                    value: "\(actualReps)",
                    suffix: "target \(set.targetReps)",
                    decrementLabel: "-1",
                    incrementLabel: "+1",
                    decrement: { updateReps(by: -1) },
                    increment: { updateReps(by: 1) },
                    edit: { beginEditing(.reps, value: "\(actualReps)") }
                )

                bumperInput(
                    title: "RPE",
                    value: actualRPE.cleanPounds,
                    suffix: "effort",
                    decrementLabel: "-0.5",
                    incrementLabel: "+0.5",
                    decrement: { updateRPE(by: -0.5) },
                    increment: { updateRPE(by: 0.5) },
                    edit: { beginEditing(.rpe, value: actualRPE.cleanPounds) }
                )
            }
            .padding(AppTheme.Spacing.l)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.Radius.row))

            if !exercise.notes.isEmpty {
                Text(exercise.notes)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.TextOnDark.small)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Text("Swipe up to log • swipe left to skip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.TextOnDark.small)
        }
    }

    private func bumperInput(
        title: String,
        value: String,
        suffix: String,
        decrementLabel: String,
        incrementLabel: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        edit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.m) {
            roundBumperButton(decrementLabel, action: decrement)

            Button(action: edit) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(AppTheme.TextOnDark.small)

                    Text(value)
                        .font(.largeTitle.weight(.black))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .monospacedDigit()

                    Text(suffix)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.TextOnDark.small)
                }
                .frame(maxWidth: .infinity, minHeight: AppTheme.Size.restPill)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(title.lowercased())")

            roundBumperButton(incrementLabel, action: increment)
        }
    }

    private func roundBumperButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.black))
                .frame(width: AppTheme.Size.compactIcon, height: AppTheme.Size.compactIcon)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(spacing: AppTheme.Spacing.s) {
            HStack(spacing: AppTheme.Spacing.s) {
                Button {
                    logCurrentSet()
                } label: {
                    Label("Log Set", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Log set")
                .accessibilityHint("Logs the current weight, reps, and RPE for this set.")

                Button {
                    skipCurrentSet()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: AppTheme.Size.secondaryActionWidth)
                .accessibilityLabel("Skip set")
                .accessibilityHint("Marks the current set as skipped and moves to the next set.")
            }

            if let currentExercise {
                Button {
                    repository.addSet(to: currentExercise)
                    syncInputs()
                } label: {
                    Text("Add Set")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.softGold)
                        .frame(minHeight: AppTheme.Size.minTouch)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.top, AppTheme.Spacing.s)
        .padding(.bottom, AppTheme.Spacing.s)
        .background(.ultraThinMaterial)
    }

    private var completePanel: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle.weight(.heavy))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(AppTheme.gold)

            Text("Workout Complete")
                .font(.largeTitle.weight(.black))

            Text("\(session.completedSetCount) sets • \(session.totalVolume.cleanPounds) lb total volume")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.74))

            Button {
                finishWorkout()
            } label: {
                Text("Save + Export")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var editingBinding: Binding<Bool> {
        Binding(
            get: { editingField != nil },
            set: { isPresented in
                if !isPresented {
                    editingField = nil
                }
            }
        )
    }

    private func beginEditing(_ field: LiveWorkoutEditingField, value: String) {
        editingValue = value
        editingField = field
    }

    private func saveEditedInput() {
        guard let editingField else { return }
        switch editingField {
        case .weight:
            actualWeight = min(max(Double(editingValue) ?? actualWeight, 0), 1000)
        case .reps:
            actualReps = min(max(Int(editingValue) ?? actualReps, 0), 100)
        case .rpe:
            actualRPE = min(max(Double(editingValue) ?? actualRPE, 1), 10)
        }
        self.editingField = nil
    }

    private func updateWeight(by delta: Double) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        actualWeight = min(max(actualWeight + delta, 0), 1000)
    }

    private func updateReps(by delta: Int) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        actualReps = min(max(actualReps + delta, 0), 100)
    }

    private func updateRPE(by delta: Double) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        actualRPE = min(max(actualRPE + delta, 1), 10)
    }

    private func syncInputs() {
        guard let currentSet, let currentExercise else {
            syncWatchState()
            return
        }
        actualWeight = currentSet.actualWeight ?? currentSet.targetWeight
        actualReps = currentSet.actualReps ?? currentSet.targetReps
        actualRPE = currentSet.actualRPE ?? currentSet.targetRPE ?? 8
        liveActivity.update(exerciseName: currentExercise.exerciseNameSnapshot, setProgress: setProgress, restEndsAt: restTimer.restEndsAt)
        syncWatchState()
    }

    private func logCurrentSet() {
        guard let currentSet else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        currentSet.actualWeight = actualWeight
        currentSet.actualReps = actualReps
        currentSet.actualRPE = actualRPE
        currentSet.completedAt = Date()
        currentSet.isSkipped = false
        try? modelContext.save()
        restTimer.start(seconds: 90)
        advance()
    }

    private func skipCurrentSet() {
        guard let currentSet else { return }
        currentSet.isSkipped = true
        currentSet.completedAt = Date()
        try? modelContext.save()
        advance()
    }

    private func advance() {
        guard let currentExercise else { return }
        if setIndex + 1 < currentExercise.orderedSets.count {
            setIndex += 1
        } else {
            setIndex = 0
            exerciseIndex += 1
        }
        syncInputs()
    }

    private func finishWorkout() {
        repository.finish(session)
        WatchConnectivityManager.shared.sendWorkoutEnded()
        liveActivity.end()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            await healthKit.requestAuthorizationAndRefresh()
            try? await healthKit.exportWorkout(session)
            dismiss()
        }
    }

    private func syncWatchState() {
        guard let currentExercise, currentSet != nil else {
            WatchConnectivityManager.shared.sendWorkoutEnded()
            return
        }

        WatchConnectivityManager.shared.sendCurrentSet(
            workoutName: session.name,
            exerciseName: currentExercise.exerciseNameSnapshot,
            setProgress: setProgress,
            weight: actualWeight,
            reps: actualReps,
            restEndsAt: restTimer.restEndsAt
        )
    }
}
