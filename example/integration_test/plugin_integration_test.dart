import 'package:flutter_continued_task/flutter_continued_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// 실기기·에뮬레이터에서 **네이티브 채널이 실제로 응답하는지**를 본다.
// 호스트 단위 테스트는 채널을 가짜로 대체하므로 이 층을 못 덮는다 —
// 존재하지 않는 네이티브 API나 미등록 채널은 여기서만 드러난다.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('syncState가 네이티브에서 실제 응답을 받는다', (tester) async {
    final state = await FlutterContinuedTask.syncNativeState();

    // 지원 OS면 값이 오고, 미지원이면 null이 온다. 어느 쪽이든 **던지지 않는다**
    // — 지원 여부 분기는 예외가 아니라 값으로 처리한다는 계약이다.
    if (state != null) {
      expect(state.assertionHeld, isA<bool>());
      expect(state.stopRequested, isA<bool>());
    }
  });

  testWidgets('중단 확인 처리는 태스크가 없어도 안전하다', (tester) async {
    await expectLater(FlutterContinuedTask.ackStopRequest(), completes);
  });

  testWidgets('실행 중인 태스크가 없을 때 중단은 무해하다', (tester) async {
    await expectLater(FlutterContinuedTask.stopCurrentTask(), completes);
    expect(FlutterContinuedTask.currentTask, isNull);
  });
}
