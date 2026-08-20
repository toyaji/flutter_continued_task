## 0.1.0

* Initial release.
* Android: foreground service (`FOREGROUND_SERVICE_DATA_SYNC`) with progress notification,
  user cancel action, and zero-config manifest merging.
* iOS 26+: `BGContinuedProcessingTask` submission, progress updates, and expiration handling
  with a safe no-op fallback on earlier versions.
* `TaskTracker` high-level API (`ContinuedTask.track`) — a single `sync(remaining)` call drives
  start/update/stop, progress formatting, and IPC coalescing.
* `titleBuilder` / `subtitleBuilder` / `configBuilder` for custom notification text.
* `ContinuedTask.requestNotificationPermission()` helper for Android 13+.
* `dart run flutter_continued_task:setup` CLI to configure `ios/Runner/Info.plist`.
