import SwiftUI

struct HealthDashboardContent: View {
    @StateObject private var manager = HealthKitManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroPanel
                metricGrid
                recoveryPanel
            }
            .padding(18)
        }
        .background(AppTheme.pageGradient)
        .task {
            await manager.requestAuthorizationAndRefresh()
        }
        .refreshable {
            await manager.refresh()
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.softGold)

                    Text(manager.readinessTitle)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .foregroundStyle(.white)

                    Text(manager.authorizationMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 0) {
                    Text(manager.readinessScoreText)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .foregroundStyle(AppTheme.gold)

                    Text("/ 100")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }

            ProgressView(value: manager.readinessScore)
                .tint(AppTheme.gold)

            HStack {
                Label(manager.lastUpdatedText, systemImage: manager.isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))

                Spacer()

                Button {
                    Task { await manager.refresh() }
                } label: {
                    Text(manager.isRefreshing ? "Syncing" : "Refresh")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.gold)
                .foregroundStyle(AppTheme.navy)
                .disabled(manager.isRefreshing)
            }
        }
        .padding(20)
        .background(
            AppTheme.heroGradient,
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppTheme.gold.opacity(0.18))
                .frame(width: 130, height: 130)
                .offset(x: 48, y: -54)
        }
        .shadow(color: AppTheme.navy.opacity(0.22), radius: 24, y: 14)
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            MetricTile(title: "Steps", value: manager.stepsText, symbol: "shoeprints.fill")
            MetricTile(title: "Energy", value: manager.activeEnergyText, symbol: "flame.fill")
            MetricTile(title: "Sleep", value: manager.sleepText, symbol: "bed.double.fill")
            MetricTile(title: "Resting HR", value: manager.restingHeartRateText, symbol: "heart.fill")
            MetricTile(title: "HRV", value: manager.hrvText, symbol: "waveform.path.ecg")
            MetricTile(title: "Weight", value: manager.weightText, symbol: "scalemass.fill")
        }
    }

    private var recoveryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Training readiness", systemImage: "bolt.heart.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.navy)

            Text(manager.recoveryGuidance)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct HealthDashboardView: View {
    var body: some View {
        NavigationStack {
            HealthDashboardContent()
                .navigationTitle("Health")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
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
                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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

#Preview {
    HealthDashboardView()
}
