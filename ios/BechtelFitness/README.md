# Bechtel Fitness iOS App

This is a native iPhone app wrapper for the Bechtel Fitness workout site with a Health tab powered by Apple HealthKit.

## Native Training Features

- `Train` tab stores local SwiftData workouts, templates, exercises, sets, and exercise history.
- Progressive overload is keyed by exercise ID. If every working set hits target reps, the next session pre-fills +5 lb for upper-body exercises and +10 lb for lower-body exercises.
- Sets store target reps/weight/RPE separately from actual reps/weight/RPE.
- Finishing a workout updates local exercise history and exports a strength-training `HKWorkout` to Apple Health with total-volume metadata.
- Live workouts include large current-set controls, swipe-up to log, swipe-left to skip, rest notifications, haptics, and Live Activity update hooks.
- `WatchCompanion/` contains the watchOS companion app. It mirrors the active set from the iPhone live workout and sends watch actions back to the iPhone without changing the underlying workout programming.

## Run On Your iPhone

1. Open `BechtelFitness.xcodeproj` in Xcode.
2. In Xcode, go to `Settings > Accounts` and add your Apple ID if it is not already there.
3. Select the `BechtelFitness` project in the left sidebar, then select the `BechtelFitness` target.
4. Open `Signing & Capabilities` and choose your Apple ID under `Team`.
5. Connect your iPhone with a cable and tap `Trust This Computer` if prompted.
6. In the device picker near the Run button, choose your iPhone.
7. Press `Run`.
8. On first launch, allow the requested Health permissions so the Health tab can show steps, calories, sleep, heart rate, HRV, and weight.

If iOS blocks the app the first time, open `Settings > General > VPN & Device Management` on the phone and trust your developer profile.

Free Apple developer accounts can install apps on your own device, but Apple may require you to rebuild/reinstall periodically.
