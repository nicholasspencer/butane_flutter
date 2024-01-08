import 'package:flutter_test/flutter_test.dart';

import 'package:butane_example/main.dart';

void main() {
  testWidgets('Test something in the future', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
  });
}
