import 'dart:async';
import 'package:checks/checks.dart';
import 'package:flutter_continued_task/flutter_continued_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _RecordingPlatform
    with MockPlatformInterfaceMixin
    implements ContinuedTaskPlatform {
  _RecordingPlatform({
    this.startResult = true,
    this.syncStateResult,
    this.isSupported = true,
  });

  final List<String> calls = [];
  final List<Map<String, dynamic>> updateArgs = [];
  final bool startResult;
  final ContinuedTaskNativeState? syncStateResult;
  @override
  final bool isSupported;
  ContinuedTaskConfig? startedConfig;
  void Function(String event)? onEventHandler;

  void emit(String event) => onEventHandler?.call(event);

  @override
  Future<bool> start(ContinuedTaskConfig config) async {
    calls.add('start');
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
    calls.add('update');
    updateArgs.add({
      'taskId': taskId,
      'progress': progress,
      'maxProgress': maxProgress,
      'title': title,
      'subtitle': subtitle,
    });
    return true;
  }

  bool? lastStopSuccess;

  @override
  Future<void> stop({required String taskId, bool success = true}) async {
    calls.add('stop');
    lastStopSuccess = success;
  }

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<ContinuedTaskNativeState?> syncState() async {
    calls.add('syncState');
    return syncStateResult;
  }

  @override
  Future<void> ackStopRequest() async {
    calls.add('ackStopRequest');
  }

  @override
  void setEventHandlers({required void Function(String event) onEvent}) {
    onEventHandler = onEvent;
  }
}

void main() {
  test('Does not invoke channel on unsupported platforms', () async {
    ContinuedTask.resetForTesting();
    final mock = _RecordingPlatform(isSupported: false);
    ContinuedTaskPlatform.instance = mock;
    final tracker = ContinuedTask.track(
      title: 'Testing',
      autoSyncNativeState: false,
    );

    await tracker.sync(3);
    await tracker.sync(0);

    check(mock.calls).isEmpty();
    check(tracker.isSubmitted).isFalse();
  });

  group('TaskTracker & ContinuedTask.track Tests', () {
    late _RecordingPlatform mock;
    late TaskTracker tracker;

    setUp(() {
      ContinuedTask.resetForTesting();
      mock = _RecordingPlatform(startResult: true);
      ContinuedTaskPlatform.instance = mock;
      tracker = ContinuedTask.track(
        title: 'Testing',
        baseConfig: const ContinuedTaskConfig(taskId: 'test_task'),
        autoSyncNativeState: false,
      );
    });

    test('0->N auto starts, N->0 sends 100% update then auto stops', () async {
      await tracker.sync(3);
      check(mock.calls).deepEquals(['start']);
      check(tracker.isSubmitted).isTrue();
      check(tracker.batchTotal).equals(3);

      await tracker.sync(0);
      check(mock.calls).deepEquals(['start', 'update', 'stop']);
      final lastUpdate = mock.updateArgs.last;
      check(lastUpdate['progress']).equals(3);
      check(lastUpdate['maxProgress']).equals(3);
      check(lastUpdate['title']).equals('Testing (3/3)');
      check(lastUpdate['subtitle']).equals('3/3');
      check(mock.lastStopSuccess).equals(true);
      check(tracker.isSubmitted).isFalse();
      check(tracker.batchTotal).equals(0);
    });

    test(
        'cancel() immediately stops ongoing task without sending fake 100% update',
        () async {
      await tracker.sync(9);
      for (var remaining = 8; remaining >= 5; remaining--) {
        await tracker.sync(remaining);
      }
      check(mock.updateArgs.last['progress']).equals(4);

      // User calls cancel() mid-flight
      await tracker.cancel();

      check(mock.calls.last).equals('stop');
      // Last update remains 4, never falsely updated to 9
      check(mock.updateArgs.last['progress']).equals(4);
      check(mock.lastStopSuccess).equals(false);
      check(tracker.isSubmitted).isFalse();
      check(tracker.batchTotal).equals(0);
    });

    test(
        'Rapid consecutive calls coalesce into a single start with final count',
        () async {
      unawaited(tracker.sync(1));
      unawaited(tracker.sync(2));
      await tracker.sync(9);

      check(mock.calls).deepEquals(['start']);
      check(mock.startedConfig!.maxProgress).equals(9);
      check(mock.startedConfig!.initialProgress).equals(0);
      check(tracker.batchTotal).equals(9);
    });

    test('Mid-flight progress changes emit update only without redundant start',
        () async {
      await tracker.sync(3);
      await tracker.sync(2);
      await tracker.sync(1);

      check(mock.calls).deepEquals(['start', 'update', 'update']);
      check(mock.updateArgs.first['progress']).equals(1); // (3 - 2) = 1
      check(mock.updateArgs.last['progress']).equals(2); // (3 - 1) = 2
    });

    test('Batch total is calculated from when count increases from 0',
        () async {
      await tracker.sync(2);
      check(mock.startedConfig!.maxProgress).equals(2);
      check(mock.startedConfig!.initialProgress).equals(0);

      await tracker.sync(0);
      await tracker.sync(5); // New batch
      check(mock.startedConfig!.maxProgress).equals(5);
      check(mock.startedConfig!.initialProgress).equals(0);
    });

    test('Mid-flight additions dynamically increase batch total', () async {
      await tracker.sync(2); // total: 2, done: 0
      await tracker.sync(1); // total: 2, done: 1
      await tracker.sync(4); // 3 items added -> total: 5, done: 1

      check(tracker.batchTotal).equals(5);
      check(mock.updateArgs.last['progress']).equals(1);
      check(mock.updateArgs.last['maxProgress']).equals(5);
    });

    test('Start rejection clears submitted state and retries on next sync',
        () async {
      final rejectingMock = _RecordingPlatform(startResult: false);
      ContinuedTaskPlatform.instance = rejectingMock;
      final rejectingTracker = ContinuedTask.track(
        title: 'Testing',
        autoSyncNativeState: false,
      );

      await rejectingTracker.sync(3);
      check(rejectingTracker.isSubmitted).isFalse();
      check(rejectingMock.calls).deepEquals(['start']);

      await rejectingTracker.sync(2);
      check(rejectingMock.calls).deepEquals(['start', 'start']);
    });

    test('Concurrent sync calls emit start exactly once', () async {
      await Future.wait([
        tracker.sync(3),
        tracker.sync(2),
        tracker.sync(1),
      ]);

      check(mock.calls.where((c) => c == 'start').length).equals(1);
    });

    test('Start rejection immediately reports assertion not held', () async {
      bool? held;
      final rejectingMock = _RecordingPlatform(startResult: false);
      ContinuedTaskPlatform.instance = rejectingMock;
      final rejectingTracker = ContinuedTask.track(
        title: 'Testing',
        onAssertionChanged: (value) => held = value,
        autoSyncNativeState: false,
      );

      await rejectingTracker.sync(3);

      check(rejectingTracker.isSubmitted).isFalse();
      check(held).equals(false);
    });

    test(
        'Submitted state does not imply assertion acquired - only native events confirm',
        () async {
      final held = <bool>[];
      final holdingTracker = ContinuedTask.track(
        title: 'Testing',
        onAssertionChanged: held.add,
        autoSyncNativeState: false,
      );

      await holdingTracker.sync(3);
      check(holdingTracker.isSubmitted).isTrue();
      check(held).isEmpty();

      mock.emit('assertionAcquired');
      check(held.last).isTrue();

      mock.emit('assertionLost');
      check(held.last).isFalse();
    });

    test('Timeout triggers onTimeout and resets submission state', () async {
      var timedOut = false;
      var cancelCalled = false;
      final timeoutTracker = ContinuedTask.track(
        title: 'Testing',
        onUserCancel: () async => cancelCalled = true,
        onTimeout: () => timedOut = true,
        autoSyncNativeState: false,
      );

      await timeoutTracker.sync(3);
      check(timeoutTracker.isSubmitted).isTrue();

      mock.emit('timeout');

      check(timedOut).isTrue();
      check(cancelCalled).isFalse();
      check(timeoutTracker.isSubmitted).isFalse();
      check(timeoutTracker.batchTotal).equals(0);
    });

    test('User cancel notification action triggers onUserCancel', () async {
      var cancelCalled = false;
      final cancelTracker = ContinuedTask.track(
        title: 'Testing',
        onUserCancel: () async => cancelCalled = true,
        autoSyncNativeState: false,
      );

      await cancelTracker.sync(3);
      mock.emit('stopRequested');

      check(cancelCalled).isTrue();
    });

    test('Auto-formats title with progress and supports custom titleBuilder',
        () async {
      final customTracker = ContinuedTask.track(
        titleBuilder: (done, total) => 'Custom: $done of $total',
        autoSyncNativeState: false,
      );

      await customTracker.sync(5);
      check(mock.startedConfig!.title).equals('Custom: 0 of 5');

      await customTracker.sync(3);
      check(mock.updateArgs.last['title']).equals('Custom: 2 of 5');
    });

    test('dispose safely stops active task and resets state', () async {
      await tracker.sync(3);
      check(mock.calls).deepEquals(['start']);

      await tracker.dispose();
      check(mock.calls).contains('stop');
      check(tracker.isSubmitted).isFalse();
    });
  });

  group('syncNativeState recovery', () {
    setUp(ContinuedTask.resetForTesting);

    test('Recovers running service state and stops cleanly when count is 0',
        () async {
      final mock = _RecordingPlatform(
        syncStateResult: const ContinuedTaskNativeState(
          assertionHeld: true,
          stopRequested: false,
        ),
      );
      ContinuedTaskPlatform.instance = mock;
      final held = <bool>[];
      final tracker = ContinuedTask.track(
        title: 'Testing',
        onAssertionChanged: held.add,
        autoSyncNativeState: true,
      );

      await pumpEventQueue();

      check(mock.calls.first).equals('syncState');
      check(held.last).isTrue();
      check(mock.calls).contains('stop');
      check(tracker.isSubmitted).isFalse();
    });

    test('Pending stop request is acknowledged only after callback finishes',
        () async {
      final mock = _RecordingPlatform(
        syncStateResult: const ContinuedTaskNativeState(
          assertionHeld: false,
          stopRequested: true,
        ),
      );
      ContinuedTaskPlatform.instance = mock;
      var stopHandled = false;
      ContinuedTask.track(
        title: 'Testing',
        onUserCancel: () async => stopHandled = true,
        autoSyncNativeState: true,
      );

      await pumpEventQueue();

      check(stopHandled).isTrue();
      check(mock.calls.contains('ackStopRequest')).isTrue();
      check(mock.calls.indexOf('ackStopRequest'))
          .isGreaterThan(mock.calls.indexOf('syncState'));
    });
  });

  group('Assertion lost & submission state', () {
    setUp(ContinuedTask.resetForTesting);

    test(
        'assertionLost clears submitted state so next sync triggers start again',
        () async {
      final mock = _RecordingPlatform(startResult: true);
      ContinuedTaskPlatform.instance = mock;
      final tracker = ContinuedTask.track(
        title: 'Testing',
        autoSyncNativeState: false,
      );

      await tracker.sync(3);
      check(tracker.isSubmitted).isTrue();

      mock.emit('assertionLost');
      check(tracker.isSubmitted).isFalse();

      mock.calls.clear();
      await tracker.sync(2);
      check(mock.calls).contains('start');
    });
  });
}
