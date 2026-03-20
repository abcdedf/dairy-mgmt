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

  /// Helper: register a canned ledger response, then create the controller.
  /// onInit calls fetchLedger, so the response must be registered first.
  VendorLedgerController createController({ApiResponse? ledgerResponse}) {
    if (ledgerResponse != null) {
      fake.onGet('/vendor-ledger', ledgerResponse);
    }
    ctrl = Get.put(VendorLedgerController());
    return ctrl;
  }

  group('VendorLedgerController', () {
    test('fetchLedger populates rows and vendorList', () async {
      createController(
        ledgerResponse: ApiResponse.success(statusCode: 200, data: {
          'rows': [
            {'date': '2026-03-10', 'location_name': 'Plant A', 'vendor_name': 'Vendor A', 'purchases': '50000.00', 'payments': '30000.00', 'balance': '20000.00'},
            {'date': '2026-03-10', 'location_name': 'Plant A', 'vendor_name': 'Vendor B', 'purchases': '25000.00', 'payments': '25000.00', 'balance': '0.00'},
          ],
          'vendors': [
            {'id': '10', 'name': 'Vendor A'},
            {'id': '11', 'name': 'Vendor B'},
          ],
        }),
      );

      // Wait for onInit's fetchLedger to complete
      await Future.delayed(Duration.zero);

      expect(ctrl.rows.length, 2);
      expect(ctrl.rows.first.vendorName, 'Vendor A');
      expect(ctrl.rows.first.purchases, 50000.0);
      expect(ctrl.rows.first.payments, 30000.0);
      expect(ctrl.rows.first.balance, 20000.0);
      expect(ctrl.rows[1].vendorName, 'Vendor B');
      expect(ctrl.rows[1].balance, 0.0);

      expect(ctrl.vendorList.length, 2);
      expect(ctrl.vendorList.first.id, 10);
      expect(ctrl.vendorList.first.name, 'Vendor A');

      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchLedger sets errorMessage on failure', () async {
      createController(
        ledgerResponse: ApiResponse.error(
          statusCode: 500,
          message: 'Database error.',
        ),
      );

      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Database error.');
      expect(ctrl.rows, isEmpty);
    });

    test('fetchLedger passes selectedVendorId as query param', () async {
      createController(
        ledgerResponse: ApiResponse.success(statusCode: 200, data: {
          'rows': [],
          'vendors': [],
        }),
      );

      // Wait for initial fetch
      await Future.delayed(Duration.zero);

      // Set vendor filter and re-fetch
      ctrl.selectedVendorId.value = 10;
      await ctrl.fetchLedger();

      final getCalls = fake.calls.where((c) => c.method == 'GET');
      final lastGet = getCalls.last;
      expect(lastGet.path, contains('vendor_id=10'));
    });

    test('savePayment posts correct payload and returns true on success', () async {
      createController(
        ledgerResponse: ApiResponse.success(statusCode: 200, data: {
          'rows': [],
          'vendors': [],
        }),
      );
      await Future.delayed(Duration.zero);

      fake.onPost('/vendor-payment', ApiResponse.success(statusCode: 201, data: {'id': 1}));

      final result = await ctrl.savePayment(
        partyId: 10,
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
      expect(postCalls.first.body!['party_id'], 10);
      expect(postCalls.first.body!['amount'], 5000.0);
      expect(postCalls.first.body!['method'], 'cash');
      expect(postCalls.first.body!['payment_date'], '2026-03-04');
      expect(postCalls.first.body!['note'], 'Partial payment');
    });

    test('savePayment returns false on failure', () async {
      createController(
        ledgerResponse: ApiResponse.success(statusCode: 200, data: {
          'rows': [],
          'vendors': [],
        }),
      );
      await Future.delayed(Duration.zero);

      fake.onPost('/vendor-payment', ApiResponse.error(
        statusCode: 400,
        message: 'Invalid payment amount.',
      ));

      final result = await ctrl.savePayment(
        partyId: 10,
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
