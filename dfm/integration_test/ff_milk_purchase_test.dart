// integration_test/ff_milk_purchase_test.dart
//
// End-to-end integration test:
//   Login → FF Milk Purchase → verify form cleared → navigate to Stock → verify balance.
// Hits the live backend — requires network access.
//
// Run:
//   chromedriver --port=4444 &
//   cd dfm
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/ff_milk_purchase_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';

import 'package:dairy_mgmt/main.dart' as app;
import 'package:dairy_mgmt/controllers/stock_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FF Milk Purchase — login, save, verify stock updated',
      (tester) async {
    // 1. Launch app
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // ── LOGIN ─────────────────────────────────────────────────────
    final userField = find.widgetWithText(TextFormField, 'Username');
    final passField = find.widgetWithText(TextFormField, 'Password');
    expect(userField, findsOneWidget, reason: 'Username field not found');
    expect(passField, findsOneWidget, reason: 'Password field not found');

    // Set credentials via --dart-define=DFM_TEST_USER=... --dart-define=DFM_TEST_PASS=...
    const testUser = String.fromEnvironment('DFM_TEST_USER');
    const testPass = String.fromEnvironment('DFM_TEST_PASS');
    assert(testUser.isNotEmpty && testPass.isNotEmpty,
        'Set DFM_TEST_USER and DFM_TEST_PASS via --dart-define');
    await tester.enterText(userField, testUser);
    await tester.enterText(passField, testPass);

    final signInBtn = find.widgetWithText(ElevatedButton, 'Sign In');
    await tester.tap(signInBtn);
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // Should be on /home with ProductionPage (first tab)
    expect(find.text('FF Milk Purchase'), findsWidgets,
        reason: 'ProductionPage with FF Milk Purchase form not found');

    // ── RECORD STOCK BEFORE SAVE ──────────────────────────────────
    // Navigate to Reports → Stock to read current FF Milk balance for today.
    final reportsTab = find.text('Reports');
    expect(reportsTab, findsOneWidget, reason: 'Reports tab not found');
    await tester.tap(reportsTab);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Tap the Stock card
    final stockCard = find.text('Stock');
    expect(stockCard, findsWidgets, reason: 'Stock card not found');
    await tester.tap(stockCard.last); // last = the card title (not the appbar)
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // Read today's FF Milk value from the StockController
    final stockCtrl = Get.find<StockController>();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayRow = stockCtrl.stockDays
        .firstWhereOrNull((d) => d.date == todayStr);
    final ffMilkBefore = todayRow?.stocks[1] ?? 0; // product_id 1 = FF Milk
    debugPrint('[TEST] FF Milk stock BEFORE save: $ffMilkBefore');

    // Go back to home
    final backBtn = find.byTooltip('Back');
    await tester.tap(backBtn);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // ── SWITCH TO PRODUCTION TAB ──────────────────────────────────
    final productionTab = find.text('Production');
    await tester.tap(productionTab);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // ── FILL FF MILK PURCHASE FORM ────────────────────────────────
    final ffMilkField = find.widgetWithText(TextFormField, 'FF Milk');
    final rateField = find.widgetWithText(TextFormField, 'Rate');
    final snfField = find.widgetWithText(TextFormField, 'SNF');
    final fatField = find.widgetWithText(TextFormField, 'Fat');

    expect(ffMilkField, findsOneWidget, reason: 'FF Milk field not found');
    expect(rateField, findsOneWidget, reason: 'Rate field not found');
    expect(snfField, findsOneWidget, reason: 'SNF field not found');
    expect(fatField, findsOneWidget, reason: 'Fat field not found');

    await tester.enterText(ffMilkField, '100');
    await tester.enterText(rateField, '50');
    await tester.enterText(snfField, '8.5');
    await tester.enterText(fatField, '6.5');

    // ── SAVE ──────────────────────────────────────────────────────
    final saveBtn = find.widgetWithText(ElevatedButton, 'Save');
    await tester.tap(saveBtn);
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // Verify form fields cleared (confirms save succeeded)
    final ffMilkWidget = tester.widget<TextFormField>(ffMilkField);
    final rateWidget = tester.widget<TextFormField>(rateField);
    expect(ffMilkWidget.controller?.text, isEmpty,
        reason: 'FF Milk field should be cleared after save');
    expect(rateWidget.controller?.text, isEmpty,
        reason: 'Rate field should be cleared after save');

    // Confirm no error banner
    expect(find.text('Save failed.'), findsNothing);
    expect(find.text('Database error.'), findsNothing);

    // ── VERIFY STOCK AFTER SAVE ───────────────────────────────────
    // Navigate back to Reports → Stock
    await tester.tap(reportsTab);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.text('Stock').last);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // StockController is a GetX singleton — onInit won't re-run on second
    // visit. Explicitly refresh to get the latest data from the backend.
    final stockCtrl2 = Get.find<StockController>();
    await stockCtrl2.fetchStock();
    await tester.pumpAndSettle(const Duration(seconds: 10));

    final todayRow2 = stockCtrl2.stockDays
        .firstWhereOrNull((d) => d.date == todayStr);
    final ffMilkAfter = todayRow2?.stocks[1] ?? 0;
    debugPrint('[TEST] FF Milk stock AFTER save: $ffMilkAfter');

    // FF Milk stock should have increased by 100
    expect(ffMilkAfter, equals(ffMilkBefore + 100),
        reason: 'FF Milk stock should increase by 100 after purchase');
  });
}
