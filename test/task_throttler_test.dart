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
  Future<void> stop({required String taskId}) async {}

  @override
  Future<ContinuedTaskNativeState?> syncState() async {
    return const ContinuedTaskNativeState(assertionHeld: false, stopRequested: false);
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

  test('High-frequency updates are serialized and coalesced, ensuring final state', () async {
    final task = await FlutterContinuedTask.start(
      config: const ContinuedTaskConfig(title: 'High Frequency Processing'),
    );
    expect(task, isNotNull);

    mockPlatform.delayCompleter = Completer<void>();

    // 짧은 시간 동안 50번의 update를 비동기로 연속 발사
    final futures = <Future<void>>[];
    for (int i = 1; i <= 50; i++) {
      futures.add(task!.update(progress: i, maxProgress: 50));
    }

    // 첫 번째 update가 진행 중인 동안 나머지가 큐에 쌓임
    mockPlatform.delayCompleter!.complete();
    await Future.wait(futures);

    // 50번의 호출 중 불필요한 중간 값은 병합(Coalesced)되고,
    // 전체 네이티브 호출 횟수는 50번보다 현저히 적으면서
    // 마지막 값(50)은 반드시 도달해야 함.
    expect(mockPlatform.processedProgresses.last, 50);
    expect(mockPlatform.processedProgresses.length, lessThan(50));
  });
}
