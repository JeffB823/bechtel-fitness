import SwiftData
import SwiftUI

struct WorkoutPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var activeSession: WorkoutSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    templateList
                    recentSessions
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Train")
            .task {
                WorkoutRepository(context: modelContext).seedIfNeeded()
            }
            .fullScreenCover(item: $activeSession) { session in
                LiveWorkoutView(session: session)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Progressive Strength")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)

                    Text("Templates now pre-fill from your last successful workout.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                }
            }

            Text("If you hit all working-set reps last time, upper-body exercises move up 5 lb and lower-body exercises move up 10 lb.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [AppTheme.navy, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .shadow(color: AppTheme.navy.opacity(0.22), radius: 24, y: 14)
    }

    private var templateList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Templates")
                .font(.headline)

            ForEach(templates) { template in
                TemplateCard(
                    template: template,
                    lastSession: sessions.first { $0.name == template.name && $0.isFinished },
                    startAction: {
                        activeSession = WorkoutRepository(context: modelContext).startWorkout(from: template)
                    },
                    duplicateAction: {
                        if let session = WorkoutRepository(context: modelContext).duplicateMostRecentSession(named: template.name) {
                            activeSession = session
                        }
                    }
                )
            }
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)

            if sessions.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                    Text("Your completed workouts will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        if let template = templates.first {
                            activeSession = WorkoutRepository(context: modelContext).startWorkout(from: template)
                        }
                    } label: {
                        Label("Start your first workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(templates.isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.l)
                .background(.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
            } else {
                ForEach(sessions.prefix(5)) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.name)
                                .font(.subheadline.weight(.bold))
                            Text("\(session.completedSetCount)/\(session.totalSetCount) sets • \(session.totalVolume.cleanPounds) lb volume")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(session.startedAt, style: .date)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }
}

private struct TemplateCard: View {
    let template: WorkoutTemplate
    let lastSession: WorkoutSession?
    let startAction: () -> Void
    let duplicateAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.title3.weight(.bold))

                    Text(template.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(template.orderedExercises.count) moves")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.gold.opacity(0.18), in: Capsule())
                    .foregroundStyle(AppTheme.navy)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(template.orderedExercises) { exercise in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(exercise.exerciseNameSnapshot) • \(exercise.targetSetCount)x\(exercise.targetReps) @ \(exercise.targetWeight.cleanPounds)")
                            .font(.subheadline.weight(.semibold))

                        if !exercise.notes.isEmpty {
                            Text(exercise.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            HStack {
                Button(action: startAction) {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)

                Button(action: duplicateAction) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(lastSession == nil)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

#Preview {
    WorkoutPlannerView()
}
