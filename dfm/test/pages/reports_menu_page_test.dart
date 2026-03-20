import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/pages/reports_menu_page.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

/// The full menu items the server would return (matching the registry keys in
/// reports_menu_page.dart). The test stubs the /report-menu endpoint with these.
List<Map<String, dynamic>> _allMenuItems() => [
  {'key': 'daily_product_sales', 'label': 'Daily Sales Summary', 'subtitle': 'Product-wise sales aggregated by date — last 30 days', 'permission': 'all'},
  {'key': 'daily_customer_sales', 'label': 'Daily Customer Sales', 'subtitle': 'Sales by customer with product, qty, rate and amount', 'permission': 'all'},
  {'key': 'sales_transactions', 'label': 'Sales Transactions', 'subtitle': 'Every sale entry with customer, qty, rate and user — last 7 days', 'permission': 'all'},
  {'key': 'production_transactions', 'label': 'Production Transactions', 'subtitle': 'All production entries with quantities and user — last 7 days', 'permission': 'all'},
  {'key': 'vendor_purchase_report', 'label': 'Vendor Purchase Report', 'subtitle': 'All purchases by vendor with product, qty, rate and amount', 'permission': 'all'},
  {'key': 'stock', 'label': 'Stock', 'subtitle': '30-day running stock balance across all products', 'permission': 'all'},
  {'key': 'stock_flow', 'label': 'Stock Flow', 'subtitle': 'Daily stock movements — inflows and outflows by product', 'permission': 'all'},
  {'key': 'pouch_stock', 'label': 'Pouch Stock', 'subtitle': 'Current pouch stock by type in crates', 'permission': 'all'},
  {'key': 'vendor_ledger', 'label': 'Vendor Ledger', 'subtitle': 'Payment tracking — purchases, payments and balance due per vendor', 'permission': 'finance'},
  {'key': 'cashflow_report', 'label': 'Cashflow Report', 'subtitle': 'Sales revenue, stock value, vendor dues and free cash', 'permission': 'finance'},
  {'key': 'profitability_report', 'label': 'Profitability Report', 'subtitle': 'Revenue, cost and profit analysis', 'permission': 'finance'},
  {'key': 'stock_valuation', 'label': 'Stock Valuation', 'subtitle': 'Stock quantities with estimated values per product', 'permission': 'finance'},
  {'key': 'cash_stock_report', 'label': 'Cash & Stock Report', 'subtitle': 'Combined cash and stock position', 'permission': 'finance'},
];

void main() {
  late FakeApiClient fake;

  setUp(() {
    fake = setupFakeApi();
  });

  tearDown(() {
    cleanupTestState();
  });

  group('ReportsMenuPage — standard user', () {
    testWidgets('shows standard report cards, hides finance cards', (tester) async {
      setupPermissions(canFinance: false);
      fake.onGet('/report-menu', ApiResponse.success(
        statusCode: 200,
        data: _allMenuItems(),
      ));

      await tester.pumpPage(const ReportsMenuPage());
      await tester.pumpAndSettle();

      // Visible cards (standard user sees non-finance items)
      expect(find.text('Daily Sales Summary', skipOffstage: false), findsOneWidget);
      expect(find.text('Sales Transactions', skipOffstage: false), findsOneWidget);
      expect(find.text('Production Transactions', skipOffstage: false), findsOneWidget);
      expect(find.text('Vendor Purchase Report', skipOffstage: false), findsOneWidget);
      expect(find.text('Stock', skipOffstage: false), findsOneWidget);

      // Finance-only cards hidden
      expect(find.text('Vendor Ledger', skipOffstage: false), findsNothing);
      expect(find.text('Cashflow Report', skipOffstage: false), findsNothing);
      expect(find.text('Stock Valuation', skipOffstage: false), findsNothing);

      // Count standard cards (all non-finance items with matching registry keys)
      final standardCount = _allMenuItems().where((m) => m['permission'] != 'finance').length;
      expect(find.byType(Card, skipOffstage: false), findsNWidgets(standardCount));
    });
  });

  group('ReportsMenuPage — finance user', () {
    testWidgets('shows all report cards', (tester) async {
      // Use a large surface so GridView.builder renders all items
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      setupPermissions(canFinance: true);
      fake.onGet('/report-menu', ApiResponse.success(
        statusCode: 200,
        data: _allMenuItems(),
      ));

      await tester.pumpPage(const ReportsMenuPage());
      await tester.pumpAndSettle();

      // All cards in widget tree
      final totalCount = _allMenuItems().length;
      expect(find.byType(Card, skipOffstage: false), findsNWidgets(totalCount));

      // All titles present
      expect(find.text('Daily Sales Summary', skipOffstage: false), findsOneWidget);
      expect(find.text('Sales Transactions', skipOffstage: false), findsOneWidget);
      expect(find.text('Production Transactions', skipOffstage: false), findsOneWidget);
      expect(find.text('Vendor Purchase Report', skipOffstage: false), findsOneWidget);
      expect(find.text('Stock', skipOffstage: false), findsOneWidget);
      expect(find.text('Vendor Ledger', skipOffstage: false), findsOneWidget);
      expect(find.text('Cashflow Report', skipOffstage: false), findsOneWidget);
      expect(find.text('Stock Valuation', skipOffstage: false), findsOneWidget);
    });
  });

  group('ReportsMenuPage — label verification', () {
    testWidgets('subtitles render correctly', (tester) async {
      setupPermissions(canFinance: true);
      fake.onGet('/report-menu', ApiResponse.success(
        statusCode: 200,
        data: _allMenuItems(),
      ));

      await tester.pumpPage(const ReportsMenuPage());
      await tester.pumpAndSettle();

      expect(find.text('Product-wise sales aggregated by date — last 30 days', skipOffstage: false), findsOneWidget);
      expect(find.text('Every sale entry with customer, qty, rate and user — last 7 days', skipOffstage: false), findsOneWidget);
      expect(find.text('All production entries with quantities and user — last 7 days', skipOffstage: false), findsOneWidget);
      expect(find.text('All purchases by vendor with product, qty, rate and amount', skipOffstage: false), findsOneWidget);
      expect(find.text('30-day running stock balance across all products', skipOffstage: false), findsOneWidget);
      expect(find.text('Payment tracking — purchases, payments and balance due per vendor', skipOffstage: false), findsOneWidget);
      expect(find.text('Stock quantities with estimated values per product', skipOffstage: false), findsOneWidget);
    });
  });
}
