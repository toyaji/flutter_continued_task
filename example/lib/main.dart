import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_continued_task/flutter_continued_task.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_continued_task Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const MainTabScreen(),
    );
  }
}

class MainTabScreen extends StatelessWidget {
  const MainTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_continued_task Example'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.auto_mode), text: 'TaskTracker (Auto)'),
              Tab(icon: Icon(Icons.touch_app), text: 'ContinuedTask (Manual)'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            TrackerDemoTab(),
            ManualDemoTab(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 1. TaskTracker Demo Tab (High-Level Automation)
// ============================================================================

class TrackerDemoTab extends StatefulWidget {
  const TrackerDemoTab({super.key});

  @override
  State<TrackerDemoTab> createState() => _TrackerDemoTabState();
}

class _TrackerDemoTabState extends State<TrackerDemoTab> {
  late TaskTracker _tracker;
  Timer? _timer;

  int _unfinished = 0;
  bool _assertionHeld = false;
  final List<String> _logs = <String>[];

  @override
  void initState() {
    super.initState();
    FlutterContinuedTask.requestNotificationPermission().then((granted) {
      if (mounted) {
        _log('🔔 [Permission] Notification permission ${granted ? "Granted" : "Denied"}');
      }
    });
    _tracker = ContinuedTask.track(
      title: 'Uploading Photos',
      baseConfig: const ContinuedTaskConfig(
        taskId: 'example_tracker_task',
        androidNotificationIcon: 'upload',
        androidChannelName: 'Photo Upload',
        androidChannelDescription: 'Shows progress while uploading photos',
        iosTaskIdentifier: 'dev.flutter.flutterContinuedTaskExample.task',
      ),
      onUserCancel: () async {
        _log('🔔 [Notification Action] User tapped Cancel on notification');
        _stopTimer();
        setState(() => _unfinished = 0);
        await _tracker.cancel();
      },
      onTimeout: () {
        _log('⚠️ [OS Event] Task time limit reached (Timeout)');
        _stopTimer();
      },
      onAssertionChanged: (held) {
        _log('⚡ [OS Lifecycle] Foreground assertion ${held ? "Acquired (Active)" : "Lost (Inactive)"}');
        if (mounted) setState(() => _assertionHeld = held);
      },
      autoSyncNativeState: true,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tracker.dispose();
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    final time = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _logs.insert(0, '[$time] $message');
      if (_logs.length > 30) _logs.removeLast();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Simulates enqueueing 9 items synchronously to verify microtask coalescing
  Future<void> _simulateBatchEnqueue() async {
    _stopTimer();
    _log('⚡ Enqueueing 9 photos in rapid succession (sync(1..9))...');

    for (var i = 1; i <= 9; i++) {
      _unfinished = i;
      unawaited(_tracker.sync(i));
    }
    setState(() {});

    _log('✅ 9 photos enqueued (batchTotal: ${_tracker.batchTotal}, submitted: ${_tracker.isSubmitted})');
    _startAutoProcess();
  }

  /// Completes 1 item every 2 seconds (realistic upload pace)
  void _startAutoProcess() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(milliseconds: 2000), (timer) async {
      if (_unfinished <= 0) {
        timer.cancel();
        _log('🎉 All items completed (sync(0) sent -> auto stopped)');
        await _tracker.sync(0);
        if (mounted) setState(() {});
        return;
      }

      setState(() => _unfinished--);
      _log('In progress: $_unfinished items remaining (${_tracker.batchTotal - _unfinished} of ${_tracker.batchTotal} completed)');
      await _tracker.sync(_unfinished);
      if (mounted) setState(() {});
    });
  }

  /// Adds 3 photos mid-flight
  Future<void> _add3Items() async {
    setState(() => _unfinished += 3);
    _log('➕ Added 3 items mid-flight! (Remaining: $_unfinished)');
    await _tracker.sync(_unfinished);
    setState(() {});
    if (_timer == null || !_timer!.isActive) {
      _startAutoProcess();
    }
  }

  /// Cancels all tasks
  Future<void> _cancelAll() async {
    _stopTimer();
    setState(() => _unfinished = 0);
    _log('🛑 Stop all requested (cancel())');
    await _tracker.cancel();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final total = _tracker.batchTotal;
    final done = (total - _unfinished).clamp(0, total);
    final progressRatio = total > 0 ? (done / total) : 0.0;
    final isRunning = _tracker.isSubmitted || _unfinished > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Status Dashboard Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress: $done / $total',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _assertionHeld ? Colors.green.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _assertionHeld ? Icons.shield : Icons.shield_outlined,
                              size: 16,
                              color: _assertionHeld ? Colors.green.shade800 : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _assertionHeld ? 'Foreground Active' : 'Foreground Inactive',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _assertionHeld ? Colors.green.shade800 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: total > 0 ? progressRatio : null,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Remaining: $_unfinished', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      Text('isSubmitted: ${_tracker.isSubmitted}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Simulation Action Buttons
          Text('Simulation Actions', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: isRunning ? null : _simulateBatchEnqueue,
            icon: const Icon(Icons.bolt),
            label: const Text('⚡ Enqueue 9 Photos (Rapid IPC Coalescing)'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isRunning ? _add3Items : null,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('➕ Add 3 Mid-flight'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isRunning ? _cancelAll : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('🛑 Stop All'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 3. Realtime Event Logs
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Realtime Event Logs', style: Theme.of(context).textTheme.titleSmall),
              TextButton(
                onPressed: () => setState(_logs.clear),
                child: const Text('Clear Logs'),
              ),
            ],
          ),
          const Divider(),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            padding: const EdgeInsets.all(8),
            child: _logs.isEmpty
                ? const Center(child: Text('No logs yet. Tap an action above to start.'))
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(_logs[index], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. Manual Demo Tab (Low-Level ContinuedTask.start Direct Control)
// ============================================================================

class ManualDemoTab extends StatefulWidget {
  const ManualDemoTab({super.key});

  @override
  State<ManualDemoTab> createState() => _ManualDemoTabState();
}

class _ManualDemoTabState extends State<ManualDemoTab> {
  static const int _totalUnits = 60;

  ContinuedTask? _task;
  Timer? _ticker;

  int _done = 0;
  bool _assertionHeld = false;
  final List<String> _events = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_syncNativeState());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _syncNativeState() async {
    final state = await ContinuedTask.syncNativeState();
    if (!mounted || state == null) return;
    setState(() {
      _assertionHeld = state.assertionHeld;
      _log('syncState: assertionHeld=${state.assertionHeld} stopRequested=${state.stopRequested}');
    });
    if (state.stopRequested) {
      await ContinuedTask.ackStopRequest();
      _log('Acknowledged pending stop request');
    }
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, message);
      if (_events.length > 15) _events.removeLast();
    });
  }

  Future<void> _start() async {
    final task = await ContinuedTask.start(
      config: const ContinuedTaskConfig(
        taskId: 'manual_example_task',
        title: 'Manual Task in Progress',
        subtitle: '0/$_totalUnits',
        maxProgress: _totalUnits,
        allowCancel: true,
        cancelActionLabel: 'Cancel',
        iosTaskIdentifier: 'dev.flutter.flutterContinuedTaskExample.task',
      ),
      onUserCancel: () {
        _log('User cancel received');
        unawaited(_stop());
      },
      onTimeout: () {
        _log('OS timeout received');
        _ticker?.cancel();
      },
      onAssertionChanged: (held) {
        _log('Assertion changed: $held');
        if (mounted) setState(() => _assertionHeld = held);
      },
    );

    if (task == null) {
      _log('Start rejected (e.g. background execution restricted)');
      return;
    }

    setState(() {
      _task = task;
      _done = 0;
    });
    _log('Task started');
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 2000), (timer) async {
      final task = _task;
      if (task == null || task.isStopped) {
        timer.cancel();
        return;
      }
      if (_done >= _totalUnits) {
        timer.cancel();
        await _stop();
        _log('Completed');
        return;
      }
      setState(() => _done++);
      await task.update(progress: _done, subtitle: '$_done/$_totalUnits');
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    await ContinuedTask.stopCurrentTask(taskId: 'manual_example_task');
    if (!mounted) return;
    setState(() => _task = null);
  }

  @override
  Widget build(BuildContext context) {
    final running = _task != null && !(_task?.isStopped ?? true);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: _done / _totalUnits),
          const SizedBox(height: 8),
          Text('$_done / $_totalUnits', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Foreground Assertion: ${_assertionHeld ? "Active" : "Inactive"}', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: running ? null : _start,
                  child: const Text('Manual Start'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: running ? _stop : null,
                  child: const Text('Manual Stop'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Event Logs'),
          const Divider(),
          Container(
            height: 250,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) => Text(_events[index]),
            ),
          ),
        ],
      ),
    );
  }
}

