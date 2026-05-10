import SwiftUI

struct WatchWorkoutRemoteView: View {
    @StateObject private var tracker = WatchWorkoutTracker()
    @StateObject private var healthSession = WatchWorkoutSessionManager()
    @State private var now = Date()

    private let restTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    statusCard

                    if tracker.isWorkoutActive {
                        currentSetCard
                        actionsCard
                        restCard
                    } else {
                        idleCard
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Workout")
            .onAppear {
                healthSession.prepare()
                tracker.requestState()
            }
            .onReceive(restTicker) { date in
                now = date
            }
            .onChange(of: tracker.isWorkoutActive) { _, isActive in
                if isActive {
                    healthSession.startIfNeeded()
                } else {
                    healthSession.end()
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tracker.workoutName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Circle()
                    .fill(tracker.isReachable ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
            }

            Text(tracker.isWorkoutActive ? "Live from iPhone" : "Waiting for an active iPhone workout")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.blue.opacity(0.16)))
    }

    private var currentSetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tracker.exerciseName)
                .font(.headline)
                .lineLimit(2)

            Text(tracker.setProgress)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                metric(title: "Weight", value: tracker.weightText)
                metric(title: "Reps", value: tracker.repsText)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionsCard: some View {
        VStack(spacing: 8) {
            Button {
                tracker.logSet()
            } label: {
                Label("Log set", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .tint(.yellow)

            Button {
                tracker.skipSet()
            } label: {
                Label("Skip set", systemImage: "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var restCard: some View {
        HStack {
            Label("Rest", systemImage: "timer")
                .font(.headline)

            Spacer()

            Text(tracker.restRemainingText(at: now))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.yellow)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
    }

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start a workout on your iPhone to use the watch as a live set remote.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                tracker.requestState()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
    }
}
