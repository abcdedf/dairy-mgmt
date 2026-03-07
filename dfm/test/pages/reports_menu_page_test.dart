import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dairy_mgmt/pages/reports_menu_page.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUp(() {
    cleanupTestState();
  });

  tearDown(() {
    cleanupTestState();
  });

  group('ReportsMenuPage — standard user', () {
    testWidgets('shows 5 report cards, hides finance cards', (tester) async {
      setupPermissions(canFinance: false);
      await tester.pumpPage(const ReportsMenuPage());

      // Visible cards
      expect(find.text('Daily Sales Summary'), findsOneWidget);
      expect(find.text('Sales Transactions'), findsOneWidget);
      expect(find.text('Production Transactions'), findsOneWidget);
      expect(find.text('Vendor Purchase Report'), findsOneWidget);
      expect(find.text('Stock'), findsOneWidget);

      // Finance-only cards hidden (not in tree at all)
      expect(find.text('Vendor Ledger', skipOffstage: false), findsNothing);
      expect(find.text('Funds Report', skipOffstage: false), findsNothing);
      expect(find.text('Stock Valuation', skipOffstage: false), findsNothing);

      // Exactly 5 Card widgets (including offstage)
      expect(find.byType(Card, skipOffstage: false), findsNWidgets(5));
    });
  });

  group('ReportsMenuPage — finance user', () {
    testWidgets('shows all 8 report cards', (tester) async {
      setupPermissions(canFinance: true);
      await tester.pumpPage(const ReportsMenuPage());

      // All 8 cards in widget tree (some may be offstage due to ListView)
      expect(find.byType(Card, skipOffstage: false), findsNWidgets(8));

      // All titles present in tree
      expect(find.text('Daily Sales Summary', skipOffstage: false), findsOneWidget);
      expect(find.text('Sales Transactions', skipOffstage: false), findsOneWidget);
      expect(find.text('Production Transactions', skipOffstage: false), findsOneWidget);
      expect(find.text('Vendor Purchase Report', skipOffstage: false), findsOneWidget);
      expect(find.text('Stock', skipOffstage: false), findsOneWidget);
      expect(find.text('Vendor Ledger', skipOffstage: false), findsOneWidget);
      expect(find.text('Funds Report', skipOffstage: false), findsOneWidget);
      expect(find.text('Stock Valuation', skipOffstage: false), findsOneWidget);
    });
  });

  group('ReportsMenuPage — label verification', () {
    testWidgets('subtitles render correctly', (tester) async {
      setupPermissions(canFinance: true);
      await tester.pumpPage(const ReportsMenuPage());

      expect(find.text('Product-wise sales aggregated by date — last 30 days', skipOffstage: false), findsOneWidget);
      expect(find.text('Every sale entry with customer, qty, rate and user — last 7 days', skipOffstage: false), findsOneWidget);
      expect(find.text('All production entries with quantities and user — last 7 days', skipOffstage: false), findsOneWidget);
      expect(find.text('All purchases by vendor with product, qty, rate and amount', skipOffstage: false), findsOneWidget);
      expect(find.text('30-day running stock balance across all products', skipOffstage: false), findsOneWidget);
      expect(find.text('Payment tracking — purchases, payments and balance due per vendor', skipOffstage: false), findsOneWidget);
      expect(find.text('Sales revenue, stock value, vendor dues and free cash', skipOffstage: false), findsOneWidget);
      expect(find.text('Stock quantities with estimated values per product', skipOffstage: false), findsOneWidget);
    });
  });
}
