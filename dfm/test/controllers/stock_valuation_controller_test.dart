import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/core/location_service.dart';
import 'package:dairy_mgmt/controllers/stock_valuation_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late StockValuationController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  StockValuationController createController() {
    ctrl = Get.put(StockValuationController());
    return ctrl;
  }

  void stubBothEndpoints() {
    fake.onGet('/estimated-rates', ApiResponse.success(statusCode: 200, data: [
      {'product_id': 1, 'product_name': 'FF Milk', 'rate': '45.00'},
      {'product_id': 2, 'product_name': 'Skim Milk', 'rate': '30.00'},
    ]));
    fake.onGet('/stock-valuation', ApiResponse.success(statusCode: 200, data: {
      'products': [
        {'id': '1', 'name': 'FF Milk', 'unit': 'KG'},
        {'id': '2', 'name': 'Skim Milk', 'unit': 'KG'},
      ],
      'dates': [
        {
          'date': '2026-03-04',
          'stocks': {'1': 100, '2': 200},
          'values': {'1': 4500.0, '2': 6000.0},
          'total_value': 10500.0,
        },
      ],
    }));
  }

  group('StockValuationController', () {
    test('_loadInitial populates estimatedRates, products, and stockDays', () async {
      stubBothEndpoints();

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.estimatedRates.length, 2);
      expect(ctrl.estimatedRates.first.productId, 1);
      expect(ctrl.estimatedRates.first.rate, 45.0);
      expect(ctrl.products.length, 2);
      expect(ctrl.products.first.name, 'FF Milk');
      expect(ctrl.stockDays.length, 1);
      expect(ctrl.stockDays.first.date, '2026-03-04');
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('error on estimated-rates sets errorMessage', () async {
      fake.onGet('/estimated-rates', ApiResponse.error(
        statusCode: 500,
        message: 'Rate load failed.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Rate load failed.');
      expect(ctrl.estimatedRates, isEmpty);
      expect(ctrl.products, isEmpty);
      expect(ctrl.stockDays, isEmpty);
    });

    test('error on stock-valuation sets errorMessage', () async {
      fake.onGet('/estimated-rates', ApiResponse.success(statusCode: 200, data: [
        {'product_id': 1, 'product_name': 'FF Milk', 'rate': '45.00'},
      ]));
      fake.onGet('/stock-valuation', ApiResponse.error(
        statusCode: 500,
        message: 'Valuation load failed.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Valuation load failed.');
      expect(ctrl.estimatedRates.length, 1);
      expect(ctrl.products, isEmpty);
      expect(ctrl.stockDays, isEmpty);
    });

    test('re-fetches valuation on location change', () async {
      stubBothEndpoints();

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final callsBefore = fake.calls.length;

      // Change to another TEST-coded location so _effectiveLocId() returns its id
      // (non-TEST locations use reportLocId which gets reset to null on change)
      LocationService.instance.selected.value =
          const DairyLocation(id: 2, name: 'Test 2', code: 'TEST');
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Should have made additional GET /stock-valuation call
      expect(fake.calls.length, greaterThan(callsBefore));
      final valuationCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/stock-valuation'));
      expect(valuationCalls.length, greaterThanOrEqualTo(2));
    });

    test('rateCtrlMap is populated from estimated rates after init', () async {
      stubBothEndpoints();

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // rateCtrlMap should be populated with TextEditingControllers
      expect(ctrl.rateCtrlMap.length, 2);
      expect(ctrl.rateCtrlMap[1]!.text, '45.00');
      expect(ctrl.rateCtrlMap[2]!.text, '30.00');
      // saveRates requires form validation (widget tree) — tested via integration tests
    });
  });
}
