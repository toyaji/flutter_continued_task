import 'dart:async';
import 'package:flutter_continued_task/flutter_continued_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class SlowMockContinuedTaskPlatform
    with MockPlatformInterfaceMixin
    implements ContinuedTaskPlatform {
  final List<int> processedProgresses = [];
  Completer<void>? delayCompleter;

  @override
  bool get isSupported => true;

  @override
  Future<bool> start(ContinuedTaskConfig config) async => true;

  @override
  Future<bool> update({
    required String taskId,
    required int progress,
    int? maxProgress,
    String? title,
    String? subtitle,
  }) async {
    processedProgresses.add(progress);
    if (delayCompleter != null) {
      await delayCompleter!.future;
    }
    return true;
  }

  @override
  Future<void> stop({required String taskId, bool success = true}) async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<ContinuedTaskNativeState?> syncState() async {
    return const ContinuedTaskNativeState(
        assertionHeld: false, stopRequested: false);
  }

  @override
  Future<void> ackStopRequest() async {}

  @override
  void setEventHandlers({required void Function(String event) onEvent}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SlowMockContinuedTaskPlatform mockPlatform;

  setUp(() {
    mockPlatform = SlowMockContinuedTaskPlatform();
    ContinuedTaskPlatform.instance = mockPlatform;
  });

  test(
      'High-frequency updates are serialized and coalesced, ensuring final state',
      () async {
    final task = await FlutterContinuedTask.start(
      config: const ContinuedTaskConfig(title: 'High Frequency Processing'),
    );
    expect(task, isNotNull);

    mockPlatform.delayCompleter = Completer<void>();

    // Dispatch 50 rapid async updates in short succession
    final futures = <Future<void>>[];
    for (int i = 1; i <= 50; i++) {
      futures.add(task!.update(progress: i, maxProgress: 50));
    }

    // While the first update is processing, subsequent updates coalesce in the queue
    mockPlatform.delayCompleter!.complete();
    await Future.wait(futures);

    // Intermediate values are coalesced, resulting in far fewer than 50 native calls,
    // while guaranteeing the final value (50) is reached.
    expect(mockPlatform.processedProgresses.last, 50);
    expect(mockPlatform.processedProgresses.length, lessThan(50));
  });

  test(
      'Immediate stop after rapid update guarantees final progress is flushed to native',
      () async {
    final task = await FlutterContinuedTask.start(
      config: const ContinuedTaskConfig(title: 'Flush Test'),
    );
    expect(task, isNotNull);

    mockPlatform.delayCompleter = Completer<void>();

    // Start in-flight update with 8
    final f8 = task!.update(progress: 8, maxProgress: 9);

    // Queue 9 immediately while 8 is still in-flight
    final f9 = task.update(progress: 9, maxProgress: 9);

    // Stop is called immediately
    final fStop = task.stop();

    // Release the delay so processing unblocks
    mockPlatform.delayCompleter!.complete();

    await Future.wait([f8, f9, fStop]);

    // The final value (9) MUST be processed before stopping, never dropped
    expect(mockPlatform.processedProgresses.last, 9);
    expect(task.isStopped, isTrue);
  });
}
