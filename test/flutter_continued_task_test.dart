import 'package:flutter_continued_task/flutter_continued_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockContinuedTaskPlatform
    with MockPlatformInterfaceMixin
    implements ContinuedTaskPlatform {
  ContinuedTaskConfig? startedConfig;
  final List<Map<String, dynamic>> updateCalls = [];
  final List<String> stoppedTasks = [];
  bool startResult = true;
  ContinuedTaskNativeState nativeState = const ContinuedTaskNativeState(
    assertionHeld: true,
    stopRequested: false,
  );
  bool ackStopRequestCalled = false;
  void Function(String event)? eventHandler;

  @override
  bool get isSupported => true;

  @override
  Future<bool> start(ContinuedTaskConfig config) async {
    startedConfig = config;
    return startResult;
  }

  @override
  Future<bool> update({
    required String taskId,
    required int progress,
    int? maxProgress,
    String? title,
    String? subtitle,
  }) async {
    updateCalls.add({
      'taskId': taskId,
      'progress': progress,
      'maxProgress': maxProgress,
      'title': title,
      'subtitle': subtitle,
    });
    return true;
  }

  @override
  Future<void> stop({required String taskId, bool success = true}) async {
    stoppedTasks.add(taskId);
  }

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<ContinuedTaskNativeState?> syncState() async {
    return nativeState;
  }

  @override
  Future<void> ackStopRequest() async {
    ackStopRequestCalled = true;
  }

  @override
  void setEventHandlers({required void Function(String event) onEvent}) {
    eventHandler = onEvent;
  }

  /// 0.2.0: per-task routing. The double keeps one slot — every task in these
  /// tests shares it, which matches the single-task scenarios they cover.
  @override
  void setTaskEventHandler(String taskId, void Function(String event) onEvent) {
    eventHandler = onEvent;
  }

  @override
  void removeTaskEventHandler(String taskId) {}

  @override
  Future<ContinuedTaskNativeState?> syncStateFor(String taskId) => syncState();

  @override
  Future<void> ackStopRequestFor(String taskId) => ackStopRequest();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockContinuedTaskPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockContinuedTaskPlatform();
    ContinuedTaskPlatform.instance = mockPlatform;
  });

  group('FlutterContinuedTask API Tests', () {
    test('start succeeds and returns ContinuedTask instance', () async {
      const config = ContinuedTaskConfig(
        title: 'DB Backup',
        subtitle: 'Backing up local database',
        initialProgress: 0,
        maxProgress: 100,
        taskId: 'db_backup_task',
      );

      final task = await FlutterContinuedTask.start(config: config);

      expect(task, isNotNull);
      expect(task!.taskId, 'db_backup_task');
      expect(mockPlatform.startedConfig, equals(config));
      expect(FlutterContinuedTask.currentTask, equals(task));
    });

    test('start returns null when native start fails (e.g. background blocked)',
        () async {
      mockPlatform.startResult = false;

      const config = ContinuedTaskConfig(
        title: 'AI Inference',
        taskId: 'ai_task',
      );

      final task = await FlutterContinuedTask.start(config: config);

      expect(task, isNull);
    });

    test('update sends parameters to platform interface', () async {
      const config = ContinuedTaskConfig(title: 'Upload File');
      final task = await FlutterContinuedTask.start(config: config);
      expect(task, isNotNull);

      await task!.update(progress: 45, maxProgress: 100, subtitle: '45 / 100');

      expect(mockPlatform.updateCalls.length, 1);
      expect(mockPlatform.updateCalls.first['progress'], 45);
      expect(mockPlatform.updateCalls.first['maxProgress'], 100);
      expect(mockPlatform.updateCalls.first['subtitle'], '45 / 100');
    });

    test('stop delegates to platform interface and marks task stopped',
        () async {
      const config =
          ContinuedTaskConfig(title: 'Video Encoding', taskId: 'video_1');
      final task = await FlutterContinuedTask.start(config: config);
      expect(task, isNotNull);

      await task!.stop();

      expect(mockPlatform.stoppedTasks, contains('video_1'));
      expect(task.isStopped, isTrue);
    });

    test('syncNativeState and ackStopRequest work correctly', () async {
      final state = await FlutterContinuedTask.syncNativeState();
      expect(state?.assertionHeld, isTrue);
      expect(state?.stopRequested, isFalse);

      await FlutterContinuedTask.ackStopRequest();
      expect(mockPlatform.ackStopRequestCalled, isTrue);
    });
  });
}
