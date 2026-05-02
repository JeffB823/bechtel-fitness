import SwiftUI

struct RestTimerRing: View {
    @ObservedObject var restTimer: RestTimerManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = restTimer.remainingSeconds
            let progress = restTimer.progress

            VStack(spacing: AppTheme.Spacing.m) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: AppTheme.Size.restRingLine)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(ringColor(for: remaining), style: StrokeStyle(lineWidth: AppTheme.Size.restRingLine, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: AppTheme.Spacing.xs) {
                        Text(restTimer.remainingCountdownText)
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .contentTransition(.numericText())
                            .monospacedDigit()
                            .accessibilityLabel("Rest timer \(restTimer.remainingCountdownText)")

                        Text("Rest")
                            .font(.headline)
                            .foregroundStyle(AppTheme.TextOnDark.secondary)
                    }
                }
                .frame(width: AppTheme.Size.restRing, height: AppTheme.Size.restRing)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rest timer")
                .accessibilityHint("Shows remaining rest time before the next set.")

                HStack(spacing: AppTheme.Spacing.s) {
                    Button {
                        restTimer.add(seconds: -15)
                    } label: {
                        Text("-15s")
                            .frame(minWidth: AppTheme.Size.restPill)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Remove 15 seconds")
                    .accessibilityHint("Shortens the current rest timer by 15 seconds.")

                    Button {
                        restTimer.add(seconds: 15)
                    } label: {
                        Text("+15s")
                            .frame(minWidth: AppTheme.Size.restPill)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Add 15 seconds")
                    .accessibilityHint("Adds 15 seconds to the current rest timer.")
                }
            }
            .frame(maxWidth: restTimer.isResting ? .infinity : 0)
            .frame(height: restTimer.isResting ? nil : 0)
            .opacity(restTimer.isResting ? 1 : 0)
            .clipped()
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: restTimer.isResting)
            .onChange(of: remaining) { _, newValue in
                restTimer.notifyIfNeeded(remaining: newValue)
            }
        }
    }

    private func ringColor(for remaining: Int) -> Color {
        remaining <= 10 ? AppTheme.electricBlue : AppTheme.gold
    }
}
