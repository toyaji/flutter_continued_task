import 'package:flutter_continued_task/flutter_continued_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class LifecycleMockPlatform
    with MockPlatformInterfaceMixin
    implements ContinuedTaskPlatform {
  void Function(String event)? eventCallback;

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
  }) async =>
      true;

  @override
  Future<void> stop({required String taskId, bool success = true}) async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<ContinuedTaskNativeState?> syncState() async =>
      const ContinuedTaskNativeState(
          assertionHeld: false, stopRequested: false);

  @override
  Future<void> ackStopRequest() async {}

  @override
  void setEventHandlers({required void Function(String event) onEvent}) {
    eventCallback = onEvent;
  }

  /// 0.2.0: per-task routing. The double keeps one slot — every task in these
  /// tests shares it, which matches the single-task scenarios they cover.
  @override
  void setTaskEventHandler(String taskId, void Function(String event) onEvent) {
    eventCallback = onEvent;
  }

  @override
  void removeTaskEventHandler(String taskId) {}

  @override
  Future<ContinuedTaskNativeState?> syncStateFor(String taskId) => syncState();

  @override
  Future<void> ackStopRequestFor(String taskId) => ackStopRequest();

  void triggerEvent(String event) {
    eventCallback?.call(event);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LifecycleMockPlatform mockPlatform;

  setUp(() {
    mockPlatform = LifecycleMockPlatform();
    ContinuedTaskPlatform.instance = mockPlatform;
  });

  group('Lifecycle Simulation Tests', () {
    test(
        'assertionAcquired and assertionLost events update isAssertionHeld and fire callback',
        () async {
      final heldHistory = <bool>[];

      final task = await FlutterContinuedTask.start(
        config: const ContinuedTaskConfig(title: 'Life Cycle Test'),
        onAssertionChanged: (held) => heldHistory.add(held),
      );
      expect(task, isNotNull);
      expect(task!.isAssertionHeld, isFalse);

      // 1. Simulate native FGS / BGContinuedProcessingTask acquisition
      mockPlatform.triggerEvent('assertionAcquired');
      expect(task.isAssertionHeld, isTrue);
      expect(heldHistory, equals([true]));

      // 2. Simulate assertion lost due to completion or OS reclaim
      mockPlatform.triggerEvent('assertionLost');
      expect(task.isAssertionHeld, isFalse);
      expect(heldHistory, equals([true, false]));
    });

    test(
        'stopRequested event (user tapped cancel button on notification) triggers onUserCancel',
        () async {
      bool userCancelFired = false;

      final task = await FlutterContinuedTask.start(
        config: const ContinuedTaskConfig(title: 'Cancelable Task'),
        onUserCancel: () {
          userCancelFired = true;
        },
      );
      expect(task, isNotNull);

      // Simulate notification cancel action click
      mockPlatform.triggerEvent('stopRequested');
      expect(userCancelFired, isTrue);
    });

    test(
        'timeout event (Android 6h limit or iOS expiration) triggers onTimeout and resets assertion',
        () async {
      bool timeoutFired = false;
      final heldHistory = <bool>[];

      final task = await FlutterContinuedTask.start(
        config: const ContinuedTaskConfig(title: 'Long Running Task'),
        onTimeout: () {
          timeoutFired = true;
        },
        onAssertionChanged: (held) => heldHistory.add(held),
      );
      expect(task, isNotNull);

      // Set to acquired state first
      mockPlatform.triggerEvent('assertionAcquired');
      expect(task!.isAssertionHeld, isTrue);

      // Simulate timeout reached
      mockPlatform.triggerEvent('timeout');
      expect(timeoutFired, isTrue);
      expect(task.isAssertionHeld, isFalse);
      expect(heldHistory, equals([true, false]));
    });
  });
}
