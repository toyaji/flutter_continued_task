import 'package:flutter_continued_task/flutter_continued_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records what each task registered, so a test can fire an event at exactly
/// one task — the thing 0.1.x could not do (one global handler slot).
class _MultiTaskPlatform
    with MockPlatformInterfaceMixin
    implements ContinuedTaskPlatform {
  final List<String> startedTaskIds = [];
  final List<String> stoppedTaskIds = [];
  final Map<String, void Function(String event)> handlers = {};
  void Function(String event)? globalHandler;

  @override
  bool get isSupported => true;

  @override
  Future<bool> start(ContinuedTaskConfig config) async {
    startedTaskIds.add(config.taskId);
    return true;
  }

  @override
  Future<bool> update({
    required String taskId,
    required int progress,
    int? maxProgress,
    String? title,
    String? subtitle,
  }) async =>
      true;

  @override
  Future<void> stop({required String taskId, bool success = true}) async {
    stoppedTaskIds.add(taskId);
  }

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<ContinuedTaskNativeState?> syncState() async => null;

  @override
  Future<ContinuedTaskNativeState?> syncStateFor(String taskId) async => null;

  @override
  Future<void> ackStopRequest() async {}

  @override
  Future<void> ackStopRequestFor(String taskId) async {}

  @override
  void setEventHandlers({required void Function(String event) onEvent}) {
    globalHandler = onEvent;
  }

  @override
  void setTaskEventHandler(String taskId, void Function(String event) onEvent) {
    handlers[taskId] = onEvent;
  }

  @override
  void removeTaskEventHandler(String taskId) {
    handlers.remove(taskId);
  }
}

void main() {
  late _MultiTaskPlatform platform;

  setUp(() {
    ContinuedTask.resetForTesting();
    platform = _MultiTaskPlatform();
    ContinuedTaskPlatform.instance = platform;
  });

  group('기본값 — 0.1.x 동작이 그대로다', () {
    test('allowConcurrent 없이 두 번째 태스크를 시작하면 첫 번째가 멈춘다', () async {
      await ContinuedTask.start(config: const ContinuedTaskConfig(taskId: 'a'));
      await ContinuedTask.start(config: const ContinuedTaskConfig(taskId: 'b'));

      expect(platform.stoppedTaskIds, ['a'],
          reason: '기존 사용자는 코드를 바꾸지 않아도 지금까지의 동작을 그대로 받는다');
      expect(platform.startedTaskIds, ['a', 'b']);
    });
  });

  group('allowConcurrent — 태스크가 서로를 밀어내지 않는다', () {
    test('서로 다른 id는 공존하고, 같은 id만 교체된다', () async {
      await ContinuedTask.start(
          config: const ContinuedTaskConfig(taskId: 'gallery'),
          allowConcurrent: true);
      await ContinuedTask.start(
          config: const ContinuedTaskConfig(taskId: 'capture'),
          allowConcurrent: true);

      expect(platform.stoppedTaskIds, isEmpty);

      await ContinuedTask.start(
          config: const ContinuedTaskConfig(taskId: 'gallery'),
          allowConcurrent: true);
      expect(platform.stoppedTaskIds, ['gallery'], reason: '같은 id의 재시작은 교체다');
    });

    test('한쪽 알림의 [중단]이 다른 태스크를 건드리지 않는다', () async {
      var galleryCancelled = 0;
      var captureCancelled = 0;

      await ContinuedTask.start(
        config: const ContinuedTaskConfig(taskId: 'gallery'),
        allowConcurrent: true,
        onUserCancel: () => galleryCancelled++,
      );
      await ContinuedTask.start(
        config: const ContinuedTaskConfig(taskId: 'capture'),
        allowConcurrent: true,
        onUserCancel: () => captureCancelled++,
      );

      // 촬영 알림의 [중단]만 눌렀다.
      platform.handlers['capture']!('stopRequested');

      expect(captureCancelled, 1);
      expect(galleryCancelled, 0,
          reason: '전역 핸들러 한 칸이던 시절에는 나중에 등록한 쪽이 남의 취소까지 받았다');
    });

    test('stop 후에는 핸들러가 해제되어 늦게 온 이벤트가 죽은 태스크를 깨우지 않는다', () async {
      final task = await ContinuedTask.start(
          config: const ContinuedTaskConfig(taskId: 'gallery'),
          allowConcurrent: true);
      await task!.stop();

      expect(platform.handlers.containsKey('gallery'), isFalse);
      expect(ContinuedTask.taskOf('gallery'), isNull);
    });
  });

  group('trackerless 정리 경로', () {
    test('stopCurrentTask(taskId:)는 그 id의 태스크만 멈춘다', () async {
      await ContinuedTask.start(
          config: const ContinuedTaskConfig(taskId: 'gallery'),
          allowConcurrent: true);
      await ContinuedTask.start(
          config: const ContinuedTaskConfig(taskId: 'capture'),
          allowConcurrent: true);

      await ContinuedTask.stopCurrentTask(taskId: 'gallery');

      expect(platform.stoppedTaskIds, ['gallery']);
      expect(ContinuedTask.taskOf('capture'), isNotNull);
    });
  });

  group('taskId 없는 이벤트 (레거시 네이티브)', () {
    test('모든 태스크에 전달되어 단일 태스크 앱의 동작이 유지된다', () async {
      var cancelled = 0;
      await ContinuedTask.start(
        config: const ContinuedTaskConfig(taskId: 'only'),
        onUserCancel: () => cancelled++,
      );

      // 전역 핸들러 경로도 계속 살아 있어야 한다.
      expect(platform.handlers.containsKey('only'), isTrue);
      platform.handlers['only']!('stopRequested');
      expect(cancelled, 1);
    });
  });
}
