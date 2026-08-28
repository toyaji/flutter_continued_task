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
| **Android** | Android 8.0+ (API 26+) | **Android 8.0+ (API 26+)** | `ForegroundService` (`dataSync`) with 6h guard |
| **iOS** | iOS 13.0+ | **iOS 26.0+** | `BGContinuedProcessingTask` & Lock Screen Progress |

> **Note on Compatibility**: Below runtime minimums (e.g. iOS < 26.0), `ContinuedTask.start()` gracefully returns `false` / no-op without throwing errors, letting tasks run normally in the foreground and pause naturally in the background. This fallback is **runtime-only**: building the iOS side requires **Xcode 26 / the iOS 26 SDK**, and your Android module must set `minSdkVersion 26` or higher.


---

## 📦 Installation

Add `flutter_continued_task` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_continued_task: ^0.2.0
```

---

## 🛠️ Platform Setup

### 1. Android Setup (Zero-Config 🎉)

**No manual `AndroidManifest.xml` edits required!**  
All required permissions (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`) and the foreground service component are **automatically merged** into your final APK/AAB during the build.

> **Tip for Android 13+ (API 33+)**:  
> Progress notifications require runtime notification permission. The package ships a helper, so no extra dependency is needed:
>
> ```dart
> final granted = await ContinuedTask.requestNotificationPermission();
> ```
>
> It returns `true` immediately on iOS and on Android below API 33.

---

### 2. iOS Setup

#### Option A: Automatic CLI Setup (Recommended ⚡)
Run the built-in setup script from your project root to automatically configure `ios/Runner/Info.plist`:

```bash
dart run flutter_continued_task:setup
```

#### Option B: Manual Setup
Add `UIBackgroundModes` with `processing` and your task identifier to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <!-- Must be prefixed with your app's bundle identifier. -->
    <string>com.your.bundle.id.continued_task</string>
</array>
```

---

## 🚀 Quickstart

### Approach 1: High-Level API (`ContinuedTask.track`) — *Recommended*

The easiest and most robust way. Create a tracker once, then simply call `tracker.sync(remainingCount)` whenever your queue changes. Everything else (lifecycle start/update/stop, progress calculation, microtask IPC coalescing) is completely automated.

#### 1. Minimal (1-liner with auto progress formatting)
```dart
final tracker = ContinuedTask.track(
  title: 'Uploading Photos', // Auto-formats to "Uploading Photos (done/total)"
  onUserCancel: () => cancelUploads(),
);
```

#### 2. Custom Title Formatting (`titleBuilder`)
```dart
final tracker = ContinuedTask.track(
  titleBuilder: (done, total) => '$done of $total photos uploaded',
  onUserCancel: () => cancelUploads(),
);
```

#### 3. Custom Metadata & Notifications (`baseConfig`)
```dart
import 'package:flutter_continued_task/flutter_continued_task.dart';

class UploadService {
  late final TaskTracker _tracker;

  void initialize() {
    _tracker = ContinuedTask.track(
      title: 'Uploading Photos',
      baseConfig: const ContinuedTaskConfig(
        androidNotificationIcon: 'upload', // Built-in: 'upload', 'download', 'sync', 'processing'
        androidChannelName: 'Photo Uploads',
      ),
      onUserCancel: () async {
        print('User tapped cancel on notification!');
        // Stop or pause your internal work queue
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
  /// - 1 -> 0: Sends final "9/9" update and automatically stops task (100% completed)
  Future<void> onQueueUpdated(int remainingCount) {
    return _tracker.sync(remainingCount);
  }

  /// Call this when the user cancels or aborts the entire batch mid-flight:
  Future<void> cancelQueue() {
    return _tracker.cancel();
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

## 🔀 Concurrent Tasks

Need two progress notifications at once — say photo uploads and video uploads —
each with its own Cancel button? Set `allowConcurrent: true` and give each task
its own `taskId`:

```dart
final photos = ContinuedTask.track(
  title: 'Uploading photos',
  allowConcurrent: true,
  baseConfig: const ContinuedTaskConfig(taskId: 'photos'),
  onUserCancel: () async => photoQueue.stop(),
);

final videos = ContinuedTask.track(
  title: 'Uploading videos',
  allowConcurrent: true,
  baseConfig: const ContinuedTaskConfig(taskId: 'videos'),
  onUserCancel: () async => videoQueue.stop(),
);
```

Each task shows its own notification, and its Cancel button only stops that
task. `onUserCancel` fires on the task the user actually cancelled.

**Without `allowConcurrent`, starting a task stops the running one** — the
default, and what single-task apps want.

### iOS: one identifier per task

Add an entry to `BGTaskSchedulerPermittedIdentifiers` for each task you run at
the same time (`dart run flutter_continued_task:setup` writes the first one):

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.example.app.task</string>
    <string>com.example.app.task_02</string>
</array>
```

Identifiers are handed out in the order they appear, so you don't need to set
`iosTaskIdentifier` yourself. Android needs no setup.

### Good to know

- **Up to 4 tasks at a time.** Android shows at most 3 notifications
  individually; from the 4th the system collapses them into a group and each
  Cancel button moves inside it.
- **Concurrency doesn't buy more background time.** Two tasks get you two
  notifications and two Cancel buttons, not a longer runtime — the OS budget
  belongs to the app.
- **If notifications are turned off**, work still runs, but there is no Cancel
  button to show. Keep a way to stop it inside your app.

---

## ⚙️ Configuration Reference (`ContinuedTaskConfig`)

All properties have sensible defaults and are completely optional:

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `title` | `String` | `'Task in progress'` | Main title displayed on notifications and lock screen. |
| `subtitle` | `String?` | `null` | Secondary text or description. |
| `allowCancel` | `bool` | `true` | Displays a user "Cancel" action button on the system notification. |
| `cancelActionLabel`| `String` | `'Cancel'` | Action button text. |
| `androidNotificationIcon` | `String?` | `null` | Android notification icon resource or keyword (`'upload'`, `'download'`, `'sync'`, `'processing'`). |
| `androidChannelId` | `String` | `'continued_task_channel'` | Android notification channel ID. |
| `androidChannelName` | `String` | `'Background Task'` | Android notification category name in OS settings. |
| `androidChannelDescription` | `String` | `'Shows ongoing progress...'` | Android notification channel description. |
| `iosTaskIdentifier`| `String?` | `null` | iOS `BGContinuedProcessingTask` ID (must match `Info.plist`). Leave null to take the next free permitted identifier. |
| `indeterminate` | `bool` | `false` | Shows an indeterminate spinner instead of a progress bar. |

---

## 🧪 Comprehensive Testing

This package includes a standalone unit & integration test suite covering all lifecycle and concurrency scenarios:

```bash
flutter test
```

You can also run the interactive test dashboard in `example/` (`cd example && flutter run`) to visually test rapid batch coalescing, mid-flight additions, and notification cancel actions on an emulator or real device.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
