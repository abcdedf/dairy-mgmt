import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/core/location_service.dart';
import 'package:dairy_mgmt/controllers/transactions_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late SalesTransactionsController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  SalesTransactionsController createController() {
    ctrl = Get.put(SalesTransactionsController());
    return ctrl;
  }

  group('SalesTransactionsController', () {
    test('fetchReport populates rows and days', () async {
      fake.onGet('/sales-transactions', ApiResponse.success(statusCode: 200, data: {
        'days': 14,
        'rows': [
          {
            'id': '1',
            'entry_date': '2026-03-05',
            'product_name': 'Ghee',
            'customer_name': 'Ravi Store',
            'quantity_kg': '10',
            'rate': '450.00',
            'total': '4500.00',
            'created_at': '2026-03-05 10:30:00',
            'user_name': 'testuser',
          },
          {
            'id': '2',
            'entry_date': '2026-03-06',
            'product_name': 'Butter',
            'customer_name': 'Sharma Dairy',
            'quantity_kg': '5',
            'rate': '300.00',
            'total': '1500.00',
            'created_at': '2026-03-06 11:00:00',
            'user_name': 'testuser',
          },
        ],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.rows.length, 2);
      expect(ctrl.rows.first.productName, 'Ghee');
      expect(ctrl.rows.first.customerName, 'Ravi Store');
      expect(ctrl.rows.first.rate, 450.0);
      expect(ctrl.rows.first.total, 4500.0);
      expect(ctrl.days.value, 14);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchReport sets errorMessage on failure', () async {
      fake.onGet('/sales-transactions', ApiResponse.error(
        statusCode: 500,
        message: 'Database error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Database error.');
      expect(ctrl.rows, isEmpty);
    });

    test('fetchReport calls API without location_id when no location selected', () async {
      LocationService.instance.clear();
      fake.reset();

      fake.onGet('/sales-transactions', ApiResponse.success(statusCode: 200, data: {
        'days': 7,
        'rows': [],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Controller now calls API even without a location (no location_id param)
      final calls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/sales-transactions'));
      expect(calls.length, 1);
      // Should not have a location_id query param
      expect(calls.first.path, '/sales-transactions');
    });

    test('fetchReport re-runs when location changes', () async {
      fake.onGet('/sales-transactions', ApiResponse.success(statusCode: 200, data: {
        'days': 7,
        'rows': [
          {
            'id': '1',
            'entry_date': '2026-03-05',
            'product_name': 'Ghee',
            'customer_name': 'Ravi Store',
            'quantity_kg': '10',
            'rate': '450.00',
            'total': '4500.00',
            'created_at': '2026-03-05 10:30:00',
            'user_name': 'testuser',
          },
        ],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final callsBefore = fake.calls.length;

      // Change location
      LocationService.instance.selected.value =
          const DairyLocation(id: 2, name: 'Plant B', code: 'PLB');
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(fake.calls.length, greaterThan(callsBefore));
      final txCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/sales-transactions'));
      expect(txCalls.length, greaterThanOrEqualTo(2));
    });
  });
}
