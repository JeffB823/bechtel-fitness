import Foundation

enum NativeProgramStore {
    static func bundledSnapshot(now: Date = .now) -> WorkoutEngineSnapshot? {
        guard let url = Bundle.main.url(forResource: "ProgramData", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        do {
            var snapshot = try JSONDecoder().decode(WorkoutEngineSnapshot.self, from: data)
            if snapshot.settings.startDate.isEmpty {
                snapshot.settings.startDate = storageDateKey(for: now)
            }
            return snapshot
        } catch {
            assertionFailure("ProgramData.json failed to decode: \(error)")
            return nil
        }
    }

    static func fallbackSettings(now: Date = .now) -> WorkoutEngineSettings {
        WorkoutEngineSettings(
            startDate: storageDateKey(for: now),
            currentPhase: 1,
            currentDayIndex: 0
        )
    }
}

private func storageDateKey(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
