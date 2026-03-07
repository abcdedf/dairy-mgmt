import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/controllers/vendor_ledger_controller.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late VendorLedgerController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  VendorLedgerController createController() {
    ctrl = Get.put(VendorLedgerController());
    return ctrl;
  }

  group('VendorLedgerController', () {
    test('fetchLedger populates vendors list', () async {
      fake.onGet('/vendor-ledger', ApiResponse.success(statusCode: 200, data: {
        'vendors': [
          {'vendor_id': 10, 'vendor_name': 'Vendor A', 'total_purchases': 50000.0, 'total_payments': 30000.0, 'balance_due': 20000.0},
          {'vendor_id': 11, 'vendor_name': 'Vendor B', 'total_purchases': 25000.0, 'total_payments': 25000.0, 'balance_due': 0.0},
        ],
      }));

      createController();
      await ctrl.fetchLedger();

      expect(ctrl.vendors.length, 2);
      expect(ctrl.vendors.first.vendorId, 10);
      expect(ctrl.vendors.first.vendorName, 'Vendor A');
      expect(ctrl.vendors.first.totalPurchases, 50000.0);
      expect(ctrl.vendors.first.totalPayments, 30000.0);
      expect(ctrl.vendors.first.balanceDue, 20000.0);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchLedger sets errorMessage on failure', () async {
      fake.onGet('/vendor-ledger', ApiResponse.error(
        statusCode: 500,
        message: 'Database error.',
      ));

      createController();
      await ctrl.fetchLedger();

      expect(ctrl.errorMessage.value, 'Database error.');
      expect(ctrl.vendors, isEmpty);
    });

    test('fetchDetail populates detail fields and transactions', () async {
      fake.onGet('/vendor-ledger-detail', ApiResponse.success(statusCode: 200, data: {
        'vendor_name': 'Vendor A',
        'total_purchases': 50000.0,
        'total_payments': 30000.0,
        'balance_due': 20000.0,
        'transactions': [
          {'type': 'purchase', 'date': '2026-03-04', 'product': 'FF Milk', 'quantity': 100, 'rate': 45.0, 'amount': 4500.0},
          {'type': 'payment', 'date': '2026-03-03', 'amount': 3000.0, 'method': 'cash'},
        ],
      }));

      createController();
      await ctrl.fetchDetail(10);

      expect(ctrl.detailVendorName.value, 'Vendor A');
      expect(ctrl.detailPurchases.value, 50000.0);
      expect(ctrl.detailPayments.value, 30000.0);
      expect(ctrl.detailBalance.value, 20000.0);
      expect(ctrl.transactions.length, 2);
      expect(ctrl.transactions.first.type, 'purchase');
      expect(ctrl.transactions.first.product, 'FF Milk');
      expect(ctrl.transactions.first.amount, 4500.0);
      expect(ctrl.transactions[1].type, 'payment');
      expect(ctrl.transactions[1].method, 'cash');
      expect(ctrl.isLoadingDetail.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchDetail sets errorMessage on failure', () async {
      fake.onGet('/vendor-ledger-detail', ApiResponse.error(
        statusCode: 500,
        message: 'Failed to load vendor details.',
      ));

      createController();
      await ctrl.fetchDetail(10);

      expect(ctrl.errorMessage.value, 'Failed to load vendor details.');
      expect(ctrl.transactions, isEmpty);
    });

    test('savePayment posts correct payload and returns true on success', () async {
      fake.onPost('/vendor-payment', ApiResponse.success(statusCode: 201, data: {'id': 1}));

      createController();
      final result = await ctrl.savePayment(
        vendorId: 10,
        date: DateTime(2026, 3, 4),
        amount: 5000.0,
        method: 'cash',
        note: 'Partial payment',
      );

      expect(result, true);
      expect(ctrl.isSaving.value, false);
      expect(ctrl.errorMessage.value, isEmpty);

      final postCalls = fake.calls.where(
          (c) => c.method == 'POST' && c.path == '/vendor-payment');
      expect(postCalls.length, 1);
      expect(postCalls.first.body!['vendor_id'], 10);
      expect(postCalls.first.body!['amount'], 5000.0);
      expect(postCalls.first.body!['method'], 'cash');
      expect(postCalls.first.body!['payment_date'], '2026-03-04');
      expect(postCalls.first.body!['note'], 'Partial payment');
    });

    test('savePayment returns false on failure', () async {
      fake.onPost('/vendor-payment', ApiResponse.error(
        statusCode: 400,
        message: 'Invalid payment amount.',
      ));

      createController();
      final result = await ctrl.savePayment(
        vendorId: 10,
        date: DateTime(2026, 3, 4),
        amount: -100.0,
        method: 'cash',
      );

      expect(result, false);
      expect(ctrl.errorMessage.value, 'Invalid payment amount.');
      expect(ctrl.isSaving.value, false);
    });
  });
}
