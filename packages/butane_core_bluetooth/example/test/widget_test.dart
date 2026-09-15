import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:butane_core_bluetooth_example/main.dart';

void main() {
  const MethodChannel channel = MethodChannel('butane_core_bluetooth');
  const String platformVersion = 'Mock platform 1.0';

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'getPlatformVersion');
      return platformVersion;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('Verify Platform version', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Running on: Mock platform 1.0'), findsOneWidget);
  });
}
