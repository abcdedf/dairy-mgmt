import 'package:flutter/material.dart';
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
    'rows': [
      {
        'id': '1',
        'transaction_date': '2026-03-14',
        'party_id': '100',
        'party_name': 'Customer A',
        'lines': [
          {
            'product_id': '2',
            'product_name': 'Skim Milk',
            'qty': '50',
            'rate': '30.00',
          },
        ],
      },
    ],
  });

  setUp(() {
    Get.testMode = true;
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
    fake.onGet('/products', ApiResponse.success(statusCode: 200, data: [
      {'id': '2', 'name': 'Skim Milk', 'unit': 'KG'},
      {'id': '5', 'name': 'Ghee', 'unit': 'KG'},
    ]));
    fake.onGet('/v4/parties', ApiResponse.success(statusCode: 200, data: [
      {'id': '100', 'name': 'Customer A', 'party_type': 'customer', 'is_active': '1'},
      {'id': '200', 'name': 'Customer B', 'party_type': 'customer', 'is_active': '1'},
    ]));
    fake.onGet('/v4/transactions', salesResponse);
    fake.onGet('/v4/stock', ApiResponse.success(statusCode: 200, data: {'dates': []}));
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

      expect(ctrl.allCustomers.length, 2);
      expect(ctrl.allCustomers.first.name, 'Customer A');
      expect(ctrl.customerId.value, 100);
      expect(ctrl.entries.length, 1);
      expect(ctrl.entries.first.productName, 'Skim Milk');
      expect(ctrl.entries.first.total, 1500.0);
      expect(ctrl.products.length, 2);
    });

    test('fetchSales sets errorMessage on failure', () async {
      fake.onGet('/v4/transactions', ApiResponse.error(
        statusCode: 500,
        message: 'Server error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Server error.');
    });

    testWidgets('deleteEntry removes entry from list', (tester) async {
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
      createController();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(ctrl.entries.length, 1);

      fake.onDelete('/v4/transaction/', ApiResponse.success(statusCode: 200, data: null));

      await ctrl.deleteEntry(1);

      expect(ctrl.entries, isEmpty);

      // Advance past the 2-second snackbar duration timer, then settle animations
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    test('deleteEntry sets errorMessage on failure', () async {
      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      fake.onDelete('/v4/transaction/', ApiResponse.error(
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
          (c) => c.method == 'GET' && c.path.startsWith('/v4/transactions'));
      expect(salesCalls.length, greaterThanOrEqualTo(2));
    });
  });
}
