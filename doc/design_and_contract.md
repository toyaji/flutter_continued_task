# flutter_continued_task Architecture & Platform Contract

## 1. Overview

`flutter_continued_task` is a general-purpose Flutter plugin designed to keep long-running foreground-initiated tasks (such as large file batch uploads, database backups, on-device AI inference, video rendering) alive when the app moves to the background. It prevents OS process suspension and socket reclamation while synchronizing progress to system notifications and lock screens.

---

## 2. Platform Implementations

### 2.1 Android: `ForegroundService` (`dataSync`)
- **Lifecycle Continuation**: API 26+ `startForegroundService` / API 34+ `FOREGROUND_SERVICE_DATA_SYNC` type foreground service.
- **Notification UI**:
  - Ongoing progress bar (`setProgress`), sticky notification (`setOngoing(true)`), and activity launch intent.
  - Optional user cancel action button ("Cancel").
- **Timeout Protection**:
  - Catches `onTimeout` for Android 15+ 6h/24h `dataSync` limits, safely shutting down without `RemoteServiceException` crashes and notifying Dart of the `timeout` event.
- **Safe Start**:
  - Safely returns `false` instead of throwing `ForegroundServiceStartNotAllowedException` if the app is already in the background.

### 2.2 iOS: `BGContinuedProcessingTask` (iOS 26.0+)
- **Lifecycle Continuation**: Submits `BGContinuedProcessingTaskRequest` for tasks initiated in the foreground to keep the main Dart isolate and network connections alive.
- **Progress & Lock Screen UI**:
  - Exposes live progress to lock screens and Dynamic Island via `task.progress` and `task.updateTitle(_:subtitle:)`.
- **User Cancel vs. System Timeout**:
  - Differentiates active user cancellation (`stopRequested`) from OS resource expiration (`timeout`).
- **Compatibility Fallback (< iOS 26)**:
  - Gracefully returns `false` on unsupported iOS versions without crashing, allowing normal foreground execution.

---

## 3. Platform Interface Contract

### 3.1 MethodChannel Specification
- **Channel Name**: `io.github.toyaji.continued_task/channel`

#### Dart → Native (Methods)
| Method | Arguments | Return | Description |
| :--- | :--- | :--- | :--- |
| `start` | `taskId: String`<br>`title: String`<br>`subtitle: String?`<br>`initialProgress: Int`<br>`maxProgress: Int`<br>`indeterminate: Boolean`<br>`allowCancel: Boolean`<br>`cancelActionLabel: String?`<br>`notificationIcon: String?`<br>`channelId: String?`<br>`channelName: String?`<br>`iosTaskIdentifier: String?` | `Boolean` | Requests task start and process assertion. Returns `true` on success, `false` if rejected. |
| `update` | `taskId: String`<br>`progress: Int`<br>`maxProgress: Int?`<br>`title: String?`<br>`subtitle: String?` | `Boolean` | Updates progress and metadata. |
| `stop` | `taskId: String` | `void` | Stops task and releases native assertion. |
| `syncState` | None | `Map<String, dynamic>`<br>`{ assertionHeld: Boolean, stopRequested: Boolean }` | Syncs current native state on app startup. |
| `ackStopRequest` | None | `void` | Acknowledges and clears pending stop request flag on native side. |

#### Native → Dart (Events)
| Event | Arguments | Description |
| :--- | :--- | :--- |
| `assertionAcquired` | `null` | Native component has acquired process lifecycle assertion. |
| `assertionLost` | `null` | Native process assertion was released or lost. |
| `stopRequested` | `null` | User tapped "Cancel" on system notification or lock screen. |
| `timeout` | `null` | OS reclaimed task due to time limits (Android 6h) or resource constraints. |

---

## 4. High-Frequency Coalescing & Throttling

During rapid batch operations, calls to `update()` or `sync()` may occur tens of times per second.
The Dart layer in `flutter_continued_task` provides built-in async queue serialization and microtask coalescing to:
1. Minimize `MethodChannel` serialization overhead,
2. Prevent UI frame drops,
3. Guarantee that the final completion state (`progress == maxProgress`) is always delivered without data loss.

