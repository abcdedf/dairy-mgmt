// Tests that all report controllers fetch fresh data on creation (simulating
// page revisit). Each report page uses StatefulWidget + Get.delete/Get.put
// so the controller is recreated every time the user navigates to the page.
//
// These tests verify:
// 1. Controller fetches data in onInit
// 2. Creating a second controller instance fetches again (simulating revisit)
// 3. The second instance sees updated data, not stale data

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/controllers/stock_controller.dart';
import 'package:dairy_mgmt/controllers/funds_report_controller.dart';
import 'package:dairy_mgmt/controllers/stock_valuation_controller.dart';
import 'package:dairy_mgmt/controllers/vendor_ledger_controller.dart';
import 'package:dairy_mgmt/controllers/pouch_stock_controller.dart';
import 'package:dairy_mgmt/controllers/pouch_type_controller.dart';
import 'package:dairy_mgmt/controllers/madhusudan_pnl_controller.dart';
import 'package:dairy_mgmt/controllers/pouch_pnl_controller.dart';
import 'package:dairy_mgmt/controllers/sales_report_controller.dart';
import 'package:dairy_mgmt/controllers/vendor_purchase_report_controller.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

/// Let async onInit settle.
Future<void> _settle() async {
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
}

void main() {
  late FakeApiClient fake;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  // ── Stock ──────────────────────────────────────────────────

  group('StockController refreshes on recreate', () {
    ApiResponse _stockResponse(int ffMilk) => ApiResponse.success(
      statusCode: 200,
      data: {
        'products': [
          {'id': '1', 'name': 'FF Milk', 'unit': 'KG'},
        ],
        'dates': [
          {'date': '2026-03-11', 'stocks': {'1': ffMilk}},
        ],
        'from': '2026-02-10',
        'to': '2026-03-11',
      },
    );

    test('second controller instance sees updated data', () async {
      fake.onGet('/stock', _stockResponse(100));
      final ctrl1 = Get.put(StockController());
      await _settle();
      expect(ctrl1.stockDays.isNotEmpty, true);
      expect(ctrl1.stockDays.last.stocks[1], 100);

      // Simulate page revisit: delete + recreate with new data
      Get.delete<StockController>(force: true);
      fake.onGet('/stock', _stockResponse(250));
      final ctrl2 = Get.put(StockController());
      await _settle();
      expect(ctrl2.stockDays.last.stocks[1], 250);
    });
  });

  // ── Funds Report ───────────────────────────────────────────

  group('FundsReportController refreshes on recreate', () {
    ApiResponse _fundsResponse(double totalSales) => ApiResponse.success(
      statusCode: 200,
      data: {
        'total_sales': totalSales,
        'total_stock_value': 0,
        'total_vendor_dues': 0,
        'free_cash': totalSales,
      },
    );

    test('second controller instance sees updated data', () async {
      fake.onGet('/funds-report', _fundsResponse(1000.0));
      final ctrl1 = Get.put(FundsReportController());
      await _settle();
      expect(ctrl1.report.value, isNotNull);

      Get.delete<FundsReportController>(force: true);
      fake.onGet('/funds-report', _fundsResponse(5000.0));
      final ctrl2 = Get.put(FundsReportController());
      await _settle();
      expect(ctrl2.report.value, isNotNull);
      // Verify it fetched twice (once per creation)
      final fundsCalls = fake.calls.where((c) => c.path.startsWith('/funds-report')).toList();
      expect(fundsCalls.length, 2);
    });
  });

  // ── Stock Valuation ────────────────────────────────────────

  group('StockValuationController refreshes on recreate', () {
    test('second controller instance fetches again', () async {
      fake.onGet('/stock-valuation', ApiResponse.success(
        statusCode: 200,
        data: [
          {'product_id': '1', 'product_name': 'FF Milk', 'stock': '100', 'rate': '50.00', 'value': '5000.00'},
        ],
      ));

      final ctrl1 = Get.put(StockValuationController());
      await _settle();
      expect(ctrl1.rows.length, 1);

      Get.delete<StockValuationController>(force: true);
      fake.onGet('/stock-valuation', ApiResponse.success(
        statusCode: 200,
        data: [
          {'product_id': '1', 'product_name': 'FF Milk', 'stock': '200', 'rate': '50.00', 'value': '10000.00'},
          {'product_id': '2', 'product_name': 'Skim Milk', 'stock': '50', 'rate': '30.00', 'value': '1500.00'},
        ],
      ));
      final ctrl2 = Get.put(StockValuationController());
      await _settle();
      expect(ctrl2.rows.length, 2);
    });
  });

  // ── Vendor Ledger ──────────────────────────────────────────

  group('VendorLedgerController refreshes on recreate', () {
    test('second controller instance fetches again', () async {
      fake.onGet('/vendor-ledger', ApiResponse.success(
        statusCode: 200,
        data: {
          'vendors': [
            {'vendor_id': '1', 'vendor_name': 'V1', 'total_purchases': '1000.00', 'total_payments': '500.00', 'balance': '500.00'},
          ],
        },
      ));

      final ctrl1 = Get.put(VendorLedgerController());
      await _settle();
      expect(ctrl1.vendors.length, 1);

      Get.delete<VendorLedgerController>(force: true);
      fake.onGet('/vendor-ledger', ApiResponse.success(
        statusCode: 200,
        data: {
          'vendors': [
            {'vendor_id': '1', 'vendor_name': 'V1', 'total_purchases': '2000.00', 'total_payments': '500.00', 'balance': '1500.00'},
            {'vendor_id': '2', 'vendor_name': 'V2', 'total_purchases': '500.00', 'total_payments': '0.00', 'balance': '500.00'},
          ],
        },
      ));
      final ctrl2 = Get.put(VendorLedgerController());
      await _settle();
      expect(ctrl2.vendors.length, 2);
    });
  });

  // ── Pouch Stock ────────────────────────────────────────────

  group('PouchStockController refreshes on recreate', () {
    test('second controller instance sees updated crate counts', () async {
      fake.onGet('/pouch-stock', ApiResponse.success(statusCode: 200, data: [
        {'pouch_type_id': '1', 'name': '500ml', 'milk_per_pouch': '0.50', 'pouches_per_crate': '20', 'crate_count': '10'},
      ]));

      final ctrl1 = Get.put(PouchStockController());
      await _settle();
      expect(ctrl1.pouchStock.first.crateCount, 10);

      Get.delete<PouchStockController>(force: true);
      fake.onGet('/pouch-stock', ApiResponse.success(statusCode: 200, data: [
        {'pouch_type_id': '1', 'name': '500ml', 'milk_per_pouch': '0.50', 'pouches_per_crate': '20', 'crate_count': '25'},
      ]));
      final ctrl2 = Get.put(PouchStockController());
      await _settle();
      expect(ctrl2.pouchStock.first.crateCount, 25);
    });
  });

  // ── Pouch Type ─────────────────────────────────────────────

  group('PouchTypeController refreshes on recreate', () {
    test('second controller instance sees newly added types', () async {
      fake.onGet('/pouch-types', ApiResponse.success(statusCode: 200, data: [
        {'id': '1', 'name': '500ml', 'milk_per_pouch': '0.50', 'pouches_per_crate': '20', 'is_active': '1'},
      ]));

      final ctrl1 = Get.put(PouchTypeController());
      await _settle();
      expect(ctrl1.pouchTypes.length, 1);

      Get.delete<PouchTypeController>(force: true);
      fake.onGet('/pouch-types', ApiResponse.success(statusCode: 200, data: [
        {'id': '1', 'name': '500ml', 'milk_per_pouch': '0.50', 'pouches_per_crate': '20', 'is_active': '1'},
        {'id': '2', 'name': '1L', 'milk_per_pouch': '1.00', 'pouches_per_crate': '12', 'is_active': '1'},
      ]));
      final ctrl2 = Get.put(PouchTypeController());
      await _settle();
      expect(ctrl2.pouchTypes.length, 2);
    });
  });

  // ── Madhusudan P&L ─────────────────────────────────────────

  group('MadhusudanPnlController refreshes on recreate', () {
    test('second controller instance sees new rows', () async {
      fake.onGet('/madhusudan-pnl', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {'id': '1', 'entry_date': '2026-03-10', 'total_ff_milk_kg': '100', 'sale_rate': '50.00', 'revenue': '5000.00', 'cost': '4000.00', 'profit': '1000.00'},
        ],
        'totals': {'total_ff_milk_kg': '100', 'revenue': '5000.00', 'cost': '4000.00', 'profit': '1000.00'},
      }));

      final ctrl1 = Get.put(MadhusudanPnlController());
      await _settle();
      expect(ctrl1.rows.length, 1);

      Get.delete<MadhusudanPnlController>(force: true);
      fake.onGet('/madhusudan-pnl', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {'id': '1', 'entry_date': '2026-03-10', 'total_ff_milk_kg': '100', 'sale_rate': '50.00', 'revenue': '5000.00', 'cost': '4000.00', 'profit': '1000.00'},
          {'id': '2', 'entry_date': '2026-03-11', 'total_ff_milk_kg': '200', 'sale_rate': '55.00', 'revenue': '11000.00', 'cost': '8000.00', 'profit': '3000.00'},
        ],
        'totals': {'total_ff_milk_kg': '300', 'revenue': '16000.00', 'cost': '12000.00', 'profit': '4000.00'},
      }));
      final ctrl2 = Get.put(MadhusudanPnlController());
      await _settle();
      expect(ctrl2.rows.length, 2);
    });
  });

  // ── Pouch P&L ──────────────────────────────────────────────

  group('PouchPnlController refreshes on recreate', () {
    test('second controller instance sees new rows', () async {
      fake.onGet('/pouch-pnl', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {'id': '1', 'entry_date': '2026-03-10', 'total_crates': '10', 'revenue': '5000.00', 'cost': '3000.00', 'profit': '2000.00'},
        ],
        'totals': {'total_crates': '10', 'revenue': '5000.00', 'cost': '3000.00', 'profit': '2000.00'},
      }));

      final ctrl1 = Get.put(PouchPnlController());
      await _settle();
      expect(ctrl1.rows.length, 1);

      Get.delete<PouchPnlController>(force: true);
      fake.onGet('/pouch-pnl', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {'id': '1', 'entry_date': '2026-03-10', 'total_crates': '10', 'revenue': '5000.00', 'cost': '3000.00', 'profit': '2000.00'},
          {'id': '2', 'entry_date': '2026-03-11', 'total_crates': '15', 'revenue': '7500.00', 'cost': '4500.00', 'profit': '3000.00'},
        ],
        'totals': {'total_crates': '25', 'revenue': '12500.00', 'cost': '7500.00', 'profit': '5000.00'},
      }));
      final ctrl2 = Get.put(PouchPnlController());
      await _settle();
      expect(ctrl2.rows.length, 2);
    });
  });

  // ── Sales Report ───────────────────────────────────────────

  group('SalesReportController refreshes on recreate', () {
    test('second controller instance fetches again', () async {
      fake.onGet('/sales-report', ApiResponse.success(statusCode: 200, data: {
        'rows': [],
        'products': [],
      }));

      final ctrl1 = Get.put(SalesReportController());
      await _settle();

      Get.delete<SalesReportController>(force: true);
      final ctrl2 = Get.put(SalesReportController());
      await _settle();

      final reportCalls = fake.calls.where((c) => c.path.startsWith('/sales-report')).toList();
      expect(reportCalls.length, 2, reason: 'Should fetch on each creation');
    });
  });

  // ── Vendor Purchase Report ─────────────────────────────────

  group('VendorPurchaseReportController refreshes on recreate', () {
    test('second controller instance fetches again', () async {
      fake.onGet('/vendor-purchase-report', ApiResponse.success(statusCode: 200, data: []));

      final ctrl1 = Get.put(VendorPurchaseReportController());
      await _settle();

      Get.delete<VendorPurchaseReportController>(force: true);
      final ctrl2 = Get.put(VendorPurchaseReportController());
      await _settle();

      final reportCalls = fake.calls.where((c) => c.path.startsWith('/vendor-purchase-report')).toList();
      expect(reportCalls.length, 2, reason: 'Should fetch on each creation');
    });
  });
}
