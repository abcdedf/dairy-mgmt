import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/core/location_service.dart';
import 'package:dairy_mgmt/controllers/stock_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late StockController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  StockController createController() {
    ctrl = Get.put(StockController());
    return ctrl;
  }

  group('StockController', () {
    test('fetchStock populates products and stockDays', () async {
      fake.onGet('/stock', ApiResponse.success(statusCode: 200, data: {
        'products': [
          {'id': '1', 'name': 'FF Milk', 'unit': 'KG'},
          {'id': '2', 'name': 'Skim Milk', 'unit': 'KG'},
          {'id': '3', 'name': 'Cream', 'unit': 'KG'},
        ],
        'dates': [
          {
            'date': '2026-03-03',
            'stocks': {'1': 100, '2': 200, '3': 50},
            'values': {'1': 4500.0, '2': 6000.0, '3': 2500.0},
            'total_value': 13000.0,
          },
          {
            'date': '2026-03-04',
            'stocks': {'1': 80, '2': 180, '3': 45},
            'values': {'1': 3600.0, '2': 5400.0, '3': 2250.0},
            'total_value': 11250.0,
          },
        ],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.products.length, 3);
      expect(ctrl.products.first.name, 'FF Milk');
      // stockDays are reversed — most recent first
      expect(ctrl.stockDays.length, 2);
      expect(ctrl.stockDays.first.date, '2026-03-04');
      expect(ctrl.stockDays.first.stocks[1], 80);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchStock sets errorMessage on failure', () async {
      fake.onGet('/stock', ApiResponse.error(
        statusCode: 500,
        message: 'Database error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Database error.');
      expect(ctrl.products, isEmpty);
      expect(ctrl.stockDays, isEmpty);
    });

    test('fetchStock skips when no location selected', () async {
      // Clear location so locId is null, and reset fake calls
      LocationService.instance.clear();
      fake.reset();

      fake.onGet('/stock', ApiResponse.success(statusCode: 200, data: {
        'products': [],
        'dates': [],
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Should not have made any GET /stock calls (locId is null)
      final stockCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/stock'));
      expect(stockCalls, isEmpty);
    });

    test('fetchStock re-runs when location changes', () async {
      fake.onGet('/stock', ApiResponse.success(statusCode: 200, data: {
        'products': [
          {'id': '1', 'name': 'FF Milk', 'unit': 'KG'},
        ],
        'dates': [
          {
            'date': '2026-03-04',
            'stocks': {'1': 100},
            'values': {},
            'total_value': 0,
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

      // Should have made additional GET /stock call
      expect(fake.calls.length, greaterThan(callsBefore));
      final stockCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/stock'));
      expect(stockCalls.length, greaterThanOrEqualTo(2));
    });
  });
}
