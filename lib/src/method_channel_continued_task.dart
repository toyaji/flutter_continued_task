import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'continued_task_platform_interface.dart';
import 'models/continued_task_config.dart';
import 'models/continued_task_state.dart';

/// The default [ContinuedTaskPlatform] implementation, backed by a [MethodChannel].
class MethodChannelContinuedTask extends ContinuedTaskPlatform {
  @override
  bool get isSupported =>
      !kIsWeb &&
      !const bool.fromEnvironment('NO_BG_ASSERTION') &&
      (Platform.isAndroid || Platform.isIOS);

  /// The channel used to talk to the Android and iOS implementations.
  @visibleForTesting
  final MethodChannel methodChannel =
      const MethodChannel('io.github.toyaji.continued_task/channel');

  void Function(String event)? _onEvent;

  /// Per-task handlers, keyed by `taskId`. Native sends the originating task id
  /// alongside every event so a task only ever sees its own notification's
  /// "Cancel", timeout and assertion changes.
  final Map<String, void Function(String event)> _taskHandlers = {};

  /// Creates the implementation and starts listening for native callbacks.
  MethodChannelContinuedTask() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    // The global handler keeps receiving everything — removing events from it
    // would change behaviour for apps written against 0.1.x.
    _onEvent?.call(call.method);

    final taskId = (call.arguments as Map?)?['taskId'] as String?;
    if (taskId != null) {
      _taskHandlers[taskId]?.call(call.method);
      return null;
    }
    // No task id: an event that predates per-task routing. Deliver it to every
    // task so a single-task app behaves exactly as before.
    for (final handler in List.of(_taskHandlers.values)) {
      handler(call.method);
    }
    return null;
  }

  @override
  void setEventHandlers({required void Function(String event) onEvent}) {
    _onEvent = onEvent;
  }

  @override
  void setTaskEventHandler(
    String taskId,
    void Function(String event) onEvent,
  ) {
    _taskHandlers[taskId] = onEvent;
  }

  @override
  void removeTaskEventHandler(String taskId) {
    _taskHandlers.remove(taskId);
  }

  @override
  Future<bool> start(ContinuedTaskConfig config) async {
    final result = await methodChannel.invokeMethod<bool>(
      'start',
      config.toMap(),
    );
    return result ?? false;
  }

  @override
  Future<bool> update({
    required String taskId,
    required int progress,
    int? maxProgress,
    String? title,
    String? subtitle,
  }) async {
    final result = await methodChannel.invokeMethod<bool>('update', {
      'taskId': taskId,
      'progress': progress,
      'maxProgress': maxProgress,
      'title': title,
      'subtitle': subtitle,
    });
    return result ?? false;
  }

  @override
  Future<void> stop({required String taskId, bool success = true}) async {
    await methodChannel.invokeMethod<void>('stop', {
      'taskId': taskId,
      'success': success,
    });
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final result =
        await methodChannel.invokeMethod<bool>('requestNotificationPermission');
    return result ?? false;
  }

  @override
  Future<ContinuedTaskNativeState?> syncState() async {
    final result =
        await methodChannel.invokeMapMethod<String, dynamic>('syncState');
    if (result == null) return null;
    return ContinuedTaskNativeState.fromMap(result);
  }

  @override
  Future<ContinuedTaskNativeState?> syncStateFor(String taskId) async {
    final result = await methodChannel
        .invokeMapMethod<String, dynamic>('syncState', {'taskId': taskId});
    if (result == null) return null;
    return ContinuedTaskNativeState.fromMap(result);
  }

  @override
  Future<void> ackStopRequest() async {
    await methodChannel.invokeMethod<void>('ackStopRequest');
  }

  @override
  Future<void> ackStopRequestFor(String taskId) async {
    await methodChannel
        .invokeMethod<void>('ackStopRequest', {'taskId': taskId});
  }
}
