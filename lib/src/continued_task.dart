import 'dart:async';
import 'package:flutter/foundation.dart';

import 'continued_task_platform_interface.dart';
import 'models/continued_task_config.dart';
import 'models/continued_task_state.dart';

/// 실행 중인 개별 계속 실행 태스크의 컨트롤러
class ContinuedTask {
  ContinuedTask._({
    required this.config,
    this.onUserCancel,
    this.onTimeout,
    this.onAssertionChanged,
  }) {
    _initEventHandling();
  }

  /// 태스크 생성 시 제공된 초기 설정
  final ContinuedTaskConfig config;

  /// 사용자가 알림/잠금화면에서 '중단'을 탭했을 때 발화되는 콜백
  void Function()? onUserCancel;

  /// Android 6시간 제한이나 OS 리소스 압박으로 태스크가 강제 종료될 때 발화되는 콜백
  void Function()? onTimeout;

  /// OS 수명이 실제로 확보(held=true)되거나 해제(held=false)될 때 발화되는 콜백
  void Function(bool held)? onAssertionChanged;

  String get taskId => config.taskId;

  bool _isAssertionHeld = false;

  /// 현재 네이티브 레벨에서 프로세스 수명이 실제로 확보되어 있는지 여부
  bool get isAssertionHeld => _isAssertionHeld;

  bool _isStopped = false;

  /// 태스크가 이미 종료되었는지 여부
  bool get isStopped => _isStopped;

  // --- 비동기 갱신 직렬화 및 최신 값 병합(Coalescing) ---
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

  /// 진행률 및 텍스트 갱신.
  /// 
  /// 고주파 호출 시(예: 초당 100회) 네이티브 채널 과부하를 막기 위해
  /// 자동으로 직렬화 및 최신 값 병합(Coalescing) 처리가 수행됩니다.
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

  /// 태스크를 정상 종료하고 네이티브 수명 및 알림 UI를 해제합니다.
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

  /// 이벤트 리스너를 동적으로 변경합니다.
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

/// 계속 실행 태스크(Continued Task) 진입점
class FlutterContinuedTask {
  FlutterContinuedTask._();

  static ContinuedTask? _currentTask;

  /// 현재 플랫폼에서 계속 실행 태스크를 지원하는지 여부
  static bool get isSupported => ContinuedTaskPlatform.instance.isSupported;

  /// 현재 활성화된 태스크 인스턴스 (없으면 null)
  static ContinuedTask? get currentTask => _currentTask;

  /// 계속 실행 태스크를 시작하고 네이티브 프로세스 수명을 요청합니다.
  /// 
  /// - 성공 시: `ContinuedTask` 인스턴스 반환
  /// - 시작 실패 시(백그라운드 진입 상태 등): `null` 반환 (대기 정책으로 처리 권장)
  static Future<ContinuedTask?> start({
    required ContinuedTaskConfig config,
    void Function()? onUserCancel,
    void Function()? onTimeout,
    void Function(bool held)? onAssertionChanged,
  }) async {
    // 기존 태스크가 실행 중이면 먼저 정리
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

  /// 앱 기동 시 네이티브에 남은 현재 상태를 동기화 조회합니다.
  static Future<ContinuedTaskNativeState?> syncNativeState() {
    return ContinuedTaskPlatform.instance.syncState();
  }

  /// 네이티브에 기록된 중단 요청 확인 플래그를 지웁니다.
  static Future<void> ackStopRequest() {
    return ContinuedTaskPlatform.instance.ackStopRequest();
  }

  /// 현재 실행 중인 태스크(또는 네이티브에 남은 태스크)를 중단합니다.
  static Future<void> stopCurrentTask({String taskId = 'upload_task'}) async {
    if (_currentTask != null) {
      await _currentTask!.stop();
      _currentTask = null;
    } else {
      await ContinuedTaskPlatform.instance.stop(taskId: taskId);
    }
  }

  /// 테스트 간 전역 상태를 리셋합니다.
  @visibleForTesting
  static void resetForTesting() {
    _currentTask = null;
  }
}
