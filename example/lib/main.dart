import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_continued_task/flutter_continued_task.dart';

/// 플러그인 동작 확인용 예제 앱. 빌드 한 번으로 네이티브까지 컴파일된다.
void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'flutter_continued_task',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: const TaskDemoPage(),
      );
}

class TaskDemoPage extends StatefulWidget {
  const TaskDemoPage({super.key});

  @override
  State<TaskDemoPage> createState() => _TaskDemoPageState();
}

class _TaskDemoPageState extends State<TaskDemoPage> {
  static const int _totalUnits = 120;

  ContinuedTask? _task;
  Timer? _ticker;

  int _done = 0;
  bool _assertionHeld = false;
  final List<String> _events = <String>[];

  @override
  void initState() {
    super.initState();
    // 앱이 없는 동안 눌린 중단·확보 상태를 넘겨받는다.
    unawaited(_syncNativeState());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _syncNativeState() async {
    final state = await FlutterContinuedTask.syncNativeState();
    if (!mounted || state == null) return;
    setState(() {
      _assertionHeld = state.assertionHeld;
      _log('syncState: 확보=${state.assertionHeld} '
          '중단대기=${state.stopRequested}');
    });
    if (state.stopRequested) {
      await FlutterContinuedTask.ackStopRequest();
      _log('보류된 중단을 확인 처리했다');
    }
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, message);
      if (_events.length > 12) _events.removeLast();
    });
  }

  Future<void> _start() async {
    final task = await FlutterContinuedTask.start(
      config: const ContinuedTaskConfig(
        taskId: 'example_task',
        title: '예제 작업 진행 중',
        subtitle: '0/$_totalUnits',
        maxProgress: _totalUnits,
        // 번들 ID 접두 필수. Info.plist의 등록 식별자와 정확히 일치해야 한다.
        iosTaskIdentifier: 'dev.flutter.flutterContinuedTaskExample.task',
      ),
      onUserCancel: () {
        _log('사용자 중단');
        unawaited(_stop());
      },
      onTimeout: () {
        _log('시스템 회수 — 남은 작업은 대기');
        _ticker?.cancel();
      },
      onAssertionChanged: (held) {
        _log('수명 확보 ${held ? "획득" : "해제"}');
        if (mounted) setState(() => _assertionHeld = held);
      },
    );

    if (task == null) {
      _log('시작 거부됨 — 대기로 처리할 상황');
      return;
    }

    setState(() {
      _task = task;
      _done = 0;
    });
    _log('시작됨');
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final task = _task;
      if (task == null || task.isStopped) {
        timer.cancel();
        return;
      }
      if (_done >= _totalUnits) {
        timer.cancel();
        await _stop();
        _log('완료');
        return;
      }
      setState(() => _done++);
      await task.update(progress: _done, subtitle: '$_done/$_totalUnits');
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    await FlutterContinuedTask.stopCurrentTask();
    if (!mounted) return;
    setState(() => _task = null);
  }

  @override
  Widget build(BuildContext context) {
    final running = _task != null && !(_task?.isStopped ?? true);

    return Scaffold(
      appBar: AppBar(title: const Text('flutter_continued_task')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: _done / _totalUnits),
            const SizedBox(height: 8),
            Text('$_done / $_totalUnits'),
            const SizedBox(height: 8),
            Text('수명 확보: ${_assertionHeld ? "유지 중" : "없음"}'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: running ? null : _start,
                    child: const Text('시작'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: running ? _stop : null,
                    child: const Text('중단'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('이벤트'),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _events.length,
                itemBuilder: (context, index) => Text(_events[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
