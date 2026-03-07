import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/core/location_service.dart';
import 'package:dairy_mgmt/controllers/sales_report_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late SalesReportController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  SalesReportController createController() {
    ctrl = Get.put(SalesReportController());
    return ctrl;
  }

  group('SalesReportController', () {
    test('fetchReport populates colOrder, prodNames, and rows', () async {
      fake.onGet('/sales-report', ApiResponse.success(statusCode: 200, data: {
        'col_order': [1, 2, 5],
        'prod_names': {'1': 'FF Milk', '2': 'Skim Milk', '5': 'Ghee'},
        'rows': [
          {
            'date': '2026-03-05',
            'products': {
              '1': {'qty_kg': '100', 'total_value': '4500.00'},
              '2': {'qty_kg': '50', 'total_value': '2000.00'},
              '5': null,
            },
            'row_total': '6500.00',
          },
          {
            'date': '2026-03-06',
            'products': {
              '1': {'qty_kg': '80', 'total_value': '3600.00'},
              '2': null,
              '5': {'qty_kg': '10', 'total_value': '5000.00'},
            },
            'row_total': '8600.00',
          },
        ],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.colOrder.length, 3);
      expect(ctrl.colOrder, [1, 2, 5]);
      expect(ctrl.prodNames.length, 3);
      expect(ctrl.prodNames[1], 'FF Milk');
      expect(ctrl.prodNames[5], 'Ghee');
      expect(ctrl.rows.length, 2);
      expect(ctrl.rows.first.date, '2026-03-05');
      expect(ctrl.rows.first.products[1]!.qtyKg, 100);
      expect(ctrl.rows.first.products[5], isNull);
      expect(ctrl.rows.last.rowTotal, 8600.0);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchReport sets errorMessage on failure', () async {
      fake.onGet('/sales-report', ApiResponse.error(
        statusCode: 500,
        message: 'Database error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Database error.');
      expect(ctrl.colOrder, isEmpty);
      expect(ctrl.prodNames, isEmpty);
      expect(ctrl.rows, isEmpty);
    });

    test('fetchReport skips when no location selected', () async {
      LocationService.instance.clear();
      fake.reset();

      fake.onGet('/sales-report', ApiResponse.success(statusCode: 200, data: {
        'col_order': [],
        'prod_names': {},
        'rows': [],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final reportCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/sales-report'));
      expect(reportCalls, isEmpty);
    });

    test('fetchReport re-runs when location changes', () async {
      fake.onGet('/sales-report', ApiResponse.success(statusCode: 200, data: {
        'col_order': [1],
        'prod_names': {'1': 'FF Milk'},
        'rows': [
          {
            'date': '2026-03-05',
            'products': {
              '1': {'qty_kg': '100', 'total_value': '4500.00'},
            },
            'row_total': '4500.00',
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
      final reportCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/sales-report'));
      expect(reportCalls.length, greaterThanOrEqualTo(2));
    });
  });
}
