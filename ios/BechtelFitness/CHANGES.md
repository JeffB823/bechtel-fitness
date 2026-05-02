# iPhone UX Overhaul

## Design Tokens

Before: iOS views mixed local padding, radius, opacity, and button styling values.

After: shared spacing, radius, touch-size, dark-text, and button style tokens live in `AppTheme+Tokens.swift`, with primary, secondary, and ghost button styles available to native SwiftUI surfaces.

## Bottom Navigation

Before: the Workout hub used a top capsule navigation pattern that felt closer to a web page.

After: Home, Workout, Program, Progress, and Health are now exposed through a native bottom `TabView`. WOD now lives inside Program as a segmented sub-tab.

## Home Quick Start

Before: starting the current workout was lower in the Home hierarchy.

After: Home now leads with a "Start Today's Workout" action and shows the current programmed day, or "Rest day" when no day is available.

## Instant Cold Start

Before: native screens waited for the hosted web app to hydrate before showing training data.

After: the latest snapshot is cached in Application Support and restored on launch when it is under 200 KB, so native views can render immediately while the web bridge refreshes in the background.

## Live Workout Polish

Before: logging leaned on gestures and dense stepper-style controls.

After: live workout logging has persistent bottom actions, a rest timer ring, add-set support, haptics, clear set context, and large bumper controls for weight, reps, and RPE.

## Empty States And Copy

Before: first-run progress/history states were plain explanatory text.

After: empty states now include a primary "Start your first workout" action, and loading/error copy is more direct.

## Scope Guardrails

The web app URL, snapshot wire format, workout programming rules, progression logic, Codable snapshot models, and WatchCompanion files were left unchanged.
