import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_continued_task.dart';
import 'models/continued_task_config.dart';
import 'models/continued_task_state.dart';

/// The platform interface every `flutter_continued_task` implementation extends.
///
/// Platform implementations must extend this class rather than implement it, so
/// that newly added methods do not break existing subclasses.
abstract class ContinuedTaskPlatform extends PlatformInterface {
  /// Constructs a platform implementation with the shared verification token.
  ContinuedTaskPlatform() : super(token: _token);

  static final Object _token = Object();

  static ContinuedTaskPlatform _instance = MethodChannelContinuedTask();

  /// The implementation currently in use, defaulting to the method channel one.
  static ContinuedTaskPlatform get instance => _instance;

  /// Replaces the active implementation, e.g. with a fake in tests.
  static set instance(ContinuedTaskPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether continued background execution is supported on the current platform.
  bool get isSupported => false;

  /// Requests to start a continued task. Returns true on success, false if rejected.
  Future<bool> start(ContinuedTaskConfig config) {
    throw UnimplementedError('start() has not been implemented.');
  }

  /// Updates progress and metadata.
  Future<bool> update({
    required String taskId,
    required int progress,
    int? maxProgress,
    String? title,
    String? subtitle,
  }) {
    throw UnimplementedError('update() has not been implemented.');
  }

  /// Stops the task and clears native foreground resources.
  Future<void> stop({required String taskId, bool success = true}) {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// Requests notification permission from the user (POST_NOTIFICATIONS on Android 13+, UNUserNotificationCenter on iOS).
  Future<bool> requestNotificationPermission() {
    throw UnimplementedError(
        'requestNotificationPermission() has not been implemented.');
  }

  /// Syncs and retrieves native state.
  Future<ContinuedTaskNativeState?> syncState() {
    throw UnimplementedError('syncState() has not been implemented.');
  }

  /// Clears the acknowledged stop request flag on the native side.
  Future<void> ackStopRequest() {
    throw UnimplementedError('ackStopRequest() has not been implemented.');
  }

  /// Registers native lifecycle event handlers.
  void setEventHandlers({
    required void Function(String event) onEvent,
  }) {
    throw UnimplementedError('setEventHandlers() has not been implemented.');
  }
}
