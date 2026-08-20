import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_continued_task.dart';
import 'models/continued_task_config.dart';
import 'models/continued_task_state.dart';

abstract class ContinuedTaskPlatform extends PlatformInterface {
  ContinuedTaskPlatform() : super(token: _token);

  static final Object _token = Object();

  static ContinuedTaskPlatform _instance = MethodChannelContinuedTask();

  static ContinuedTaskPlatform get instance => _instance;

  static set instance(ContinuedTaskPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// 현재 플랫폼에서 계속 실행 태스크를 지원하는지 여부
  bool get isSupported => false;

  /// 태스크 시작 요청 (성공 시 true, 불가 시 false)
  Future<bool> start(ContinuedTaskConfig config) {
    throw UnimplementedError('start() has not been implemented.');
  }

  /// 진행률 및 텍스트 갱신
  Future<bool> update({
    required String taskId,
    required int progress,
    int? maxProgress,
    String? title,
    String? subtitle,
  }) {
    throw UnimplementedError('update() has not been implemented.');
  }

  /// 태스크 종료
  Future<void> stop({required String taskId}) {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// 네이티브 상태 동기화 조회 (미지원 또는 응답 없을 시 null)
  Future<ContinuedTaskNativeState?> syncState() {
    throw UnimplementedError('syncState() has not been implemented.');
  }

  /// 중단 요청 확인 플래그 리셋
  Future<void> ackStopRequest() {
    throw UnimplementedError('ackStopRequest() has not been implemented.');
  }

  /// 네이티브 이벤트 핸들러 등록
  void setEventHandlers({
    required void Function(String event) onEvent,
  }) {
    throw UnimplementedError('setEventHandlers() has not been implemented.');
  }
}
