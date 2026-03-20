import 'package:flutter_test/flutter_test.dart';
import 'package:dairy_mgmt/main.dart';

void main() {
  testWidgets('DairyApp can be instantiated', (WidgetTester tester) async {
    // Smoke test: verify the app widget can be created without errors.
    const app = DairyApp();
    expect(app, isA<DairyApp>());
  });
}
