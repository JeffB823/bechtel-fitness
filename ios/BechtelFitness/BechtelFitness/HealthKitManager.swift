import Foundation
import HealthKit
import SwiftUI

private enum HealthKitExportError: Error {
    case missingWorkout
}

@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var authorizationMessage = "Connect Apple Health to see today's recovery signals."
    @Published private(set) var steps: Double?
    @Published private(set) var activeEnergy: Double?
    @Published private(set) var sleepHours: Double?
    @Published private(set) var restingHeartRate: Double?
    @Published private(set) var hrv: Double?
    @Published private(set) var weight: Double?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private let store = HKHealthStore()

    var stepsText: String {
        formatNumber(steps, fallback: "--")
    }

    var activeEnergyText: String {
        guard let activeEnergy else { return "--" }
        return "\(Int(activeEnergy.rounded())) kcal"
    }

    var sleepText: String {
        guard let sleepHours else { return "--" }
        return String(format: "%.1f hr", sleepHours)
    }

    var restingHeartRateText: String {
        guard let restingHeartRate else { return "--" }
        return "\(Int(restingHeartRate.rounded())) bpm"
    }

    var hrvText: String {
        guard let hrv else { return "--" }
        return "\(Int(hrv.rounded())) ms"
    }

    var weightText: String {
        guard let weight else { return "--" }
        return String(format: "%.1f lb", weight)
    }

    var readinessScore: Double {
        var score = 0.55

        if let sleepHours {
            score += min(max((sleepHours - 6.0) / 3.0, -0.25), 0.25)
        }

        if let restingHeartRate, restingHeartRate > 0 {
            score += restingHeartRate <= 62 ? 0.1 : restingHeartRate >= 75 ? -0.12 : 0
        }

        if let hrv, hrv > 0 {
            score += hrv >= 45 ? 0.1 : hrv <= 25 ? -0.1 : 0
        }

        return min(max(score, 0), 1)
    }

    var readinessScoreText: String {
        let score = Int((readinessScore * 100).rounded())
        return "\(score)"
    }

    var readinessColor: Color {
        switch readinessScore {
        case 0.75...:
            return .green
        case 0.5..<0.75:
            return .blue
        default:
            return .orange
        }
    }

    var recoveryGuidance: String {
        if sleepHours == nil && restingHeartRate == nil && hrv == nil {
            return "Once Health access is allowed, this tab will use sleep, resting heart rate, HRV, steps, active energy, and body weight to give you a simple daily training read."
        }

        if readinessScore >= 0.75 {
            return "Good day to train hard. Keep the warm-up honest and use your first working sets to confirm the signal."
        }

        if readinessScore >= 0.5 {
            return "Normal training day. Push if the bar speed is there, but keep a little room for recovery."
        }

        return "Recovery looks compressed. Consider reducing volume, keeping intensity controlled, or making today a technique-focused session."
    }

    var readinessTitle: String {
        switch readinessScore {
        case 0.75...:
            return "Green Light"
        case 0.5..<0.75:
            return "Train Smart"
        default:
            return "Recovery Bias"
        }
    }

    var lastUpdatedText: String {
        guard let lastUpdated else { return "Not synced yet" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: lastUpdated, relativeTo: Date()))"
    }

    func requestAuthorizationAndRefresh() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationMessage = "Apple Health is not available on this device."
            return
        }

        do {
            try await store.requestAuthorization(toShare: shareTypes, read: healthTypes)
            authorizationMessage = "Apple Health connected. Pull to refresh after new data syncs."
            await refresh()
        } catch {
            authorizationMessage = "Health access was not granted. Open Settings to allow Bechtel Fitness to read Health data."
        }
    }

    func exportWorkout(_ session: WorkoutSession) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: healthTypes)

        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let minutes = max(end.timeIntervalSince(start) / 60, 1)
        let estimatedCalories = max(45, minutes * 5.5)
        let energy = HKQuantity(unit: .kilocalorie(), doubleValue: estimatedCalories)
        let metadata: [String: Any] = [
            "BechtelFitnessTotalVolumeLbs": session.totalVolume,
            "BechtelFitnessCompletedSets": session.completedSetCount,
            "BechtelFitnessWorkoutName": session.name
        ]

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)

        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            let energySample = HKQuantitySample(type: energyType, quantity: energy, start: start, end: end)
            try await builder.addSamples([energySample])
        }

        try await builder.addMetadata(metadata)
        try await builder.endCollection(at: end)
        _ = try await finishWorkout(using: builder)
        session.healthKitExportedAt = Date()
    }

    func refresh() async {
        isRefreshing = true
        defer {
            isRefreshing = false
            lastUpdated = Date()
        }

        async let stepsValue = quantitySum(.stepCount, unit: .count(), start: Calendar.current.startOfDay(for: Date()))
        async let energyValue = quantitySum(.activeEnergyBurned, unit: .kilocalorie(), start: Calendar.current.startOfDay(for: Date()))
        async let sleepValue = sleepSinceYesterday()
        async let restingHeartRateValue = latestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrvValue = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let weightValue = latestQuantity(.bodyMass, unit: .pound())

        steps = await stepsValue
        activeEnergy = await energyValue
        sleepHours = await sleepValue
        restingHeartRate = await restingHeartRateValue
        hrv = await hrvValue
        weight = await weightValue
    }

    private var healthTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        [
            HKQuantityTypeIdentifier.stepCount,
            .activeEnergyBurned,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .bodyMass
        ].forEach { identifier in
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        return types
    }

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energyType)
        }
        return types
    }

    private func finishWorkout(using builder: HKWorkoutBuilder) async throws -> HKWorkout {
        try await withCheckedThrowingContinuation { continuation in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let workout {
                    continuation.resume(returning: workout)
                } else {
                    continuation.resume(throwing: HealthKitExportError.missingWorkout)
                }
            }
        }
    }

    private func quantitySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func sleepSinceYesterday() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let total = (samples as? [HKCategorySample])?
                    .filter { sample in
                        sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                        sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                        sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                        sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    }
                    .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0

                continuation.resume(returning: total > 0 ? total / 3600 : nil)
            }
            store.execute(query)
        }
    }

    private func formatNumber(_ value: Double?, fallback: String) -> String {
        guard let value else { return fallback }
        return NumberFormatter.localizedString(from: NSNumber(value: Int(value.rounded())), number: .decimal)
    }
}
