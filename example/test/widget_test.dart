import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_continued_task_example/main.dart';

void main() {
  testWidgets('예제 앱이 뜨고 시작 버튼이 활성 상태다', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('0 / 20'), findsOneWidget);
    expect(find.text('시작'), findsOneWidget);
    expect(find.text('수명 확보: 없음'), findsOneWidget);
  });
}
