import 'package:flutter_continued_task/flutter_continued_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Verifies that native channels respond on real devices and emulators.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('syncState receives valid native response without throwing', (tester) async {
    final state = await FlutterContinuedTask.syncNativeState();

    // Returns state on supported platforms or null on unsupported; never throws.
    if (state != null) {
      expect(state.assertionHeld, isA<bool>());
      expect(state.stopRequested, isA<bool>());
    }
  });

  testWidgets('ackStopRequest is safe even when no task is active', (tester) async {
    await expectLater(FlutterContinuedTask.ackStopRequest(), completes);
  });

  testWidgets('stopCurrentTask is safe and no-op when no task is running', (tester) async {
    await expectLater(FlutterContinuedTask.stopCurrentTask(), completes);
    expect(FlutterContinuedTask.currentTask, isNull);
  });
}
