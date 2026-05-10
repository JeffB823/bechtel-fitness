import Foundation
import HealthKit

@MainActor
final class WatchWorkoutSessionManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func prepare() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate)
        let readTypes = Set([heartRate].compactMap { $0 })
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: readTypes) { _, _ in }
    }

    func startIfNeeded() {
        guard session == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            self.session = session
            self.builder = builder
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }
        } catch {
            self.session = nil
            self.builder = nil
        }
    }

    func end() {
        guard let session, let builder else { return }
        let endDate = Date()
        session.end()
        builder.endCollection(withEnd: endDate) { _, _ in
            builder.finishWorkout { _, _ in }
        }
        self.session = nil
        self.builder = nil
    }
}
