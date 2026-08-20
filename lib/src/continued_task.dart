import 'dart:async';
import 'package:flutter/foundation.dart';

import 'continued_task_platform_interface.dart';
import 'models/continued_task_config.dart';
import 'models/continued_task_state.dart';
import 'task_tracker.dart';

/// Controller for an active continued background task.
class ContinuedTask {
  ContinuedTask._({
    required this.config,
    this.onUserCancel,
    this.onTimeout,
    this.onAssertionChanged,
  }) {
    _initEventHandling();
  }

  /// Initial configuration provided when starting the task.
  final ContinuedTaskConfig config;

  /// Callback triggered when the user taps "Cancel" on system notifications or lock screen.
  void Function()? onUserCancel;

  /// Callback triggered when the OS terminates the task (e.g. Android 6h limit or iOS expiration).
  void Function()? onTimeout;

  /// Callback triggered when the OS process assertion is acquired (`held = true`) or lost (`held = false`).
  void Function(bool held)? onAssertionChanged;

  String get taskId => config.taskId;

  bool _isAssertionHeld = false;

  /// Whether the process assertion is currently active and held at the native level.
  bool get isAssertionHeld => _isAssertionHeld;

  bool _isStopped = false;

  /// Whether the task has already been stopped.
  bool get isStopped => _isStopped;

  // --- Async update serialization & coalescing ---
  _TaskUpdatePayload? _pendingUpdate;
  Future<void>? _activeUpdateJob;

  void _initEventHandling() {
    ContinuedTaskPlatform.instance.setEventHandlers(
      onEvent: (event) {
        switch (event) {
          case 'assertionAcquired':
            _setAssertionHeld(true);
            break;
          case 'assertionLost':
            _isAssertionHeld = false;
            onAssertionChanged?.call(false);
            break;
          case 'stopRequested':
            onUserCancel?.call();
            break;
          case 'timeout':
            _isAssertionHeld = false;
            onAssertionChanged?.call(false);
            onTimeout?.call();
            break;
        }
      },
    );
  }

  void _setAssertionHeld(bool held) {
    if (_isAssertionHeld != held) {
      _isAssertionHeld = held;
      onAssertionChanged?.call(held);
    }
  }

  /// Updates progress and metadata.
  /// 
  /// High-frequency calls (e.g. 100+ calls/sec) are automatically serialized
  /// and coalesced to prevent MethodChannel IPC saturation.
  Future<void> update({
    required int progress,
    int? maxProgress,
    String? title,
    String? subtitle,
  }) {
    if (_isStopped) return Future.value();

    _pendingUpdate = _TaskUpdatePayload(
      progress: progress,
      maxProgress: maxProgress ?? config.maxProgress,
      title: title,
      subtitle: subtitle,
    );

    _activeUpdateJob ??= _processUpdateQueue();
    return _activeUpdateJob!;
  }

  Future<void> _processUpdateQueue() async {
    while (_pendingUpdate != null && !_isStopped) {
      final payload = _pendingUpdate!;
      _pendingUpdate = null;

      try {
        await ContinuedTaskPlatform.instance.update(
          taskId: taskId,
          progress: payload.progress,
          maxProgress: payload.maxProgress,
          title: payload.title,
          subtitle: payload.subtitle,
        );
      } catch (e) {
        debugPrint('[ContinuedTask] Failed to update progress: $e');
      }
    }
    _activeUpdateJob = null;
  }

  /// Stops the task, releasing native assertions and clearing notifications.
  Future<void> stop() async {
    if (_isStopped) return;
    _isStopped = true;
    _pendingUpdate = null;

    try {
      await ContinuedTaskPlatform.instance.stop(taskId: taskId);
    } catch (e) {
      debugPrint('[ContinuedTask] Failed to stop task: $e');
    } finally {
      _setAssertionHeld(false);
    }
  }

  /// Dynamically updates event listeners.
  void setListeners({
    void Function()? onUserCancel,
    void Function()? onTimeout,
    void Function(bool held)? onAssertionChanged,
  }) {
    if (onUserCancel != null) this.onUserCancel = onUserCancel;
    if (onTimeout != null) this.onTimeout = onTimeout;
    if (onAssertionChanged != null) this.onAssertionChanged = onAssertionChanged;
  }

  @visibleForTesting
  void simulateEvent(String event) {
    switch (event) {
      case 'assertionAcquired':
        _setAssertionHeld(true);
        break;
      case 'assertionLost':
        _setAssertionHeld(false);
        break;
      case 'stopRequested':
        onUserCancel?.call();
        break;
      case 'timeout':
        _setAssertionHeld(false);
        onTimeout?.call();
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Static Entry Points & Task Management
  // ---------------------------------------------------------------------------

  static ContinuedTask? _currentTask;

  /// Whether continued tasks are supported on the current platform.
  static bool get isSupported => ContinuedTaskPlatform.instance.isSupported;

  /// The currently active task instance, or `null` if none.
  static ContinuedTask? get currentTask => _currentTask;

  /// Creates a [TaskTracker] that manages start, update, stop, and IPC
  /// coalescing automatically based on remaining task count changes.
  ///
  /// - Pass [title] for simple auto-formatting: `"$title ($done/$total)"`.
  /// - Pass [titleBuilder] for custom title formatting.
  /// - Pass [baseConfig] for static metadata (channel name, icon, taskId, etc.).
  static TaskTracker track({
    String title = 'Task in progress',
    String Function(int done, int total)? titleBuilder,
    String? subtitle,
    String Function(int done, int total)? subtitleBuilder,
    ContinuedTaskConfig baseConfig = const ContinuedTaskConfig(),
    ContinuedTaskConfig Function(int done, int total)? configBuilder,
    Future<void> Function()? onUserCancel,
    void Function()? onTimeout,
    void Function(bool held)? onAssertionChanged,
    bool autoSyncNativeState = true,
  }) {
    return TaskTracker(
      title: title,
      titleBuilder: titleBuilder,
      subtitle: subtitle,
      subtitleBuilder: subtitleBuilder,
      baseConfig: baseConfig,
      configBuilder: configBuilder,
      onUserCancel: onUserCancel,
      onTimeout: onTimeout,
      onAssertionChanged: onAssertionChanged,
      autoSyncNativeState: autoSyncNativeState,
    );
  }

  /// Starts a continued task manually and requests native process lifecycle continuation.
  /// 
  /// - Returns a `ContinuedTask` on success.
  /// - Returns `null` if rejected (e.g. background execution restrictions).
  static Future<ContinuedTask?> start({
    required ContinuedTaskConfig config,
    void Function()? onUserCancel,
    void Function()? onTimeout,
    void Function(bool held)? onAssertionChanged,
  }) async {
    // If an existing task is running, clean it up first
    if (_currentTask != null && !_currentTask!._isStopped) {
      await _currentTask!.stop();
    }

    final success = await ContinuedTaskPlatform.instance.start(config);
    if (!success) {
      return null;
    }

    final task = ContinuedTask._(
      config: config,
      onUserCancel: onUserCancel,
      onTimeout: onTimeout,
      onAssertionChanged: onAssertionChanged,
    );
    _currentTask = task;
    return task;
  }

  /// Syncs and retrieves the current native service state on app startup.
  static Future<ContinuedTaskNativeState?> syncNativeState() {
    return ContinuedTaskPlatform.instance.syncState();
  }

  /// Acknowledges and clears any pending stop request recorded on the native side.
  static Future<void> ackStopRequest() {
    return ContinuedTaskPlatform.instance.ackStopRequest();
  }

  /// Stops the currently running task (or cleans up any dangling native service).
  static Future<void> stopCurrentTask({String taskId = 'upload_task'}) async {
    if (_currentTask != null) {
      await _currentTask!.stop();
      _currentTask = null;
    } else {
      await ContinuedTaskPlatform.instance.stop(taskId: taskId);
    }
  }

  /// Resets global static state between unit tests.
  @visibleForTesting
  static void resetForTesting() {
    _currentTask = null;
  }
}

class _TaskUpdatePayload {
  _TaskUpdatePayload({
    required this.progress,
    required this.maxProgress,
    this.title,
    this.subtitle,
  });

  final int progress;
  final int maxProgress;
  final String? title;
  final String? subtitle;
}

/// Alias for backward compatibility with [ContinuedTask].
typedef FlutterContinuedTask = ContinuedTask;
