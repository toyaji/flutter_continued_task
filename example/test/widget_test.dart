import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_continued_task_example/main.dart';

void main() {
  testWidgets('renders example app dashboard correctly', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('flutter_continued_task Example'), findsOneWidget);
    expect(find.text('TaskTracker (Auto)'), findsOneWidget);
    expect(find.text('ContinuedTask (Manual)'), findsOneWidget);
    expect(find.text('Progress: 0 / 0'), findsOneWidget);
  });
}
