# Bechtel Fit Watch App

This folder contains the watchOS companion app source.

- Mirror the active iPhone workout set on Apple Watch.
- Log or skip the current set from the watch without changing the underlying workout programming.
- Start a `HKWorkoutSession` so the workout indicator shows and heart-rate capture can run while the iPhone remains the source of truth.

The watch app is intentionally narrow: the iPhone owns workout definitions, schedule, progression, and saved workout history. The watch app is the live companion surface.

## Companion Architecture

- The iPhone app sends the current exercise, set progress, target weight, target reps, and rest timer over `WatchConnectivity`.
- The watch app renders that live state and sends back actions like `Log Set` and `Skip Set`.
- The iPhone app applies those actions to the real live workout session, then publishes the updated state back to the watch.

This keeps the workout programming in one place and avoids creating a second workout engine on the watch.

## Running on Your Watch

1. Open `BechtelFitness.xcodeproj` in Xcode.
2. Go to Xcode > Settings > Accounts and make sure your Apple ID is added.
3. Select the project, then select the `BechtelFitnessWatch` target.
4. Open Signing & Capabilities and select your Apple ID team.
5. Keep Automatically manage signing enabled so Xcode creates the Watch provisioning profile.
6. Select the `BechtelFitnessWatch` scheme.
7. Select your paired Apple Watch as the run destination.
8. Press Run.

If Xcode says there are no profiles for `com.jeffbechtel.BechtelFitness.watchkitapp`, let Xcode create the provisioning profile from Signing & Capabilities. If the watch destination is ineligible and the watchOS version looks blank, unlock the watch, keep it near the iPhone, and reopen Xcode after the watch finishes pairing with Developer Mode enabled.

The watch target currently supports `watchOS 10.0+`, which matches Jeff's Apple Watch on `watchOS 10.6.2`.

## Developer Mode Checklist

Apple requires Developer Mode for running development-signed apps from Xcode. On watchOS 10, the final location is Apple Watch Settings > Privacy & Security > Developer Mode.

If Developer Mode is missing on the watch:

1. Connect the paired iPhone to the Mac with USB and unlock both iPhone and Apple Watch.
2. In Xcode, open Window > Devices and Simulators.
3. Select the iPhone and wait for the Apple Watch to appear under Paired Watches.
4. Fix any yellow warning shown for the iPhone or watch.
5. Select the `BechtelFitnessWatch` scheme and press Run once.
6. If Xcode shows a Developer Mode warning, cancel it.
7. On the watch, check Settings > Privacy & Security > Developer Mode again.
8. Turn Developer Mode on, restart when prompted, then tap Turn On after reboot.

Apple notes that Developer Mode may not appear until you begin pairing or try running from Xcode for the first time.

## Connection Troubleshooting

For Apple Watch Series 5 or older, Xcode needs the Mac, iPhone, and Apple Watch on the same Bonjour-compatible Wi-Fi network. If the Mac is only on Ethernet or another network, Xcode may show the watch as paired but fail to read watchOS, leaving the watch ineligible or causing install timeouts.

If install times out:

1. Connect the Mac to the same Wi-Fi network as the iPhone and Apple Watch.
2. Keep Bluetooth enabled on the Mac and iPhone.
3. Keep the iPhone connected to the Mac by USB.
4. Unlock the iPhone and keep the Apple Watch awake/unlocked near the iPhone.
5. Run `xcrun devicectl manage pair --device A0A50509-D692-5DFE-B241-18CBBFD92BEB`, then run the Watch scheme again.

## Known Failure Modes

1. The watch app opens but stays on a waiting screen:
   - make sure the iPhone app is in an active live workout
   - keep both apps in the foreground the first time
   - confirm the phone build includes the latest `WatchConnectivity` changes

2. Watch button taps do nothing:
   - confirm the watch is reachable in the iPhone app session
   - unlock both devices and retry with the apps foregrounded
   - rerun the iPhone app if the connectivity session activated before the watch was available

3. Xcode can build for simulator but not install on hardware:
   - verify Signing & Capabilities on both the iPhone and watch targets
   - enable Developer Mode on both devices
   - keep the iPhone connected by USB during first install
