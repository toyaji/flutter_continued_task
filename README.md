# flutter_continued_task

A powerful Flutter plugin designed to keep long-running tasks alive when the app moves to the background, preventing OS suspension and network reclamation while synchronizing progress to system notifications and the lock screen.

---

## 🌟 Features

- **Process Lifecycle Continuation**: Keeps the app process and network connections active when transitioned to the background.
- **Android `dataSync` Foreground Service**:
  - Ongoing low-priority progress notifications (`setProgress`).
  - Optional user cancel action button ("중단").
  - Automated 6-hour timeout guard (`onTimeout`) to prevent `RemoteServiceException`.
- **iOS 26+ `BGContinuedProcessingTask`**:
  - Native lock screen and Dynamic Island progress tracking.
  - Distinguishes user cancellation from system resource expiration.
- **Coalescing & Throttling Queue**: Automatically serializes high-frequency progress updates (up to 100+ updates/sec) to avoid MethodChannel overhead while guaranteeing final progress delivery.
- **Generic & Unopinionated**: Works seamlessly with large file uploads, local database backups, on-device AI inference, video rendering, and more.

---

## 📦 Installation

Add `flutter_continued_task` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_continued_task: ^0.1.0
```

---

## 🛠️ iOS Setup

iOS requires `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes` declared in `ios/Runner/Info.plist`. You can configure this automatically using the built-in CLI:

```bash
# Run from the root of your Flutter project:
dart run flutter_continued_task:setup your.custom.task.identifier
```

---

## 🚀 Usage

### 1. Start a Continued Task

Start a task while the app is in the foreground (e.g., when the user initiates an upload or backup):

```dart
import 'package:flutter_continued_task/flutter_continued_task.dart';

final task = await FlutterContinuedTask.start(
  config: const ContinuedTaskConfig(
    taskId: 'upload_batch_1',
    title: 'Uploading Photos',
    subtitle: '0 / 10',
    initialProgress: 0,
    maxProgress: 10,
    allowCancel: true,
    cancelActionLabel: 'Cancel',
    // Built-in presets: 'upload', 'download', 'sync', 'processing'
    // Or pass your custom drawable name (e.g. 'ic_my_custom_icon')
    androidNotificationIcon: 'upload',
    androidChannelId: 'upload_progress',
    androidChannelName: 'Photo Upload',
    iosTaskIdentifier: 'co.zelly.flutter.upload',
  ),
  onUserCancel: () {
    print('User tapped cancel on system notification');
    // Pause or hold your work queue
  },
  onTimeout: () {
    print('OS time limit reached (Android 6h or iOS expiration)');
    // Defer remaining work for next app launch
  },
  onAssertionChanged: (held) {
    print('OS lifecycle assertion held: $held');
  },
);
```

### 2. Update Progress

Progress updates are automatically coalesced and serialized. You can safely call this in high-frequency loops:

```dart
await task?.update(
  progress: 3,
  maxProgress: 10,
  title: 'Uploading Photos (3/10)',
  subtitle: '3 / 10',
);
```

### 3. Stop the Task

When the operation finishes, stop the task to release native resources and dismiss the notification:

```dart
await task?.stop();
```

### 4. Sync Native State on App Launch

If the app was terminated while the background service was running, pull the native fact on next app startup:

```dart
final state = await FlutterContinuedTask.syncNativeState();
if (state != null) {
  if (state.assertionHeld) {
    print('Service is still running in the background');
  }
  if (state.stopRequested) {
    print('User requested stop while app was detached');
    await FlutterContinuedTask.ackStopRequest();
  }
}
```

---

## 📚 Platform Support

| Platform | Min OS Version | Mechanism |
| :--- | :--- | :--- |
| **Android** | Android 8.0+ (API 26+) | `ForegroundService` (`dataSync` with 6h timeout guard) |
| **iOS** | iOS 26.0+ | `BGContinuedProcessingTask` & Lock Screen Progress |

---

## 🧪 Testing

This package includes a full standalone test suite:

```bash
cd packages/flutter_continued_task
flutter test
```
