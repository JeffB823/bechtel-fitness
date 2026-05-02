import SwiftUI
import Charts

struct WorkoutEngineSnapshot: Codable, Equatable {
    var screen: String?
    var settings: WorkoutEngineSettings
    var logs: [String: [WorkoutLoggedSession]]
    var phases: [WorkoutPhase]
    var crossfitWeek: CrossfitWeek?
    var crossfitLogs: [String: CrossfitDayLog]?

    var currentPhase: WorkoutPhase? {
        phases.first(where: { $0.id == settings.currentPhase }) ?? phases.first
    }

    var currentDay: WorkoutDay? {
        guard let phase = currentPhase else { return nil }
        if phase.days.indices.contains(settings.currentDayIndex) {
            return phase.days[settings.currentDayIndex]
        }
        return phase.days.first
    }

    var sessions: [FlattenedWorkoutSession] {
        logs.flatMap { date, values in
            values.enumerated().map { index, value in
                FlattenedWorkoutSession(date: date, sessionIndex: index, session: value)
            }
        }
        .sorted { lhs, rhs in
            let left = lhs.session.completedAt ?? lhs.date
            let right = rhs.session.completedAt ?? rhs.date
            if left != right { return left > right }
            return lhs.sessionIndex > rhs.sessionIndex
        }
    }

    var totalSessions: Int {
        sessions.count
    }

    var crossfitCompletedCount: Int {
        (crossfitWeek?.days ?? []).filter { crossfitLogs?[$0.day]?.done == true }.count
    }

    var recentSessions: [FlattenedWorkoutSession] {
        Array(sessions.prefix(10))
    }

    func weekContext(now: Date = .now) -> WorkoutWeekContext {
        let startDate = settings.startDateValue ?? now
        let elapsedDays = max(0, Calendar.current.dateComponents([.day], from: startDate.startOfDayValue, to: now.startOfDayValue).day ?? 0)
        let weekNumber = max(1, (elapsedDays / 7) + 1)
        let phaseWeek = max(1, weekNumber - ((settings.currentPhase - 1) * 9))
        return WorkoutWeekContext(
            weekNumber: weekNumber,
            phaseWeek: phaseWeek,
            progress: min(Double(min(phaseWeek, 8)) / 8.0, 1.0),
            isDeload: phaseWeek == 9
        )
    }

    func streak(now: Date = .now) -> Int {
        var streak = 0
        var day = now.startOfDayValue
        for index in 0..<60 {
            let key = dateKey(for: day)
            let count = logs[key]?.count ?? 0
            if count > 0 {
                streak += 1
            } else if index > 0 {
                break
            }
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    func weekDays(now: Date = .now) -> [WorkoutWeekdayStatus] {
        let today = now.startOfDayValue
        let startOfWeek = Calendar.current.date(byAdding: .day, value: -(Calendar.current.component(.weekday, from: today) - 1), to: today) ?? today
        let labels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

        return (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: startOfWeek) ?? today
            let key = dateKey(for: date)
            return WorkoutWeekdayStatus(
                label: labels[Calendar.current.component(.weekday, from: date) - 1],
                isToday: Calendar.current.isDate(date, inSameDayAs: today),
                isLogged: (logs[key]?.isEmpty == false)
            )
        }
    }

    func weeklyVolumes(now: Date = .now) -> [Double] {
        let today = now.startOfDayValue
        let startOfWeek = Calendar.current.date(byAdding: .day, value: -(Calendar.current.component(.weekday, from: today) - 1), to: today) ?? today

        return (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: startOfWeek) ?? today
            let key = dateKey(for: date)
            return (logs[key] ?? []).reduce(0) { partialResult, session in
                partialResult + session.totalVolume
            }
        }
    }

    func topPersonalRecords(limit: Int = 4) -> [WorkoutPersonalRecord] {
        var bestByExercise: [String: WorkoutBestSet] = [:]

        for session in sessions {
            for exercise in session.session.exercises {
                guard let best = exercise.bestSet else { continue }
                let current = bestByExercise[exercise.name]
                if current == nil || best.isBetter(than: current) {
                    bestByExercise[exercise.name] = best
                }
            }
        }

        let records = bestByExercise.map { entry in
            WorkoutPersonalRecord(name: entry.key, bestSet: entry.value)
        }

        let sorted = records.sorted { lhs, rhs in
            if lhs.bestSet.estimatedOneRepMax != rhs.bestSet.estimatedOneRepMax {
                return lhs.bestSet.estimatedOneRepMax > rhs.bestSet.estimatedOneRepMax
            }
            return lhs.bestSet.weight > rhs.bestSet.weight
        }

        return Array(sorted.prefix(limit))
    }

    var exerciseNames: [String] {
        let names = sessions.flatMap { session in
            session.session.exercises.compactMap { exercise in
                exercise.sets.isEmpty ? nil : exercise.name
            }
        }
        return Array(Set(names)).sorted()
    }

    func history(for exerciseName: String) -> [WorkoutExerciseHistoryPoint] {
        let filtered = sessions.filter { session in
            session.session.exercises.contains(where: { $0.name == exerciseName && !$0.sets.isEmpty })
        }

        let counts = Dictionary(grouping: filtered, by: \.date).mapValues(\.count)
        var seen: [String: Int] = [:]

        return filtered.reversed().compactMap { session in
            guard let exercise = session.session.exercises.first(where: { $0.name == exerciseName }),
                  let bestSet = exercise.bestSet
            else {
                return nil
            }

            seen[session.date, default: 0] += 1
            let suffixNeeded = (counts[session.date] ?? 0) > 1
            let labelBase = String(session.date.dropFirst(5))
            let label = suffixNeeded ? "\(labelBase) #\(seen[session.date] ?? 1)" : labelBase

            return WorkoutExerciseHistoryPoint(
                id: "\(session.id)-\(exerciseName)",
                date: session.date,
                label: label,
                weight: bestSet.weight,
                reps: bestSet.reps,
                estimatedOneRepMax: bestSet.estimatedOneRepMax,
                metric: bestSet.estimatedOneRepMax > 0 ? bestSet.estimatedOneRepMax : (bestSet.weight > 0 ? bestSet.weight : Double(bestSet.reps)),
                volume: bestSet.volume
            )
        }
    }

    func stats(for exerciseName: String) -> WorkoutExerciseStats? {
        let relevantBestSets = sessions.compactMap { session in
            session.session.exercises.first(where: { $0.name == exerciseName })?.bestSet
        }

        guard !relevantBestSets.isEmpty else { return nil }

        let bestWeight = relevantBestSets.map(\.weight).max() ?? 0
        let bestVolume = relevantBestSets.map(\.volume).max() ?? 0
        let bestOneRepMax = relevantBestSets.map(\.estimatedOneRepMax).max() ?? 0
        let bestSet = relevantBestSets.max(by: { !$0.isBetter(than: $1) })

        return WorkoutExerciseStats(
            bestWeight: bestWeight,
            bestVolume: bestVolume,
            bestOneRepMax: bestOneRepMax,
            bestSet: bestSet,
            sessionCount: relevantBestSets.count
        )
    }
}

struct WorkoutEngineSettings: Codable, Equatable {
    var startDate: String
    var currentPhase: Int
    var currentDayIndex: Int

    var startDateValue: Date? {
        dateFromKey(startDate)
    }
}

struct WorkoutPhase: Codable, Equatable, Identifiable {
    var id: Int
    var label: String
    var weekRange: String
    var days: [WorkoutDay]
}

struct WorkoutDay: Codable, Equatable, Identifiable {
    var dayNum: Int
    var name: String
    var muscleGroup: String?
    var exercises: [WorkoutExercise]

    var id: String {
        "\(dayNum)-\(name)"
    }

    var trainingExercises: [WorkoutExercise] {
        exercises.filter { !($0.isAbs ?? false) }
    }

    var exerciseCount: Int {
        trainingExercises.count
    }

    var workingSetCount: Int {
        trainingExercises.reduce(0) { $0 + $1.sets }
    }
}

struct WorkoutExercise: Codable, Equatable, Identifiable {
    var name: String
    var warmup: Bool?
    var sets: Int
    var repRange: String
    var isAbs: Bool?
    var optional: Bool?
    var bodyweight: Bool?

    var id: String { name }
}

struct WorkoutLoggedSession: Codable, Equatable {
    var completedAt: String?
    var sessionId: String?
    var phase: Int?
    var dayNum: Int?
    var dayName: String?
    var duration: Double?
    var volume: Double?
    var prsHit: [String]?
    var notes: String?
    var exercises: [WorkoutLoggedExercise]

    var totalVolume: Double {
        if let volume { return volume }
        return exercises.reduce(0) { partialResult, exercise in
            partialResult + exercise.sets.reduce(0) { $0 + (($1.weight ?? 0) * Double($1.reps ?? 0)) }
        }
    }
}

struct WorkoutLoggedExercise: Codable, Equatable, Identifiable {
    var name: String
    var bodyweight: Bool?
    var sets: [WorkoutLoggedSet]

    var id: String { name }

    var bestSet: WorkoutBestSet? {
        sets.compactMap { WorkoutBestSet(set: $0) }.max(by: { !$0.isBetter(than: $1) })
    }
}

struct WorkoutLoggedSet: Codable, Equatable {
    var weight: Double?
    var reps: Int?
}

struct FlattenedWorkoutSession: Identifiable, Equatable {
    let date: String
    let sessionIndex: Int
    let session: WorkoutLoggedSession

    var id: String {
        session.sessionId ?? "\(date)-\(sessionIndex)"
    }
}

struct WorkoutWeekContext: Equatable {
    let weekNumber: Int
    let phaseWeek: Int
    let progress: Double
    let isDeload: Bool
}

struct WorkoutWeekdayStatus: Identifiable, Equatable {
    let label: String
    let isToday: Bool
    let isLogged: Bool

    var id: String { label }
}

struct WorkoutBestSet: Equatable {
    let weight: Double
    let reps: Int
    let volume: Double
    let estimatedOneRepMax: Double

    init?(set: WorkoutLoggedSet) {
        let weight = set.weight ?? 0
        let reps = set.reps ?? 0
        guard weight > 0 || reps > 0 else { return nil }
        self.weight = weight
        self.reps = reps
        self.volume = weight * Double(reps)
        self.estimatedOneRepMax = weight > 0 && reps > 0 ? round(weight * (1 + (Double(reps) / 30.0))) : 0
    }

    func isBetter(than other: WorkoutBestSet?) -> Bool {
        guard let other else { return true }
        if estimatedOneRepMax != other.estimatedOneRepMax { return estimatedOneRepMax > other.estimatedOneRepMax }
        if weight != other.weight { return weight > other.weight }
        if reps != other.reps { return reps > other.reps }
        return volume > other.volume
    }

    var setLabel: String {
        if weight > 0 {
            return "\(formatWholeNumber(weight)) x \(reps)"
        }
        return "\(reps) reps"
    }

    var metricValue: String {
        if estimatedOneRepMax > 0 { return formatWholeNumber(estimatedOneRepMax) }
        if weight > 0 { return formatWholeNumber(weight) }
        return "\(reps)"
    }

    var metricLabel: String {
        if estimatedOneRepMax > 0 { return "Est. 1RM" }
        if weight > 0 { return "Top load" }
        return "Top reps"
    }
}

struct WorkoutPersonalRecord: Identifiable, Equatable {
    let name: String
    let bestSet: WorkoutBestSet

    var id: String { name }
}

struct WorkoutExerciseHistoryPoint: Identifiable, Equatable {
    let id: String
    let date: String
    let label: String
    let weight: Double
    let reps: Int
    let estimatedOneRepMax: Double
    let metric: Double
    let volume: Double
}

struct WorkoutExerciseStats: Equatable {
    let bestWeight: Double
    let bestVolume: Double
    let bestOneRepMax: Double
    let bestSet: WorkoutBestSet?
    let sessionCount: Int
}

struct CrossfitWeek: Codable, Equatable {
    var source: String
    var sourceUrl: String
    var importedAt: String
    var days: [CrossfitWorkoutDay]
}

struct CrossfitWorkoutDay: Codable, Equatable, Identifiable {
    var day: String
    var section: String
    var lines: [String]
    var notes: [String]?
    var extra: [String]?

    var id: String { day }
}

struct CrossfitDayLog: Codable, Equatable {
    var done: Bool?
    var completedOn: String?
    var score: String?
    var notes: String?
}

struct NativeWorkoutHomeView: View {
    let snapshot: WorkoutEngineSnapshot
    let isRefreshing: Bool
    let onOpenWorkout: () -> Void
    let onOpenProgram: () -> Void

    private var weekContext: WorkoutWeekContext {
        snapshot.weekContext()
    }

    private var todayWorkout: WorkoutDay? {
        snapshot.currentDay
    }

    private var weeklyVolume: Double {
        snapshot.weeklyVolumes().reduce(0, +)
    }

    private var streak: Int {
        snapshot.streak()
    }

    private var topRecords: [WorkoutPersonalRecord] {
        snapshot.topPersonalRecords()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.l) {
                quickStartCard
                todayHero
                weekStripCard
                summaryGrid

                if !topRecords.isEmpty {
                    recordsCard
                }
            }
            .padding(AppTheme.Spacing.l)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.dashboardGradient)
    }

    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Start Today's Workout")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(todayWorkout?.name ?? "Rest day")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.TextOnDark.secondary)
                    .lineLimit(2)
            }

            Button(action: onOpenWorkout) {
                Label("Start Today's Workout", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(todayWorkout == nil)
            .accessibilityLabel("Start Today's Workout")
            .accessibilityHint("Opens the live workout flow for the current programmed day.")
        }
        .padding(AppTheme.Spacing.l)
        .background(AppTheme.navy.opacity(0.92), in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                .stroke(AppTheme.gold.opacity(0.28), lineWidth: 1)
        }
    }

    private var todayHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                if let currentPhase = snapshot.currentPhase {
                    workoutChip(currentPhase.label, style: .accent)
                }
                workoutChip("Week \(min(weekContext.phaseWeek, 9))", style: .neutral)
                if weekContext.isDeload {
                    workoutChip("Deload", style: .gold)
                }

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .tint(AppTheme.softGold)
                }
            }

            if let workout = todayWorkout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's workout")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(workout.name)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Day \(workout.dayNum) · \(workout.exerciseCount) exercises · \(workout.workingSetCount) working sets")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.76))
                }

                VStack(spacing: 10) {
                    ForEach(workout.trainingExercises.prefix(4)) { exercise in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(AppTheme.softGold.opacity(0.85))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("\(exercise.sets) sets · \(exercise.repRange) reps")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button(action: onOpenWorkout) {
                        Label("Open live workout", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.gold)
                    .foregroundStyle(AppTheme.navy)

                    Button(action: onOpenProgram) {
                        Label("Program", systemImage: "calendar")
                            .font(.headline)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.85))
                }
            } else {
                Text("Waiting for your program state.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(22)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: AppTheme.navy.opacity(0.24), radius: 24, y: 14)
    }

    private var weekStripCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week")
                        .font(.headline)
                    Text(streak > 0 ? "\(streak)-day streak" : "No streak yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(weeklyVolume > 0 ? "\(formatCompactVolume(weeklyVolume)) volume" : "No sessions yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
            }

            HStack(spacing: 10) {
                ForEach(snapshot.weekDays()) { day in
                    VStack(spacing: 8) {
                        Text(day.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(day.isToday ? AppTheme.blue : .secondary)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(day.isLogged ? AppTheme.blue.opacity(day.isToday ? 0.95 : 0.2) : Color.secondary.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(day.isToday ? AppTheme.blue.opacity(0.75) : Color.clear, lineWidth: 1.5)
                            }
                            .frame(height: 42)
                            .overlay {
                                Image(systemName: day.isLogged ? "checkmark" : (day.isToday ? "circle.fill" : "circle"))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(day.isLogged ? (day.isToday ? .white : AppTheme.blue) : .secondary.opacity(day.isToday ? 0.85 : 0.45))
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
            WorkoutSummaryTile(title: "Current phase", value: snapshot.currentPhase?.label ?? "—", subtitle: snapshot.currentPhase?.weekRange ?? "Program syncing", symbol: "square.stack.3d.up.fill")
            WorkoutSummaryTile(title: "Phase week", value: "\(min(weekContext.phaseWeek, 9))", subtitle: weekContext.isDeload ? "Deload week" : "Week in current block", symbol: "calendar.badge.clock")
            WorkoutSummaryTile(title: "Sessions logged", value: "\(snapshot.totalSessions)", subtitle: "Tracked over time", symbol: "checkmark.seal.fill")
            WorkoutSummaryTile(title: "Weekly volume", value: formatCompactVolume(weeklyVolume), subtitle: "From completed sets", symbol: "chart.bar.fill")
        }
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Top personal records")
                .font(.headline)

            ForEach(topRecords) { record in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.gold.opacity(0.14))
                            .frame(width: 38, height: 38)

                        Image(systemName: "trophy.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.gold)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.name)
                            .font(.body.weight(.semibold))

                        Text("Best set \(record.bestSet.setLabel)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(record.bestSet.metricValue)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.blue)

                        Text(record.bestSet.metricLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if record.id != topRecords.last?.id {
                    Divider()
                }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct NativeWorkoutTodayView: View {
    let snapshot: WorkoutEngineSnapshot
    let isRefreshing: Bool
    let onOpenLiveWorkout: () -> Void
    let onOpenProgram: () -> Void

    private var weekContext: WorkoutWeekContext {
        snapshot.weekContext()
    }

    private var workout: WorkoutDay? {
        snapshot.currentDay
    }

    private var recentMatch: FlattenedWorkoutSession? {
        guard let workout else { return nil }
        return snapshot.sessions.first { session in
            let dayMatch = session.session.dayNum == workout.dayNum
            let nameMatch = session.session.dayName == workout.name
            return dayMatch || nameMatch
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                workoutHero
                workoutSummaryGrid
                exerciseLineupCard

                if let recentMatch {
                    recentPerformanceCard(recentMatch)
                }
            }
            .padding(18)
            .padding(.bottom, workout == nil ? 18 : 92)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.dashboardGradient)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if workout != nil {
                startWorkoutBar
            }
        }
    }

    private var workoutHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                if let currentPhase = snapshot.currentPhase {
                    workoutChip(currentPhase.label, style: .accent)
                }
                workoutChip("Week \(min(weekContext.phaseWeek, 9))", style: .neutral)
                if let muscleGroup = workout?.muscleGroup, !muscleGroup.isEmpty {
                    workoutChip(muscleGroup, style: .gold)
                }

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .tint(AppTheme.softGold)
                }
            }

            if let workout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(workout.name)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Day \(workout.dayNum) · \(workout.exerciseCount) exercises · \(workout.workingSetCount) working sets")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.78))
                }

                Button(action: onOpenProgram) {
                    Label("View program", systemImage: "calendar")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))
            } else {
                Text("Waiting for your workout.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(22)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: AppTheme.navy.opacity(0.24), radius: 24, y: 14)
    }

    private var startWorkoutBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))

            Button(action: onOpenLiveWorkout) {
                Label("Start workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.gold)
            .foregroundStyle(AppTheme.navy)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var workoutSummaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
            WorkoutSummaryTile(
                title: "Working sets",
                value: "\(workout?.workingSetCount ?? 0)",
                subtitle: "Across today’s main work",
                symbol: "number.square.fill"
            )
            WorkoutSummaryTile(
                title: "Exercises",
                value: "\(workout?.exerciseCount ?? 0)",
                subtitle: workout?.muscleGroup ?? "Planned for today",
                symbol: "list.bullet.rectangle.portrait.fill"
            )
            WorkoutSummaryTile(
                title: "Last session",
                value: recentMatch.map { formatCompactVolume($0.session.totalVolume) } ?? "—",
                subtitle: recentMatch.map { String($0.date.dropFirst(5)) } ?? "No matching log yet",
                symbol: "clock.arrow.circlepath"
            )
            WorkoutSummaryTile(
                title: "Phase week",
                value: "\(min(weekContext.phaseWeek, 9))",
                subtitle: weekContext.isDeload ? "Deload week" : "Current block",
                symbol: "calendar.badge.clock"
            )
        }
    }

    private var exerciseLineupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exercise lineup")
                .font(.headline)

            if let workout {
                let exercises = workout.trainingExercises

                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.blue)
                            .frame(width: 22, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.body.weight(.semibold))

                            Text("\(exercise.sets) sets · \(exercise.repRange) reps")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        if exercise.warmup == true {
                            workoutChip("Warm-up", style: .neutral)
                        }
                    }

                    if exercise.id != exercises.last?.id {
                        Divider()
                    }
                }
            } else {
                Text("No workout loaded yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private func recentPerformanceCard(_ session: FlattenedWorkoutSession) -> some View {
        let exercises = Array(session.session.exercises.prefix(3))

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last time on this day")
                        .font(.headline)
                    Text(String(session.date.dropFirst(5)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatCompactVolume(session.session.totalVolume))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.blue)
                    Text("volume")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(exercises) { exercise in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.body.weight(.semibold))

                        if let bestSet = exercise.bestSet {
                            Text("Best set \(bestSet.setLabel)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No tracked set data")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    if let bestSet = exercise.bestSet {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(bestSet.metricValue)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppTheme.blue)
                            Text(bestSet.metricLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if exercise.id != exercises.last?.id {
                    Divider()
                }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct NativeProgramView: View {
    enum ProgramSubtab: String, CaseIterable, Identifiable {
        case program = "Program"
        case wod = "WOD"

        var id: String { rawValue }
    }

    let snapshot: WorkoutEngineSnapshot
    let onOpenWorkout: () -> Void
    let onResetCrossfitWeek: () -> Void
    let onOpenCrossfitSource: () -> Void
    let onToggleCrossfitDone: (_ day: String, _ isDone: Bool) -> Void
    let onUpdateCrossfitScore: (_ day: String, _ score: String) -> Void
    let onUpdateCrossfitNotes: (_ day: String, _ notes: String) -> Void

    @State private var selectedPhaseID: Int
    @State private var selectedSubtab: ProgramSubtab = .program

    init(
        snapshot: WorkoutEngineSnapshot,
        onOpenWorkout: @escaping () -> Void,
        onResetCrossfitWeek: @escaping () -> Void,
        onOpenCrossfitSource: @escaping () -> Void,
        onToggleCrossfitDone: @escaping (_ day: String, _ isDone: Bool) -> Void,
        onUpdateCrossfitScore: @escaping (_ day: String, _ score: String) -> Void,
        onUpdateCrossfitNotes: @escaping (_ day: String, _ notes: String) -> Void
    ) {
        self.snapshot = snapshot
        self.onOpenWorkout = onOpenWorkout
        self.onResetCrossfitWeek = onResetCrossfitWeek
        self.onOpenCrossfitSource = onOpenCrossfitSource
        self.onToggleCrossfitDone = onToggleCrossfitDone
        self.onUpdateCrossfitScore = onUpdateCrossfitScore
        self.onUpdateCrossfitNotes = onUpdateCrossfitNotes
        _selectedPhaseID = State(initialValue: snapshot.settings.currentPhase)
    }

    private var selectedPhase: WorkoutPhase? {
        snapshot.phases.first(where: { $0.id == selectedPhaseID }) ?? snapshot.currentPhase
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Program section", selection: $selectedSubtab) {
                    ForEach(ProgramSubtab.allCases) { subtab in
                        Text(subtab.rawValue).tag(subtab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Program section")

                if selectedSubtab == .program {
                    phaseSelector

                    if let phase = selectedPhase {
                        phaseOverview(phase)

                        ForEach(phase.days) { day in
                            ProgramDayCard(
                                day: day,
                                isCurrent: phase.id == snapshot.settings.currentPhase && day.dayNum == snapshot.currentDay?.dayNum
                            )
                        }
                    }

                    trainingRules
                } else {
                    NativeCrossfitView(
                        snapshot: snapshot,
                        onResetWeek: onResetCrossfitWeek,
                        onOpenSource: onOpenCrossfitSource,
                        onToggleDone: onToggleCrossfitDone,
                        onUpdateScore: onUpdateCrossfitScore,
                        onUpdateNotes: onUpdateCrossfitNotes
                    )
                }
            }
            .padding(AppTheme.Spacing.l)
        }
        .background(AppTheme.dashboardGradient)
    }

    private var phaseSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(snapshot.phases) { phase in
                    Button {
                        selectedPhaseID = phase.id
                    } label: {
                        Text(phase.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedPhaseID == phase.id ? AppTheme.navy : .white.opacity(0.82))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(
                                Capsule()
                                    .fill(selectedPhaseID == phase.id ? AppTheme.gold : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func phaseOverview(_ phase: WorkoutPhase) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(phase.label)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text(phase.weekRange)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                if phase.id == snapshot.settings.currentPhase {
                    workoutChip("Current", style: .gold)
                }
            }

            Text("Five training days, current progression intact, and the same exercise ordering the web engine already uses.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))

            Button(action: onOpenWorkout) {
                Label("Open current workout", systemImage: "figure.strengthtraining.traditional")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.gold)
            .foregroundStyle(AppTheme.navy)
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [AppTheme.navy, AppTheme.blue.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var trainingRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Training rules")
                .font(.headline)

            ForEach(programRules, id: \.title) { rule in
                HStack(alignment: .top, spacing: 12) {
                    Text(rule.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 110, alignment: .leading)

                    Text(rule.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if rule.title != programRules.last?.title {
                    Divider()
                }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var programRules: [(title: String, detail: String)] {
        [
            ("Rep ranges", "Heavy lifts use 4-6 reps. Accessory work uses 8-10 where programmed."),
            ("Progression", "Add 10 pounds when you hit the top of the rep range."),
            ("Primary rest", "3-4 minutes for heavy barbell work."),
            ("Accessory rest", "90-120 seconds for assistance work."),
            ("Strength week", "Every fourth week trims set count while keeping the same loads."),
            ("Deload", "Week 9 of each phase is a no-lifting recovery week.")
        ]
    }
}

struct ProgramDayCard: View {
    let day: WorkoutDay
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Day \(day.dayNum)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(day.name)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(day.exerciseCount) exercises · \(day.workingSetCount) working sets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isCurrent {
                    workoutChip("Current", style: .accent)
                }
            }

            VStack(spacing: 10) {
                ForEach(day.exercises) { exercise in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(exercise.optional == true ? Color.secondary.opacity(0.35) : AppTheme.blue.opacity(0.82))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.name)
                                .font(.body.weight(exercise.warmup == true ? .semibold : .regular))
                                .foregroundStyle(exercise.optional == true ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)

                            if exercise.isAbs != true {
                                Text("\(exercise.sets) sets · \(exercise.repRange) reps\(exercise.optional == true ? " · Optional" : "")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(isCurrent ? AppTheme.blue.opacity(0.35) : AppTheme.border, lineWidth: 1)
        }
    }
}

struct NativeLiveWorkoutView: View {
    let snapshot: WorkoutEngineSnapshot
    let onClose: () -> Void
    let onFinish: (WorkoutLoggedSession) -> Void

    @State private var startedAt = Date()
    @State private var workingLogs: [String: [NativeWorkoutSetLog]] = [:]
    @State private var warmupLogs: [String: Set<Int>] = [:]
    @State private var skippedWarmups: [String: Set<Int>] = [:]
    @State private var skippedWorkingSets: [String: Set<Int>] = [:]
    @State private var activeRest: NativeWorkoutRest?
    @State private var remainingRest = 0
    @State private var sessionNote = ""
    @State private var finishedSummary: NativeWorkoutFinishedSummary?

    private var workout: WorkoutDay? {
        snapshot.currentDay
    }

    private var phase: WorkoutPhase? {
        snapshot.currentPhase
    }

    private var steps: [NativeWorkoutStep] {
        guard let workout else { return [] }
        return NativeWorkoutStep.build(from: workout, workingLogs: workingLogs)
    }

    private var activeStepIndex: Int? {
        steps.firstIndex { !isComplete($0) }
    }

    private var activeStep: NativeWorkoutStep? {
        guard let activeStepIndex else { return nil }
        return steps[activeStepIndex]
    }

    private var nextStep: NativeWorkoutStep? {
        guard let activeStepIndex, steps.indices.contains(activeStepIndex + 1) else { return nil }
        return steps[activeStepIndex + 1]
    }

    private var completedStepCount: Int {
        steps.filter(isComplete).count
    }

    private var completedWorkingSetCount: Int {
        workingLogs.values.flatMap { $0 }.filter { $0.isDone && !$0.isSkipped }.count
    }

    private var totalWorkingSetCount: Int {
        workout?.trainingExercises.reduce(0) { $0 + ($1.isAbs == true ? 0 : $1.sets) } ?? 0
    }

    private var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(completedStepCount) / Double(steps.count)
    }

    var body: some View {
        ZStack {
            AppTheme.workoutCanvas
                .ignoresSafeArea()

            if let finishedSummary {
                finishedView(finishedSummary)
            } else if let workout {
                VStack(spacing: 0) {
                    header(workout)

                    ScrollView {
                        VStack(spacing: 16) {
                            progressHeader(workout)

                            if let activeStep {
                                activeStepCard(activeStep)
                            } else {
                                readyToFinishCard(workout)
                            }

                            upcomingCard
                            notesCard
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 116)
                    }
                    .scrollIndicators(.hidden)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomActionBar
                }
            } else {
                WorkoutSnapshotLoadingView(title: "Live Workout")
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            startedAt = Date()
            initializeLogsIfNeeded()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard activeRest != nil else { return }
            remainingRest = max(0, remainingRest - 1)
        }
    }

    private func header(_ workout: WorkoutDay) -> some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)

                Text("\(completedWorkingSetCount)/\(totalWorkingSetCount) working sets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            if let phase {
                workoutChip(phase.label.replacingOccurrences(of: "Phase ", with: "P"), style: .gold)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func progressHeader(_ workout: WorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Guided workout")
                    .font(.title3.weight(.bold))

                Spacer()

                Text("\(completedStepCount)/\(steps.count) steps")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AppTheme.softGold)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(AppTheme.gold)
                        .frame(width: max(12, proxy.size.width * progress))
                }
            }
            .frame(height: 9)

            Text("Day \(workout.dayNum) - current set, rest, and next action stay visible.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.glassBorder, lineWidth: 1)
        }
    }

    private func activeStepCard(_ step: NativeWorkoutStep) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    workoutChip(step.kind.title, style: step.kind.chipStyle)

                    Text(step.exerciseName)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.subtitle)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 12)

                Text("Step \(step.displayIndex(in: steps))")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            if let activeRest {
                restPanel(activeRest)
            } else {
                stepInputs(step)
            }

            if step.kind == .warmup {
                Text("Warmups are logged for flow and timing only. They do not change working-set volume or PR history.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    step.kind == .warmup ? AppTheme.gold.opacity(0.16) : AppTheme.electricBlue.opacity(0.16),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(step.kind == .warmup ? AppTheme.gold.opacity(0.32) : AppTheme.electricBlue.opacity(0.28), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func stepInputs(_ step: NativeWorkoutStep) -> some View {
        switch step.kind {
        case .warmup:
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    NativeWorkoutMetricPanel(title: "This warmup", value: "\(formatWholeNumber(step.targetWeight)) lb", subtitle: "\(step.targetRepsText) reps")
                    NativeWorkoutMetricPanel(title: "Rest after", value: step.restLabel ?? "1 min", subtitle: "then next step")
                }

                weightControl(
                    title: "Working weight",
                    value: workingWeight(for: step.exerciseName),
                    step: 5,
                    onChange: { setWorkingWeight($0, for: step.exerciseName) }
                )
            }

        case .work:
            VStack(spacing: 12) {
                weightControl(
                    title: step.bodyweight ? "Added weight" : "Weight",
                    value: log(for: step).weight,
                    step: 5,
                    onChange: { updateWorkingLog(step, weight: $0) }
                )

                repsControl(
                    title: "Reps",
                    value: log(for: step).reps,
                    onChange: { updateWorkingLog(step, reps: $0) }
                )
            }

        case .abs:
            Text("Complete the full circuit round, then log it here. Rest follows the same guided flow.")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func restPanel(_ rest: NativeWorkoutRest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Resting now")
                        .font(.caption.weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.green.opacity(0.9))

                    Text("From \(rest.fromLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))

                    if !rest.nextLabel.isEmpty {
                        Text("Next \(rest.nextLabel)")
                            .font(.subheadline.weight(.bold))
                    }
                }

                Spacer()

                Text(formatRestTime(remainingRest))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .monospacedDigit()
                    .foregroundStyle(Color.green)
            }

            HStack(spacing: 10) {
                Button {
                    remainingRest += 30
                } label: {
                    Label("30 sec", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.9))

                Button {
                    clearRest()
                } label: {
                    Label(remainingRest > 0 ? "Skip Rest" : "Continue", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.green)
                .foregroundStyle(AppTheme.navy)
            }
        }
        .padding(16)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.green.opacity(0.26), lineWidth: 1)
        }
    }

    private func weightControl(title: String, value: Double, step: Double, onChange: @escaping (Double) -> Void) -> some View {
        NativeWorkoutStepper(
            title: title,
            value: value.cleanPounds,
            suffix: "lb",
            decrement: { onChange(max(0, value - step)) },
            increment: { onChange(value + step) }
        )
    }

    private func repsControl(title: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        NativeWorkoutStepper(
            title: title,
            value: "\(value)",
            suffix: "reps",
            decrement: { onChange(max(0, value - 1)) },
            increment: { onChange(value + 1) }
        )
    }

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Workout flow")
                    .font(.headline)

                Spacer()

                Text("\(completedWorkingSetCount)/\(totalWorkingSetCount) sets")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            let start = max(0, (activeStepIndex ?? steps.count) - 2)
            let visible = Array(steps.enumerated()).filter { index, _ in
                index >= start && index < start + 8
            }

            ForEach(visible, id: \.element.id) { index, step in
                NativeWorkoutStepRow(
                    index: index + 1,
                    step: step,
                    isActive: index == activeStepIndex,
                    isRestingNext: activeRest?.nextLabel == step.label,
                    isComplete: isComplete(step)
                )

                if step.id != visible.last?.element.id {
                    Divider()
                        .background(AppTheme.border)
                }
            }
        }
        .foregroundStyle(.primary)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session notes")
                .font(.headline)

            TextEditor(text: $sessionNote)
                .frame(minHeight: 94)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .foregroundStyle(.primary)
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func readyToFinishCard(_ workout: WorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            workoutChip("All Sets Complete", style: .accent)

            Text("Ready to finish")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("Save this session to your existing workout history and advance to the next program day.")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.glassBorder, lineWidth: 1)
        }
    }

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            if let activeStep {
                Button {
                    if activeRest != nil {
                        clearRest()
                    } else {
                        complete(activeStep)
                    }
                } label: {
                    Label(primaryActionTitle(for: activeStep), systemImage: activeRest == nil ? "checkmark" : "forward.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(activeStep.kind == .warmup ? Color.green : AppTheme.gold)
                .foregroundStyle(AppTheme.navy)
                .disabled(activeRest == nil && !canComplete(activeStep))

                if activeRest == nil {
                    Button {
                        skip(activeStep)
                    } label: {
                        Text(activeStep.kind == .warmup ? "Skip warmup" : "Skip set")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.85))
                }
            } else {
                Button {
                    finishWorkout()
                } label: {
                    Label("Finish Session", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.green)
                .foregroundStyle(AppTheme.navy)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func finishedView(_ summary: NativeWorkoutFinishedSummary) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 70))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(AppTheme.gold)

            VStack(spacing: 6) {
                Text("Session Complete")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                Text(summary.workoutName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 10) {
                NativeWorkoutMetricPanel(title: "Duration", value: summary.durationText, subtitle: "total time")
                NativeWorkoutMetricPanel(title: "Volume", value: formatCompactVolume(summary.volume), subtitle: "lb")
                NativeWorkoutMetricPanel(title: "PRs", value: "\(summary.prs.count)", subtitle: "new")
            }

            if !summary.nextWorkoutLabel.isEmpty {
                Text("Up next: \(summary.nextWorkoutLabel)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }

            Button {
                onFinish(summary.session)
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.gold)
            .foregroundStyle(AppTheme.navy)
        }
        .padding(24)
    }

    private func initializeLogsIfNeeded() {
        guard workingLogs.isEmpty, let workout else { return }

        var initial: [String: [NativeWorkoutSetLog]] = [:]
        for exercise in workout.exercises where exercise.isAbs != true {
            let weight = lastWeight(for: exercise.name) ?? 0
            let reps = topRepTarget(for: exercise.repRange)
            initial[exercise.name] = (0..<exercise.sets).map { _ in
                NativeWorkoutSetLog(weight: weight, reps: reps, isDone: false, isSkipped: false)
            }
        }
        workingLogs = initial
    }

    private func log(for step: NativeWorkoutStep) -> NativeWorkoutSetLog {
        workingLogs[step.exerciseName]?[safe: step.setIndex] ?? NativeWorkoutSetLog(weight: 0, reps: 0, isDone: false, isSkipped: false)
    }

    private func workingWeight(for exerciseName: String) -> Double {
        workingLogs[exerciseName]?.first?.weight ?? 0
    }

    private func setWorkingWeight(_ weight: Double, for exerciseName: String) {
        guard var logs = workingLogs[exerciseName] else { return }
        for index in logs.indices where !logs[index].isDone {
            logs[index].weight = weight
        }
        workingLogs[exerciseName] = logs
    }

    private func updateWorkingLog(_ step: NativeWorkoutStep, weight: Double? = nil, reps: Int? = nil) {
        guard var logs = workingLogs[step.exerciseName], logs.indices.contains(step.setIndex) else { return }
        if let weight {
            logs[step.setIndex].weight = weight
        }
        if let reps {
            logs[step.setIndex].reps = reps
        }
        workingLogs[step.exerciseName] = logs
    }

    private func canComplete(_ step: NativeWorkoutStep) -> Bool {
        switch step.kind {
        case .warmup, .abs:
            return true
        case .work:
            let setLog = log(for: step)
            if setLog.reps <= 0 { return false }
            return step.bodyweight || setLog.weight > 0
        }
    }

    private func complete(_ step: NativeWorkoutStep) {
        switch step.kind {
        case .warmup:
            warmupLogs[step.exerciseName, default: []].insert(step.setIndex)
        case .work:
            guard var logs = workingLogs[step.exerciseName], logs.indices.contains(step.setIndex) else { return }
            logs[step.setIndex].isDone = true
            logs[step.setIndex].isSkipped = false
            workingLogs[step.exerciseName] = logs
        case .abs:
            guard var logs = workingLogs[step.exerciseName] else {
                workingLogs[step.exerciseName] = [NativeWorkoutSetLog(weight: 0, reps: 0, isDone: true, isSkipped: false)]
                startRest(from: step)
                return
            }
            if logs.isEmpty {
                logs = [NativeWorkoutSetLog(weight: 0, reps: 0, isDone: true, isSkipped: false)]
            } else {
                logs[0].isDone = true
                logs[0].isSkipped = false
            }
            workingLogs[step.exerciseName] = logs
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        startRest(from: step)
    }

    private func skip(_ step: NativeWorkoutStep) {
        switch step.kind {
        case .warmup:
            warmupLogs[step.exerciseName, default: []].insert(step.setIndex)
            skippedWarmups[step.exerciseName, default: []].insert(step.setIndex)
        case .work, .abs:
            skippedWorkingSets[step.exerciseName, default: []].insert(step.setIndex)
            if var logs = workingLogs[step.exerciseName], logs.indices.contains(step.setIndex) {
                logs[step.setIndex].isDone = true
                logs[step.setIndex].isSkipped = true
                workingLogs[step.exerciseName] = logs
            } else {
                workingLogs[step.exerciseName] = [NativeWorkoutSetLog(weight: 0, reps: 0, isDone: true, isSkipped: true)]
            }
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        clearRest()
    }

    private func isComplete(_ step: NativeWorkoutStep) -> Bool {
        switch step.kind {
        case .warmup:
            return warmupLogs[step.exerciseName]?.contains(step.setIndex) == true
        case .work, .abs:
            return workingLogs[step.exerciseName]?[safe: step.setIndex]?.isDone == true
                || skippedWorkingSets[step.exerciseName]?.contains(step.setIndex) == true
        }
    }

    private func startRest(from step: NativeWorkoutStep) {
        guard let next = nextIncompleteStep(after: step) else {
            clearRest()
            return
        }

        let seconds = step.kind == .warmup ? step.restSeconds : restSeconds(for: step.exercise)
        activeRest = NativeWorkoutRest(fromLabel: step.label, nextLabel: next.label, duration: seconds)
        remainingRest = seconds
    }

    private func nextIncompleteStep(after step: NativeWorkoutStep) -> NativeWorkoutStep? {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return nil }
        return steps.dropFirst(index + 1).first { !isComplete($0) }
    }

    private func clearRest() {
        activeRest = nil
        remainingRest = 0
    }

    private func primaryActionTitle(for step: NativeWorkoutStep) -> String {
        if activeRest != nil {
            return "Skip Rest and Start Next"
        }

        switch step.kind {
        case .warmup:
            return "Log Warmup"
        case .work:
            return "Log Set"
        case .abs:
            return "Complete Circuit"
        }
    }

    private func finishWorkout() {
        guard let workout else { return }

        let duration = Date().timeIntervalSince(startedAt)
        let completedAt = ISO8601DateFormatter().string(from: Date())
        let loggedExercises = workout.exercises.map { exercise in
            WorkoutLoggedExercise(
                name: exercise.name,
                bodyweight: exercise.bodyweight == true,
                sets: loggedSets(for: exercise)
            )
        }
        let volume = loggedExercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { setTotal, set in
                setTotal + ((set.weight ?? 0) * Double(set.reps ?? 0))
            }
        }
        let prs = workout.exercises.compactMap { exercise -> String? in
            guard let currentBest = bestSet(from: loggedSets(for: exercise)) else { return nil }
            let previous = snapshot.stats(for: exercise.name)
            if currentBest.estimatedOneRepMax > (previous?.bestOneRepMax ?? 0) { return exercise.name }
            if currentBest.weight > (previous?.bestWeight ?? 0) { return exercise.name }
            if currentBest.volume > (previous?.bestVolume ?? 0) { return exercise.name }
            return nil
        }
        let nextWorkout = nextWorkoutLabel()
        let session = WorkoutLoggedSession(
            completedAt: completedAt,
            sessionId: "\(dateKey(for: Date()))-\(Int(Date().timeIntervalSince1970 * 1000))",
            phase: phase?.id,
            dayNum: workout.dayNum,
            dayName: workout.name,
            duration: duration,
            volume: volume,
            prsHit: prs,
            notes: sessionNote.trimmingCharacters(in: .whitespacesAndNewlines),
            exercises: loggedExercises
        )

        finishedSummary = NativeWorkoutFinishedSummary(
            session: session,
            workoutName: workout.name,
            duration: duration,
            volume: volume,
            prs: prs,
            nextWorkoutLabel: nextWorkout
        )
    }

    private func loggedSets(for exercise: WorkoutExercise) -> [WorkoutLoggedSet] {
        guard exercise.isAbs != true else {
            let completed = workingLogs[exercise.name]?.first?.isDone == true
            let skipped = workingLogs[exercise.name]?.first?.isSkipped == true
            return completed && !skipped ? [WorkoutLoggedSet(weight: 0, reps: 0)] : []
        }

        return (workingLogs[exercise.name] ?? [])
            .filter { $0.isDone && !$0.isSkipped }
            .map { WorkoutLoggedSet(weight: $0.weight, reps: $0.reps) }
    }

    private func nextWorkoutLabel() -> String {
        guard let phase else { return "" }
        let nextIndex = (snapshot.settings.currentDayIndex + 1) % phase.days.count
        guard phase.days.indices.contains(nextIndex) else { return "" }
        let next = phase.days[nextIndex]
        return "Day \(next.dayNum) - \(next.name)"
    }

    private func lastWeight(for exerciseName: String) -> Double? {
        for session in snapshot.sessions {
            guard let exercise = session.session.exercises.first(where: { $0.name == exerciseName }) else { continue }
            if let set = exercise.sets.first(where: { ($0.weight ?? 0) > 0 }) {
                return set.weight
            }
        }
        return nil
    }

    private func topRepTarget(for repRange: String) -> Int {
        let parts = repRange.split { !$0.isNumber }.compactMap { Int($0) }
        return parts.last ?? parts.first ?? 0
    }

    private func restSeconds(for exercise: WorkoutExercise) -> Int {
        if exercise.isAbs == true { return 60 }
        if NativeWorkoutStep.primaryRestExerciseNames.contains(exercise.name) { return 210 }
        if exercise.repRange == "8-10" { return 90 }
        if exercise.optional == true || exercise.bodyweight == true { return 105 }
        return 120
    }

    private func bestSet(from sets: [WorkoutLoggedSet]) -> NativeWorkoutBestSet? {
        sets.compactMap { NativeWorkoutBestSet(set: $0) }.max { lhs, rhs in
            if lhs.estimatedOneRepMax != rhs.estimatedOneRepMax {
                return lhs.estimatedOneRepMax < rhs.estimatedOneRepMax
            }
            if lhs.weight != rhs.weight {
                return lhs.weight < rhs.weight
            }
            if lhs.reps != rhs.reps {
                return lhs.reps < rhs.reps
            }
            return lhs.volume < rhs.volume
        }
    }

    private func formatRestTime(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private enum NativeWorkoutStepKind: Equatable {
    case warmup
    case work
    case abs

    var title: String {
        switch self {
        case .warmup:
            return "Warmup"
        case .work:
            return "Working Set"
        case .abs:
            return "Circuit"
        }
    }

    var chipStyle: WorkoutChipStyle {
        switch self {
        case .warmup:
            return .gold
        case .work:
            return .accent
        case .abs:
            return .neutral
        }
    }
}

private struct NativeWorkoutStep: Identifiable, Equatable {
    let kind: NativeWorkoutStepKind
    let exercise: WorkoutExercise
    let exerciseName: String
    let exerciseIndex: Int
    let setIndex: Int
    let totalSets: Int
    let targetReps: Int
    let targetWeight: Double
    let restLabel: String?
    let restSeconds: Int
    let bodyweight: Bool

    var id: String {
        "\(kind)-\(exerciseName)-\(setIndex)"
    }

    var targetRepsText: String {
        targetReps > 0 ? "\(targetReps)" : exercise.repRange
    }

    var subtitle: String {
        switch kind {
        case .warmup:
            return "Warmup \(setIndex + 1) of \(totalSets) - \(formatWholeNumber(targetWeight)) lb x \(targetRepsText)"
        case .work:
            return "Set \(setIndex + 1) of \(totalSets) - target \(exercise.repRange)"
        case .abs:
            return "Complete the circuit round"
        }
    }

    var label: String {
        switch kind {
        case .warmup:
            return "\(exerciseName) - Warmup \(setIndex + 1)"
        case .work:
            return "\(exerciseName) - Set \(setIndex + 1)"
        case .abs:
            return "\(exerciseName) - Circuit"
        }
    }

    func displayIndex(in steps: [NativeWorkoutStep]) -> Int {
        (steps.firstIndex { $0.id == id } ?? 0) + 1
    }

    static let primaryRestExerciseNames: Set<String> = [
        "Barbell Deadlift",
        "Barbell Squat",
        "Barbell Front Squat",
        "Romanian Deadlift",
        "Flat Barbell Bench Press",
        "Incline Barbell Bench Press",
        "Barbell Military Press",
        "Close-Grip Bench Press"
    ]

    static func build(from workout: WorkoutDay, workingLogs: [String: [NativeWorkoutSetLog]]) -> [NativeWorkoutStep] {
        var steps: [NativeWorkoutStep] = []

        for (exerciseIndex, exercise) in workout.exercises.enumerated() {
            if exercise.isAbs == true {
                steps.append(
                    NativeWorkoutStep(
                        kind: .abs,
                        exercise: exercise,
                        exerciseName: exercise.name,
                        exerciseIndex: exerciseIndex,
                        setIndex: 0,
                        totalSets: 1,
                        targetReps: 0,
                        targetWeight: 0,
                        restLabel: nil,
                        restSeconds: 60,
                        bodyweight: exercise.bodyweight == true
                    )
                )
                continue
            }

            let workingWeight = workingLogs[exercise.name]?.first?.weight ?? 0

            if exercise.warmup == true {
                warmups(for: workingWeight).enumerated().forEach { index, warmup in
                    steps.append(
                        NativeWorkoutStep(
                            kind: .warmup,
                            exercise: exercise,
                            exerciseName: exercise.name,
                            exerciseIndex: exerciseIndex,
                            setIndex: index,
                            totalSets: 4,
                            targetReps: warmup.reps,
                            targetWeight: warmup.weight,
                            restLabel: warmup.restLabel,
                            restSeconds: warmup.restSeconds,
                            bodyweight: exercise.bodyweight == true
                        )
                    )
                }
            }

            for setIndex in 0..<exercise.sets {
                steps.append(
                    NativeWorkoutStep(
                        kind: .work,
                        exercise: exercise,
                        exerciseName: exercise.name,
                        exerciseIndex: exerciseIndex,
                        setIndex: setIndex,
                        totalSets: exercise.sets,
                        targetReps: 0,
                        targetWeight: workingWeight,
                        restLabel: nil,
                        restSeconds: 0,
                        bodyweight: exercise.bodyweight == true
                    )
                )
            }
        }

        return steps
    }

    private static func warmups(for workingWeight: Double) -> [NativeWorkoutWarmup] {
        [
            NativeWorkoutWarmup(percent: 0.5, reps: 12, restLabel: "1 min", restSeconds: 60),
            NativeWorkoutWarmup(percent: 0.5, reps: 10, restLabel: "1 min", restSeconds: 60),
            NativeWorkoutWarmup(percent: 0.7, reps: 4, restLabel: "1 min", restSeconds: 60),
            NativeWorkoutWarmup(percent: 0.9, reps: 1, restLabel: "2-3 min", restSeconds: 150)
        ].map { warmup in
            var copy = warmup
            copy.weight = (workingWeight * warmup.percent / 5).rounded() * 5
            return copy
        }
    }
}

private struct NativeWorkoutWarmup: Equatable {
    let percent: Double
    let reps: Int
    let restLabel: String
    let restSeconds: Int
    var weight: Double = 0
}

private struct NativeWorkoutSetLog: Equatable {
    var weight: Double
    var reps: Int
    var isDone: Bool
    var isSkipped: Bool
}

private struct NativeWorkoutRest: Equatable {
    let fromLabel: String
    let nextLabel: String
    let duration: Int
}

private struct NativeWorkoutFinishedSummary: Equatable {
    let session: WorkoutLoggedSession
    let workoutName: String
    let duration: TimeInterval
    let volume: Double
    let prs: [String]
    let nextWorkoutLabel: String

    var durationText: String {
        let seconds = Int(duration.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct NativeWorkoutBestSet: Equatable {
    let weight: Double
    let reps: Int
    let volume: Double
    let estimatedOneRepMax: Double

    init?(set: WorkoutLoggedSet) {
        let weight = set.weight ?? 0
        let reps = set.reps ?? 0
        guard weight > 0 || reps > 0 else { return nil }

        self.weight = weight
        self.reps = reps
        volume = weight * Double(reps)
        estimatedOneRepMax = weight > 0 && reps > 0 ? round(weight * (1 + (Double(reps) / 30.0))) : 0
    }
}

private struct NativeWorkoutMetricPanel: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct NativeWorkoutStepper: View {
    let title: String
    let value: String
    let suffix: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.58))

            HStack(spacing: 10) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.headline.weight(.heavy))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.9))

                VStack(spacing: 1) {
                    Text(value)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(suffix)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.heavy))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.9))
            }
        }
    }
}

private struct NativeWorkoutStepRow: View {
    let index: Int
    let step: NativeWorkoutStep
    let isActive: Bool
    let isRestingNext: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(dotFill)
                    .frame(width: 32, height: 32)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.black))
                        .foregroundStyle(AppTheme.navy)
                } else {
                    Text("\(index)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(isActive ? AppTheme.navy : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.exerciseName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Text(step.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(step.kind == .warmup ? "WU" : step.kind == .abs ? "ABS" : "SET")
                .font(.caption2.weight(.black))
                .foregroundStyle(step.kind == .warmup ? AppTheme.navy : .white)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(step.kind == .warmup ? AppTheme.gold : AppTheme.blue, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(rowFill)
    }

    private var dotFill: Color {
        if isComplete { return Color.green }
        if isActive { return AppTheme.gold }
        if isRestingNext { return Color.green.opacity(0.22) }
        return Color.secondary.opacity(0.14)
    }

    private var rowFill: Color {
        if isActive { return AppTheme.gold.opacity(0.08) }
        if isRestingNext { return Color.green.opacity(0.08) }
        return .clear
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct NativeProgressView: View {
    let snapshot: WorkoutEngineSnapshot
    let onOpenWorkout: () -> Void

    @State private var selectedExerciseName: String?

    private var weeklyVolumes: [WeeklyVolumeEntry] {
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return snapshot.weeklyVolumes().enumerated().map { index, value in
            WeeklyVolumeEntry(id: index, label: labels[index], volume: value)
        }
    }

    private var selectedHistory: [WorkoutExerciseHistoryPoint] {
        guard let selectedExerciseName else { return [] }
        return snapshot.history(for: selectedExerciseName)
    }

    private var selectedStats: WorkoutExerciseStats? {
        guard let selectedExerciseName else { return nil }
        return snapshot.stats(for: selectedExerciseName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressHero
                weeklyVolumeCard
                exerciseProgressCard
                recentSessionsCard
            }
            .padding(18)
        }
        .background(AppTheme.dashboardGradient)
        .onAppear {
            if selectedExerciseName == nil {
                selectedExerciseName = snapshot.exerciseNames.first
            }
        }
    }

    private var progressHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Progress")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Recent sessions, top sets, and trends from the same workout logs you already trust.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onOpenWorkout) {
                    Label("Workout", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))
            }

            HStack(spacing: 12) {
                WorkoutHeroMetric(value: "\(snapshot.totalSessions)", label: "Sessions")
                WorkoutHeroMetric(value: formatCompactVolume(snapshot.weeklyVolumes().reduce(0, +)), label: "This week")
                WorkoutHeroMetric(value: "\(snapshot.streak())", label: "Streak")
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [AppTheme.navy, AppTheme.blue.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var weeklyVolumeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Weekly volume")
                .font(.headline)

            if weeklyVolumes.contains(where: { $0.volume > 0 }) {
                Chart(weeklyVolumes) { entry in
                    BarMark(
                        x: .value("Day", entry.label),
                        y: .value("Volume", entry.volume)
                    )
                    .foregroundStyle(entry.volume > 0 ? AppTheme.blue : Color.secondary.opacity(0.18))
                    .cornerRadius(6)
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            } else {
                Text("Log a few sessions and your weekly training volume will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var exerciseProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exercise progress")
                .font(.headline)

            if snapshot.exerciseNames.isEmpty {
                Text("Your exercise history will appear here once you have a few logged sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(snapshot.exerciseNames, id: \.self) { name in
                            Button {
                                selectedExerciseName = name
                            } label: {
                                Text(name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(selectedExerciseName == name ? AppTheme.navy : .primary)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 38)
                                    .background(
                                        Capsule()
                                            .fill(selectedExerciseName == name ? AppTheme.gold : Color.secondary.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let selectedExerciseName, let stats = selectedStats {
                    HStack(spacing: 12) {
                        WorkoutSummaryTile(title: "Best set", value: stats.bestSet?.setLabel ?? "—", subtitle: selectedExerciseName, symbol: "trophy.fill")
                        WorkoutSummaryTile(title: "Est. 1RM", value: stats.bestOneRepMax > 0 ? formatWholeNumber(stats.bestOneRepMax) : "—", subtitle: "\(stats.sessionCount) sessions", symbol: "chart.line.uptrend.xyaxis")
                    }

                    if !selectedHistory.isEmpty {
                        Chart(selectedHistory) { point in
                            LineMark(
                                x: .value("Session", point.label),
                                y: .value("Metric", point.metric)
                            )
                            .foregroundStyle(AppTheme.blue)

                            AreaMark(
                                x: .value("Session", point.label),
                                y: .value("Metric", point.metric)
                            )
                            .foregroundStyle(AppTheme.blue.opacity(0.15))

                            PointMark(
                                x: .value("Session", point.label),
                                y: .value("Metric", point.metric)
                            )
                            .foregroundStyle(AppTheme.gold)
                        }
                        .frame(height: 210)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 3))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent sessions")
                .font(.headline)

            if snapshot.recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                    Text("Your completed workouts will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(action: onOpenWorkout) {
                        Label("Start your first workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(AppTheme.Spacing.l)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
            } else {
                ForEach(snapshot.recentSessions) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.session.dayName ?? "Workout")
                                    .font(.body.weight(.semibold))
                                Text(session.date)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if session.session.totalVolume > 0 {
                                Text("\(formatCompactVolume(session.session.totalVolume)) lbs")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.blue)
                            }
                        }

                        Text(sessionSummary(for: session))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let prs = session.session.prsHit, !prs.isEmpty {
                            Text("PR: \(prs.joined(separator: ", "))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.gold)
                        }
                    }

                    if session.id != snapshot.recentSessions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private func sessionSummary(for session: FlattenedWorkoutSession) -> String {
        let parts = session.session.exercises
            .filter { !$0.sets.isEmpty }
            .prefix(3)
            .map { exercise -> String in
                let setSummary = exercise.sets.prefix(2).map { set in
                    "\(formatWholeNumber(set.weight ?? 0))x\(set.reps ?? 0)"
                }.joined(separator: ", ")
                return "\(exercise.name) (\(setSummary))"
            }
        return parts.joined(separator: " · ")
    }
}

struct NativeCrossfitView: View {
    let snapshot: WorkoutEngineSnapshot
    let onResetWeek: () -> Void
    let onOpenSource: () -> Void
    let onToggleDone: (_ day: String, _ isDone: Bool) -> Void
    let onUpdateScore: (_ day: String, _ score: String) -> Void
    let onUpdateNotes: (_ day: String, _ notes: String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                crossfitHero
                crossfitSummary

                if let week = snapshot.crossfitWeek {
                    ForEach(week.days) { day in
                        NativeCrossfitDayCard(
                            day: day,
                            log: snapshot.crossfitLogs?[day.day],
                            onToggleDone: { isDone in onToggleDone(day.day, isDone) },
                            onUpdateScore: { score in onUpdateScore(day.day, score) },
                            onUpdateNotes: { notes in onUpdateNotes(day.day, notes) }
                        )
                    }
                } else {
                    WorkoutSnapshotLoadingView(title: "WOD")
                }
            }
            .padding(18)
        }
        .background(AppTheme.dashboardGradient)
    }

    private var crossfitHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CrossFit WOD")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text(snapshot.crossfitWeek?.source ?? "Member-site import")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.74))
                }

                Spacer()

                workoutChip("Member", style: .gold)
            }

            HStack(spacing: 12) {
                Button(action: onResetWeek) {
                    Label("Reset week", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))

                Button(action: onOpenSource) {
                    Label("Open source", systemImage: "safari")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.gold)
                .foregroundStyle(AppTheme.navy)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [AppTheme.navy, AppTheme.blue.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var crossfitSummary: some View {
        HStack(spacing: 12) {
            WorkoutSummaryTile(title: "Days loaded", value: "\(snapshot.crossfitWeek?.days.count ?? 0)", subtitle: "This imported week", symbol: "calendar")
            WorkoutSummaryTile(title: "Completed", value: "\(snapshot.crossfitCompletedCount)", subtitle: "Marked done", symbol: "checkmark.circle.fill")
            WorkoutSummaryTile(title: "Imported", value: snapshot.crossfitWeek.map { String($0.importedAt.dropFirst(5)) } ?? "—", subtitle: "Snapshot date", symbol: "square.and.arrow.down.fill")
        }
    }
}

struct NativeCrossfitDayCard: View {
    let day: CrossfitWorkoutDay
    let log: CrossfitDayLog?
    let onToggleDone: (Bool) -> Void
    let onUpdateScore: (String) -> Void
    let onUpdateNotes: (String) -> Void

    @State private var scoreText: String = ""
    @State private var notesText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(day.day)
                        .font(.title3.weight(.bold))

                    Text(day.section)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onToggleDone(!(log?.done ?? false))
                } label: {
                    Label(log?.done == true ? "Completed" : "Mark done", systemImage: log?.done == true ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(log?.done == true ? AppTheme.gold : AppTheme.blue)
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(day.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(AppTheme.blue.opacity(0.85))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        Text(line)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }

            if let extra = day.extra, !extra.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extra")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.gold)

                    ForEach(Array(extra.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(AppTheme.groupedBackground, in: RoundedRectangle(cornerRadius: 16))
            }

            if let notes = day.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coach notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(notes.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(AppTheme.groupedBackground, in: RoundedRectangle(cornerRadius: 16))
            }

            VStack(spacing: 12) {
                TextField("Score / time / weight", text: $scoreText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onChange(of: scoreText) { _, newValue in
                        onUpdateScore(newValue)
                    }

                TextField("Workout notes, substitutions, or scaling", text: $notesText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4, reservesSpace: true)
                    .font(.body)
                    .onChange(of: notesText) { _, newValue in
                        onUpdateNotes(newValue)
                    }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke((log?.done == true ? AppTheme.gold.opacity(0.3) : AppTheme.border), lineWidth: 1)
        }
        .onAppear {
            scoreText = log?.score ?? ""
            notesText = log?.notes ?? ""
        }
        .onChange(of: log?.score ?? "") { _, newValue in
            if newValue != scoreText {
                scoreText = newValue
            }
        }
        .onChange(of: log?.notes ?? "") { _, newValue in
            if newValue != notesText {
                notesText = newValue
            }
        }
    }
}

struct WorkoutHeroMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WeeklyVolumeEntry: Identifiable {
    let id: Int
    let label: String
    let volume: Double
}

struct WorkoutSummaryTile: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.blue.opacity(0.12))
                    .frame(width: 38, height: 38)

                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(AppTheme.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct WorkoutSnapshotLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(AppTheme.gold)

            Text("Loading \(title.lowercased())")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Still using your existing workout engine. We’re just waiting for the current app state.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(AppTheme.navy)
    }
}

enum WorkoutChipStyle {
    case accent
    case neutral
    case gold
}

func workoutChip(_ title: String, style: WorkoutChipStyle) -> some View {
    let fill: Color
    let foreground: Color

    switch style {
    case .accent:
        fill = AppTheme.blue.opacity(0.18)
        foreground = AppTheme.electricBlue
    case .neutral:
        fill = Color.white.opacity(0.1)
        foreground = .white.opacity(0.86)
    case .gold:
        fill = AppTheme.gold.opacity(0.18)
        foreground = AppTheme.softGold
    }

    return Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(Capsule().fill(fill))
}

private extension Date {
    var startOfDayValue: Date {
        Calendar.current.startOfDay(for: self)
    }
}

private func dateKey(for date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
}

private func dateFromKey(_ value: String) -> Date? {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

private func formatCompactVolume(_ value: Double) -> String {
    guard value > 0 else { return "—" }
    if value >= 1000 {
        return "\(Int(round(value / 1000)))k"
    }
    return formatWholeNumber(value)
}

private func formatWholeNumber(_ value: Double) -> String {
    String(Int(round(value)))
}
