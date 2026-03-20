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
  late ProductionTransactionsController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  ProductionTransactionsController createController() {
    ctrl = Get.put(ProductionTransactionsController());
    return ctrl;
  }

  group('ProductionTransactionsController', () {
    test('fetchReport populates rows and days', () async {
      fake.onGet('/production-transactions', ApiResponse.success(statusCode: 200, data: {
        'days': 10,
        'rows': [
          {
            'id': '1',
            'type': 'FF Milk Purchase',
            'entry_date': '2026-03-05',
            'created_at': '2026-03-05 08:00:00',
            'user_name': 'testuser',
            'vendor_name': 'Kumar Dairy',
            'input_ff_milk_kg': '500',
            'input_snf': '8.5',
            'input_fat': '6.0',
            'input_rate': '45.00',
          },
          {
            'id': '2',
            'type': 'Dahi Production',
            'entry_date': '2026-03-06',
            'created_at': '2026-03-06 09:00:00',
            'user_name': 'testuser',
            'input_smp_bags': '10',
            'input_culture_kg': '2.50',
            'input_protein_kg': '1.50',
            'input_skim_milk_kg': '100',
            'output_container_count': '200',
          },
        ],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.rows.length, 2);
      expect(ctrl.rows.first.type, 'FF Milk Purchase');
      expect(ctrl.rows.first.date, '2026-03-05');
      expect(ctrl.rows.first.userName, 'testuser');
      expect(ctrl.rows[1].type, 'Dahi Production');
      expect(ctrl.days.value, 10);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchReport sets errorMessage on failure', () async {
      fake.onGet('/production-transactions', ApiResponse.error(
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

      fake.onGet('/production-transactions', ApiResponse.success(statusCode: 200, data: {
        'days': 7,
        'rows': [],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Controller now calls API even without a location (no location_id param)
      final calls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/production-transactions'));
      expect(calls.length, 1);
      // Should not have a location_id query param
      expect(calls.first.path, '/production-transactions');
    });

    test('fetchReport re-runs when location changes', () async {
      fake.onGet('/production-transactions', ApiResponse.success(statusCode: 200, data: {
        'days': 7,
        'rows': [
          {
            'id': '1',
            'type': 'FF Milk Purchase',
            'entry_date': '2026-03-05',
            'created_at': '2026-03-05 08:00:00',
            'user_name': 'testuser',
            'vendor_name': 'Kumar Dairy',
            'input_ff_milk_kg': '500',
            'input_snf': '8.5',
            'input_fat': '6.0',
            'input_rate': '45.00',
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
          (c) => c.method == 'GET' && c.path.startsWith('/production-transactions'));
      expect(txCalls.length, greaterThanOrEqualTo(2));
    });
  });
}
