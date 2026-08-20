import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_continued_task/flutter_continued_task.dart';

/// 플러그인 동작을 손으로 확인하는 예제 앱.
///
/// **이 앱의 첫째 목적은 데모가 아니라 컴파일 강제다.** 플러그인 패키지만으로는
/// 네이티브(Swift·Kotlin)가 빌드되지 않아, 존재하지 않는 API를 써도 앱에
/// 붙이기 전까지 아무도 모른다. 실제로 그런 오타가 앱 빌드에서야 잡힌 적이
/// 있다(`cancelTaskRequest` → `cancel(taskRequestWithIdentifier:)`).
/// `flutter build ios --no-codesign` / `flutter build apk` 한 번이면 양쪽이
/// 컴파일된다.
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
  static const int _totalUnits = 20;

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
      ),
      // 사용자가 알림·잠금화면에서 중단을 눌렀다. 의사이므로 되살리지 않는다.
      onUserCancel: () {
        _log('사용자 중단');
        unawaited(_stop());
      },
      // 시스템이 회수했다(시간·리소스). 환경이므로 조건이 되면 재개해도 된다.
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
      // 미지원 OS이거나 지금 시작할 수 없는 상태(백그라운드 등).
      // **예외가 아니라 null이다** — 호출부는 대기 정책으로 다루면 된다.
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
