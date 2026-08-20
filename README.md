# flutter_continued_task

[![pub package](https://img.shields.io/pub/v/flutter_continued_task.svg)](https://pub.dev/packages/flutter_continued_task)
[![Platform](https://img.shields.io/badge/platform-flutter%20%7C%20android%20%7C%20ios-blue.svg)](https://pub.dev/packages/flutter_continued_task)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A robust Flutter plugin to keep long-running tasks alive when the app moves to the background, preventing OS process suspension and socket reclamation while synchronizing progress to system notifications, lock screens, and Dynamic Island.

---

## 🌟 Why `flutter_continued_task`?

When a mobile app moves to the background during long-running tasks (such as photo/video batch uploads, file synchronization, database migrations, or on-device AI inference):
1. **OS Process Suspension**: iOS and Android rapidly suspend or kill background apps unless an ongoing task assertion or foreground service is explicitly held.
2. **High-Frequency IPC Thrashing**: Rapid progress events (e.g. enqueueing 10+ items synchronously) can flood Flutter's `MethodChannel` and flicker native notifications (`0/1 -> 0/2 -> ...`).
3. **Lifecycle Edge Cases**: Handling user cancel button taps on notifications, Android 6h `dataSync` timeouts, and app termination recovery requires complex boilerplate.

`flutter_continued_task` solves all of this with a **zero-boilerplate high-level API (`ContinuedTask.track`)** and a **flexible low-level API (`ContinuedTask.start`)**.

---

## ✨ Features

- 🛡️ **Guaranteed Process Continuation**: Prevents OS suspension and network reclamation in the background.
- 🤖 **Android `dataSync` Foreground Service**:
  - Ongoing system progress notifications (`setProgress`).
  - Native "Cancel" action button on notifications.
  - Automatic 6-hour timeout guard to prevent `RemoteServiceException`.
- 🍎 **iOS 26+ `BGContinuedProcessingTask`**:
  - Native lock screen and Dynamic Island progress tracking.
  - Swift Package Manager (SPM) & CocoaPods dual support.
- ⚡ **Automated High-Frequency Coalescing (`_drain`)**: Synchronous rapid updates are coalesced into a single IPC call, preventing "0/1" flicker and starting immediately with true batch totals (e.g. "0/9").
- 🔄 **Smart Batch Life-Cycle Management**:
  - `0 -> N`: Automatically requests OS process assertion & starts foreground service.
  - `N -> M`: Automatically updates progress.
  - `N -> 0`: Guarantees 100% completion update (`N/N`) before stopping the service.
  - Mid-flight additions: Automatically increments the batch total if new items are queued.
- 🔌 **Native State Recovery**: Automatically pulls native state (`assertionHeld`, `stopRequested`) on app cold start.

---

## 📱 Platform Support

| Platform | Install Target | **Active Background Continuation** | Underlying Mechanism |
| :--- | :--- | :--- | :--- |
| **Android** | Android 5.0+ (API 21+) | **Android 8.0+ (API 26+)** | `ForegroundService` (`dataSync`) with 6h guard |
| **iOS** | iOS 13.0+ | **iOS 26.0+** | `BGContinuedProcessingTask` & Lock Screen Progress |

> **Note on Compatibility**: Below runtime minimums (e.g. iOS < 26.0), `ContinuedTask.start()` gracefully returns `false` / no-op without throwing errors, letting tasks run normally in the foreground and pause naturally in the background.

---

## 📦 Installation

Add `flutter_continued_task` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_continued_task: ^0.1.0
```

---

## 🛠️ Platform Setup

### 1. Android Setup

Add the required foreground service permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required for Android 9+ (API 28+) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <!-- Required for Android 14+ (API 34+) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <!-- Required for Android 13+ (API 33+) Notification Permission -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application ...>
        <!-- flutter_continued_task Foreground Service is auto-manifest-merged! -->
    </application>
</manifest>
```

### 2. iOS Setup

iOS requires `BGContinuedProcessingTask` permitted identifiers in `ios/Runner/Info.plist`:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>your.bundle.id.upload</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>
```

---

## 🚀 Quickstart

### Approach 1: High-Level API (`ContinuedTask.track`) — *Recommended*

The easiest and most robust way. Create a tracker once, then simply call `tracker.sync(remainingCount)` whenever your queue changes. Everything else is automated:

```dart
import 'package:flutter_continued_task/flutter_continued_task.dart';

class UploadService {
  late final TaskTracker _tracker;

  void initialize() {
    _tracker = ContinuedTask.track(
      configBuilder: (done, total) => ContinuedTaskConfig(
        taskId: 'upload_task',
        title: total > 0 ? 'Uploading Photos ($done/$total)' : 'Uploading Photos',
        subtitle: total > 0 ? '$done/$total' : null,
        initialProgress: done,
        maxProgress: total.clamp(1, 999999),
        allowCancel: true,
        cancelActionLabel: 'Cancel',
        androidNotificationIcon: 'upload', // Built-in: 'upload', 'download', 'sync', 'processing'
        androidChannelId: 'upload_progress',
        androidChannelName: 'Upload Progress',
        iosTaskIdentifier: 'your.bundle.id.upload',
      ),
      onUserCancel: () async {
        print('User tapped cancel on notification!');
        // Pause or cancel your internal upload queue
      },
      onTimeout: () {
        print('OS timeout reached (Android 6h limit)');
      },
      onAssertionChanged: (held) {
        print('OS assertion active: $held');
      },
    );
  }

  /// Call this whenever your pending queue count changes:
  /// - 0 -> 9: Starts foreground task as "0/9" (no "0/1" flicker)
  /// - 9 -> 8: Updates progress to "1/9"
  /// - 1 -> 0: Sends final "9/9" update and automatically stops task
  Future<void> onQueueUpdated(int remainingCount) {
    return _tracker.sync(remainingCount);
  }

  void dispose() {
    _tracker.dispose();
  }
}
```

---

### Approach 2: Low-Level API (`ContinuedTask.start`)

If you want full manual control over start, update, and stop:

```dart
import 'package:flutter_continued_task/flutter_continued_task.dart';

// 1. Check platform support
if (!ContinuedTask.isSupported) return;

// 2. Start manual task
final task = await ContinuedTask.start(
  config: const ContinuedTaskConfig(
    taskId: 'custom_task_1',
    title: 'Processing Video',
    maxProgress: 100,
    allowCancel: true,
    iosTaskIdentifier: 'your.bundle.id.upload',
  ),
  onUserCancel: () => print('User canceled'),
  onTimeout: () => print('Timed out'),
  onAssertionChanged: (held) => print('Assertion: $held'),
);

// 3. Update progress (automatically serialized and throttled)
await task?.update(progress: 45, maxProgress: 100, subtitle: '45%');

// 4. Stop when finished
await task?.stop();
```

---

## 🧪 Comprehensive Testing

This package includes a standalone unit & integration test suite covering all lifecycle and concurrency scenarios:

```bash
cd packages/flutter_continued_task
flutter test
```

You can also run the interactive test dashboard in `packages/flutter_continued_task/example` to visually test rapid batch coalescing, mid-flight additions, and notification cancel actions on an emulator or real device.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
