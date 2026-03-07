import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/core/location_service.dart';
import 'package:dairy_mgmt/controllers/sales_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late SalesController ctrl;

  final salesResponse = ApiResponse.success(statusCode: 200, data: {
    'products': [
      {'id': '2', 'name': 'Skim Milk', 'unit': 'KG'},
      {'id': '5', 'name': 'Ghee', 'unit': 'KG'},
    ],
    'entries': [
      {
        'id': '1',
        'product_id': '2',
        'product_name': 'Skim Milk',
        'customer_id': '100',
        'customer_name': 'Customer A',
        'quantity_kg': '50',
        'rate': '30.00',
        'total': '1500.00',
      },
    ],
  });

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
    fake.onGet('/customers', ApiResponse.success(statusCode: 200, data: [
      {'id': '100', 'name': 'Customer A'},
      {'id': '200', 'name': 'Customer B'},
    ]));
    fake.onGet('/sales', salesResponse);
  });

  tearDown(() => cleanupTestState());

  SalesController createController() {
    ctrl = Get.put(SalesController());
    return ctrl;
  }

  group('SalesController', () {
    test('onInit loads customers and sales', () async {
      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.customers.length, 2);
      expect(ctrl.customers.first.name, 'Customer A');
      expect(ctrl.selectedCustomerId.value, 100);
      expect(ctrl.entries.length, 1);
      expect(ctrl.entries.first.productName, 'Skim Milk');
      expect(ctrl.entries.first.total, 1500.0);
      expect(ctrl.products.length, 2);
    });

    test('fetchSales sets errorMessage on failure', () async {
      fake.onGet('/sales', ApiResponse.error(
        statusCode: 500,
        message: 'Server error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Server error.');
    });

    test('deleteEntry removes entry from list', () async {
      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.entries.length, 1);

      fake.onDelete('/sales/', ApiResponse.success(statusCode: 200, data: null));

      await ctrl.deleteEntry(1);

      expect(ctrl.entries, isEmpty);
      expect(ctrl.successMessage.value, 'Entry deleted.');
    });

    test('deleteEntry sets errorMessage on failure', () async {
      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      fake.onDelete('/sales/', ApiResponse.error(
        statusCode: 403,
        message: 'Not allowed.',
      ));

      await ctrl.deleteEntry(1);

      expect(ctrl.errorMessage.value, 'Not allowed.');
      expect(ctrl.entries.length, 1); // entry not removed
    });

    test('dayQty and dayTotal compute from entries', () async {
      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.dayQty, 50);
      expect(ctrl.dayTotal, 1500.0);
    });

    test('fetchSales re-runs on location change', () async {
      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      LocationService.instance.selected.value =
          const DairyLocation(id: 2, name: 'Plant B', code: 'PLB');
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final salesCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/sales'));
      expect(salesCalls.length, greaterThanOrEqualTo(2));
    });
  });
}
