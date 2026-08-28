## 0.2.0

Concurrent tasks — two or more tasks can now run side by side, each with its own
notification, its own Cancel action and its own progress.

* **Existing apps need no changes.** Concurrency is opt-in via `allowConcurrent`
  on `ContinuedTask.start()` / `ContinuedTask.track()`. Left at its default
  (`false`), starting a task still stops whatever ran before it, exactly as in
  0.1.x.
* Events are now routed per task id. Previously a single global handler slot
  meant the most recently started task received every event — including the
  "Cancel" tap meant for another task's notification.
* Added `ContinuedTask.taskOf(taskId)`; `syncNativeState()` and
  `ackStopRequest()` take an optional `taskId`.
* `TaskTracker` scopes its cleanup to its own task id instead of stopping
  "whatever ran last".
* Platform interface gained `setTaskEventHandler`, `removeTaskEventHandler`,
  `syncStateFor` and `ackStopRequestFor`, all with default implementations that
  delegate to the 0.1.x methods. Implementations that **extend**
  `ContinuedTaskPlatform` (as the interface requires) keep compiling unchanged;
  only doubles that `implements` it need the new members.

Android:

* Four service components are now declared (`…Service`, `…ServiceSlot1..3`). A
  foreground service owns exactly one notification, so a task that wants its own
  notification and Cancel action needs its own component. A single-task app only
  ever uses slot 0 and its notification id is unchanged.
* Notification ids are per slot; Cancel intents are per component (extras are
  excluded from `PendingIntent` matching, so one component plus a task-id extra
  would have handed every notification the same intent).
* Swiping a notification away no longer resurrects it on the next progress
  update. Dismissal hides the notification; it is not a stop request — the
  Cancel action is. A new run posts a fresh notification again.
* `stop` now uses `startForegroundService`, which reaches a running service
  while the app is in the background; `startService` threw there and the task
  silently kept running.
* Stop requests recorded while the engine was detached are stored per task.

iOS:

* Tasks are tracked per `BGTaskScheduler` identifier instead of a single slot,
  so a second submission no longer finishes the first.
* Handlers are registered once per process. `BGTaskScheduler` kills the app on a
  second registration of the same identifier, which could happen whenever a
  second `FlutterEngine` was created.
* A task without an explicit `iosTaskIdentifier` is assigned the next free entry
  from `BGTaskSchedulerPermittedIdentifiers`, in declaration order. Previously
  the default was a name that was usually absent from that list, so submission
  always failed with `NotPermitted`.

Fixes found while testing on devices:

* Status bar icons no longer flicker with several tasks running. Every rebuild
  stamped a fresh `when`, and the status bar orders icons by it, so concurrent
  tasks kept swapping places. `when` is now fixed for the run and each slot
  carries a stable sort key.
* Progress updates no longer restart the service. They reach the running
  instance directly and refresh the notification, instead of re-entering the
  foreground state on every tick.

Verified on devices (Galaxy S21 / Android 15, iPhone / iOS 26.5):

* Two tasks run at once, each with its own notification and Cancel, and each
  cancel stops only its own task.
* Android keeps running through home, screen off and forced Doze.
* Android bundles the notifications at four or more, hiding the per-task Cancel
  inside the group — three concurrent tasks still show individually.
* iOS grants each task its own 900 s budget; Android shares one 6 h `dataSync`
  budget across the app.

Concurrency limits and shared budgets:

* Process lifetime and force-stop are **per app, not per task**. Splitting work
  into two tasks buys separate notifications and separate Cancel actions — not
  more background time.

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
