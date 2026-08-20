import 'dart:async';

import 'continued_task.dart';
import 'models/continued_task_config.dart';

/// Tracks progress and synchronizes background task lifecycle (`start`/`update`/`stop`) automatically.
///
/// - Automatically coalesces rapid high-frequency calls (e.g. loops emitting `sync`) into a single IPC call
/// - Automatically calls `start` when count transitions from `0 -> N`
/// - Automatically calls `update` when count changes from `N -> M`
/// - Guarantees 100% progress update (`N/N`) and calls `stop` when count reaches `0`
/// - Automatically increments the batch total if new items are added mid-flight
class TaskTracker {
  /// Creates a [TaskTracker] and sets up initial state.
  ///
  /// - Pass [title] for simple auto-formatting: `"$title ($done/$total)"`.
  /// - Pass [titleBuilder] for custom title formatting.
  /// - Pass [baseConfig] for static metadata (channel name, icon, taskId, etc.).
  TaskTracker({
    this.title = 'Task in progress',
    this.titleBuilder,
    this.subtitle,
    this.subtitleBuilder,
    this.baseConfig = const ContinuedTaskConfig(),
    ContinuedTaskConfig Function(int done, int total)? configBuilder,
    this.onUserCancel,
    this.onTimeout,
    this.onAssertionChanged,
    bool autoSyncNativeState = true,
  }) : _configBuilder = configBuilder {
    if (autoSyncNativeState) {
      unawaited(syncNativeState());
    }
  }

  /// Default title prefix or text used when [titleBuilder] is not provided.
  final String title;

  /// Custom title builder receiving (done, total).
  final String Function(int done, int total)? titleBuilder;

  /// Subtitle displayed on notifications.
  final String? subtitle;

  /// Custom subtitle builder receiving (done, total).
  final String Function(int done, int total)? subtitleBuilder;

  /// Base static configuration (channel name, icon, taskId, iosTaskIdentifier, etc.).
  final ContinuedTaskConfig baseConfig;

  /// Optional full configuration builder (kept for advanced usage / backward compatibility).
  final ContinuedTaskConfig Function(int done, int total)? _configBuilder;

  /// Callback triggered when the user taps "Cancel" on system notifications.
  final Future<void> Function()? onUserCancel;

  /// Callback triggered on OS timeout (e.g. Android 6-hour limit).
  final void Function()? onTimeout;

  /// Callback triggered when OS process assertion status changes (`held = true/false`).
  final void Function(bool held)? onAssertionChanged;

  // ---------------------------------------------------------------------------
  // Public Properties
  // ---------------------------------------------------------------------------

  ContinuedTask? _activeTask;
  bool _submitted = false;

  /// Whether a start request has been submitted (not necessarily acquired yet).
  bool get isSubmitted => _submitted;

  int _batchTotal = 0;

  /// Total number of items in the current batch.
  int get batchTotal => _batchTotal;

  int _lastUnfinished = 0;
  int? _requested;
  Future<void>? _flush;
  bool _isDisposed = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Synchronizes the current remaining (unfinished) item count with the tracker.
  ///
  /// - `unfinished > 0`: Calls `start` if no active task, or `update` if already running.
  /// - `unfinished <= 0`: Sends final 100% completion update and stops the task.
  ///
  /// Rapid consecutive calls are coalesced into a single microtask execution.
  Future<void> sync(int unfinished) {
    if (_isDisposed) return Future.value();
    _requested = unfinished;
    return _flush ??= Future.microtask(_drain);
  }

  /// Synchronizes and recovers native service state on app startup if needed.
  Future<void> syncNativeState() async {
    if (!ContinuedTask.isSupported || _isDisposed) return;
    final state = await ContinuedTask.syncNativeState();
    if (state == null) return;

    final serviceRunning = state.assertionHeld;
    onAssertionChanged?.call(serviceRunning);

    if (serviceRunning && !_submitted) {
      _submitted = true;
      unawaited(sync(_lastUnfinished));
    }

    if (state.stopRequested) {
      await onUserCancel?.call();
      await ContinuedTask.ackStopRequest();
    }
  }

  /// Disposes the tracker and stops any running task.
  Future<void> dispose() async {
    _isDisposed = true;
    _requested = null;
    if (_activeTask != null) {
      await _activeTask!.stop();
      _activeTask = null;
    }
    _submitted = false;
    _resetBatch();
  }

  // ---------------------------------------------------------------------------
  // Private Pipeline
  // ---------------------------------------------------------------------------

  Future<void> _drain() async {
    try {
      while (_requested != null && !_isDisposed) {
        final value = _requested!;
        _requested = null;
        await _performSync(value);
      }
    } finally {
      _flush = null;
    }
  }

  Future<void> _performSync(int unfinished) async {
    if (!ContinuedTask.isSupported || _isDisposed) return;

    if (unfinished <= 0) {
      if (_submitted) {
        if (_batchTotal > 0) {
          await _updateProgress(done: _batchTotal, total: _batchTotal);
        }
        _submitted = false;
        if (_activeTask != null) {
          await _activeTask!.stop();
          _activeTask = null;
        } else {
          await ContinuedTask.stopCurrentTask();
        }
      }
      _resetBatch();
      return;
    }

    if (unfinished > _lastUnfinished) {
      _batchTotal += unfinished - _lastUnfinished;
    }
    _lastUnfinished = unfinished;
    final done = (_batchTotal - unfinished).clamp(0, _batchTotal);

    if (!_submitted) {
      final config = _buildConfig(done, _batchTotal.clamp(1, 999999));
      _activeTask = await ContinuedTask.start(
        config: config,
        onUserCancel: () => onUserCancel?.call(),
        onTimeout: () {
          _submitted = false;
          _activeTask = null;
          _resetBatch();
          onTimeout?.call();
        },
        onAssertionChanged: (held) {
          if (!held) {
            _submitted = false;
            _activeTask = null;
          }
          onAssertionChanged?.call(held);
        },
      );
      _submitted = _activeTask != null;
      if (!_submitted) onAssertionChanged?.call(false);
      return;
    }

    await _updateProgress(done: done, total: _batchTotal);
  }

  Future<void> _updateProgress({required int done, required int total}) async {
    if (_activeTask != null && !_isDisposed) {
      final config = _buildConfig(done, total.clamp(1, 999999));
      await _activeTask!.update(
        progress: done,
        maxProgress: total.clamp(1, 999999),
        title: config.title,
        subtitle: config.subtitle,
      );
    }
  }

  ContinuedTaskConfig _buildConfig(int done, int total) {
    if (_configBuilder != null) {
      return _configBuilder!(done, total);
    }

    final resolvedTitle = titleBuilder != null
        ? titleBuilder!(done, total)
        : (total > 0 ? '$title ($done/$total)' : title);

    final resolvedSubtitle = subtitleBuilder != null
        ? subtitleBuilder!(done, total)
        : (subtitle ?? (total > 0 ? '$done/$total' : null));

    return baseConfig.copyWith(
      title: resolvedTitle,
      subtitle: resolvedSubtitle,
      initialProgress: done,
      maxProgress: total.clamp(1, 999999),
    );
  }

  void _resetBatch() {
    _batchTotal = 0;
    _lastUnfinished = 0;
  }
}
