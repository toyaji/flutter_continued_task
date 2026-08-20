import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'continued_task_platform_interface.dart';
import 'models/continued_task_config.dart';
import 'models/continued_task_state.dart';

class MethodChannelContinuedTask extends ContinuedTaskPlatform {
  @override
  bool get isSupported =>
      !kIsWeb &&
      !const bool.fromEnvironment('NO_BG_ASSERTION') &&
      (Platform.isAndroid || Platform.isIOS);

  @visibleForTesting
  final MethodChannel methodChannel =
      const MethodChannel('dev.flutter.continued_task/channel');

  void Function(String event)? _onEvent;

  MethodChannelContinuedTask() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    _onEvent?.call(call.method);
    return null;
  }

  @override
  void setEventHandlers({required void Function(String event) onEvent}) {
    _onEvent = onEvent;
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
    final result = await methodChannel.invokeMethod<bool>('requestNotificationPermission');
    return result ?? false;
  }

  @override
  Future<ContinuedTaskNativeState?> syncState() async {
    final result = await methodChannel.invokeMapMethod<String, dynamic>('syncState');
    if (result == null) return null;
    return ContinuedTaskNativeState.fromMap(result);
  }

  @override
  Future<void> ackStopRequest() async {
    await methodChannel.invokeMethod<void>('ackStopRequest');
  }
}
