import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/core/location_service.dart';
import 'package:dairy_mgmt/controllers/anomaly_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late AnomalyController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  AnomalyController createController() {
    ctrl = Get.put(AnomalyController());
    return ctrl;
  }

  group('AnomalyController', () {
    test('fetchAnomalies populates rows on success', () async {
      fake.onGet('/anomalies', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {
            'id': '10',
            'entry_date': '2026-03-05',
            'input_ff_milk_used_kg': '500',
            'output_skim_milk_kg': '420',
            'output_cream_kg': '80',
            'ratio': 6.25,
            'is_anomalous': true,
            'vendor_name': 'Vendor A',
            'user_name': 'admin',
            'created_at': '2026-03-05 10:00:00',
          },
          {
            'id': '11',
            'entry_date': '2026-03-06',
            'input_ff_milk_used_kg': '600',
            'output_skim_milk_kg': '540',
            'output_cream_kg': '60',
            'ratio': 10.0,
            'is_anomalous': false,
            'vendor_name': 'Vendor B',
            'user_name': 'admin',
            'created_at': '2026-03-06 11:00:00',
          },
        ],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.rows.length, 2);
      expect(ctrl.rows.first.id, 10);
      expect(ctrl.rows.first.entryDate, '2026-03-05');
      expect(ctrl.rows.first.inputFfMilkUsedKg, 500);
      expect(ctrl.rows.first.isAnomalous, true);
      expect(ctrl.rows.last.vendorName, 'Vendor B');
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchAnomalies sets errorMessage on failure', () async {
      fake.onGet('/anomalies', ApiResponse.error(
        statusCode: 500,
        message: 'Database error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Database error.');
      expect(ctrl.rows, isEmpty);
    });

    test('fetchAnomalies skips when no location selected', () async {
      LocationService.instance.clear();
      fake.reset();

      fake.onGet('/anomalies', ApiResponse.success(statusCode: 200, data: {
        'rows': [],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final anomalyCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/anomalies'));
      expect(anomalyCalls, isEmpty);
    });

    test('fetchAnomalies re-runs when location changes', () async {
      fake.onGet('/anomalies', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {
            'id': '10',
            'entry_date': '2026-03-05',
            'input_ff_milk_used_kg': '500',
            'output_skim_milk_kg': '420',
            'output_cream_kg': '80',
            'ratio': 6.25,
            'is_anomalous': false,
            'vendor_name': 'Vendor A',
            'user_name': 'admin',
            'created_at': '2026-03-05 10:00:00',
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
      final anomalyCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/anomalies'));
      expect(anomalyCalls.length, greaterThanOrEqualTo(2));
    });
  });
}
