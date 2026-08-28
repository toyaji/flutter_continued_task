import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_continued_task/flutter_continued_task.dart';

/// Real-device harness for the questions no documentation answers:
///
/// * do two (three, four) tasks really run at the same time?
/// * does each notification's Cancel stop only its own task?
/// * at what point does the system fold the notifications into a bundle?
/// * what happens when a notification is swiped away?
/// * does a single task still behave exactly like 0.1.x?
///
/// Every observation lands in the log, so a tester can read the answers off the
/// screen instead of inferring them.
class ConcurrentDemoTab extends StatefulWidget {
  const ConcurrentDemoTab({super.key});

  @override
  State<ConcurrentDemoTab> createState() => _ConcurrentDemoTabState();
}

class _ConcurrentDemoTabState extends State<ConcurrentDemoTab> {
  static const List<_TaskSpec> _specs = <_TaskSpec>[
    // Every task uses the same icon on purpose: concurrent tasks in a real app
    // are usually the same kind of work, and the status bar reads better when
    // they match. The notification title is what tells them apart.
    _TaskSpec('slot_a', 'Photos', 'upload', 'photo_upload'),
    _TaskSpec('slot_b', 'Videos', 'upload', 'video_upload'),
    _TaskSpec('slot_c', 'Backup', 'upload', 'backup'),
    _TaskSpec('slot_d', 'Cleanup', 'upload', 'cleanup'),
  ];

  final Map<String, TaskTracker> _trackers = <String, TaskTracker>{};
  final Map<String, int> _remaining = <String, int>{};
  final Map<String, bool> _held = <String, bool>{};
  final Map<String, Timer> _timers = <String, Timer>{};
  final List<String> _logs = <String>[];

  @override
  void initState() {
    super.initState();
    ContinuedTask.requestNotificationPermission().then((granted) {
      _log(
        granted
            ? '🔔 Notification permission granted'
            : '🔕 Notification permission DENIED — notifications will not appear, '
                  'only the Task Manager entry (per-task Cancel becomes impossible)',
      );
    });
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    for (final tracker in _trackers.values) {
      unawaited(tracker.dispose());
    }
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() => _logs.insert(0, message));
  }

  TaskTracker _trackerFor(_TaskSpec spec) {
    return _trackers.putIfAbsent(spec.id, () {
      return ContinuedTask.track(
        title: spec.label,
        // The point of the harness: without this the second task would stop
        // the first, which is the 0.1.x behaviour every existing app relies on.
        allowConcurrent: true,
        baseConfig: ContinuedTaskConfig(
          taskId: spec.id,
          androidNotificationIcon: spec.icon,
          androidChannelId: spec.channelId,
          androidChannelName: spec.label,
          androidChannelDescription: '${spec.label} progress',
          cancelActionLabel: 'Stop ${spec.label}',
        ),
        onUserCancel: () async {
          // If this fires for a task whose notification you did NOT tap, the
          // per-task event routing is broken.
          _log('🛑 [${spec.label}] Cancel tapped on ITS notification');
          await _stop(spec);
        },
        onAssertionChanged: (held) {
          _held[spec.id] = held;
          _log(
            '${held ? "✅" : "⚪️"} [${spec.label}] assertion ${held ? "held" : "released"}',
          );
        },
        onTimeout: () => _log('⏰ [${spec.label}] OS timeout'),
      );
    });
  }

  Future<void> _start(_TaskSpec spec, {int items = 600}) async {
    _remaining[spec.id] = items;
    await _trackerFor(spec).sync(items);
    _log('▶️ [${spec.label}] started with $items items');

    _timers[spec.id]?.cancel();
    _timers[spec.id] = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      final left = (_remaining[spec.id] ?? 0) - 1;
      _remaining[spec.id] = left;
      setState(() {});
      await _trackerFor(spec).sync(left < 0 ? 0 : left);
      if (left <= 0) {
        timer.cancel();
        _log('🏁 [${spec.label}] finished');
      }
    });
  }

  Future<void> _stop(_TaskSpec spec) async {
    _timers[spec.id]?.cancel();
    _remaining[spec.id] = 0;
    await _trackerFor(spec).cancel();
    setState(() {});
  }

  Future<void> _startMany(int count) async {
    for (var i = 0; i < count; i++) {
      await _start(_specs[i]);
    }
    _log(
      '📦 Started $count tasks — check how many notifications appear and '
      'whether the system bundled them',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Concurrent tasks',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Start several tasks, then check the notification shade: one '
          'notification per task, each with its own Stop button.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final count in [1, 2, 3, 4])
              FilledButton.tonal(
                onPressed: () => _startMany(count),
                child: Text('Start $count'),
              ),
            OutlinedButton(
              onPressed: () async {
                for (final spec in _specs) {
                  await _stop(spec);
                }
                _log('🧹 Stopped everything');
              },
              child: const Text('Stop all'),
            ),
          ],
        ),
        const Divider(height: 32),
        for (final spec in _specs)
          Card(
            child: ListTile(
              leading: Icon(
                _held[spec.id] == true
                    ? Icons.play_circle
                    : Icons.circle_outlined,
                color: _held[spec.id] == true ? Colors.green : Colors.grey,
              ),
              title: Text('${spec.label}  ·  ${spec.id}'),
              subtitle: Text('remaining ${_remaining[spec.id] ?? 0}'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => _start(spec),
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () => _stop(spec),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 32),
        const Text('Checklist', style: TextStyle(fontWeight: FontWeight.bold)),
        const _Checklist(
          items: [
            'Start 2 → two notifications, each with its own Stop button',
            'Tap Stop on one → only that task logs a cancel, the other keeps going',
            'Start 3 and 4 → note when the system folds them into a bundle',
            'Swipe one notification away → work continues and it does NOT come back',
            'Start 1 only → behaves exactly like the other tabs (0.1.x baseline)',
            'Deny notification permission → per-task Stop is no longer reachable',
            'Background the app → tasks keep running',
          ],
        ),
        const Divider(height: 32),
        const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final line in _logs.take(40))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

class _TaskSpec {
  const _TaskSpec(this.id, this.label, this.icon, this.channelId);

  final String id;
  final String label;
  final String icon;
  final String channelId;
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('☐ $item', style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
