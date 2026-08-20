# flutter_continued_task_example

An interactive dashboard for exercising `flutter_continued_task` on a real device
or emulator.

```bash
cd example
flutter run
```

## What it demonstrates

- **Simulated upload queue** — start a batch, then add items mid-flight to see
  `TaskTracker.sync()` coalesce rapid changes into a single native update.
- **Progress notification** — live title/progress on the Android notification and
  the iOS 26 Lock Screen.
- **User cancel** — the notification's cancel action routed back into Dart via
  `onUserCancel`.
- **Lifecycle survival** — background the app, lock the screen, or swipe the app
  away and watch how the native assertion is held or released.
- **Unsupported platforms** — `ContinuedTask.isSupported` reporting `false` with
  the work still running normally in the foreground.

## Requirements

- Android: `minSdk 26` (already set in `android/app/build.gradle.kts`)
- iOS: Xcode 26 / iOS 26 SDK to build; background continuation is active on
  iOS 26+ devices only. The task identifier is declared in
  `ios/Runner/Info.plist` and must stay prefixed with the app's bundle ID.
