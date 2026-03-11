import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/controllers/pouch_stock_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late PouchStockController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  PouchStockController createController() {
    ctrl = Get.put(PouchStockController());
    return ctrl;
  }

  group('PouchStockController', () {
    test('fetchPouchStock loads rows with crateCount', () async {
      fake.onGet('/pouch-stock', ApiResponse.success(statusCode: 200, data: [
        {
          'pouch_type_id': '1',
          'name': '500ml',
          'milk_per_pouch': '0.50',
          'pouches_per_crate': '20',
          'crate_count': '15',
        },
        {
          'pouch_type_id': '2',
          'name': '1L',
          'milk_per_pouch': '1.00',
          'pouches_per_crate': '12',
          'crate_count': '8',
        },
      ]));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.pouchStock.length, 2);
      expect(ctrl.pouchStock.first.name, '500ml');
      expect(ctrl.pouchStock.first.crateCount, 15);
      expect(ctrl.pouchStock.first.milkPerPouch, 0.5);
      expect(ctrl.pouchStock.first.pouchesPerCrate, 20);
      expect(ctrl.pouchStock[1].name, '1L');
      expect(ctrl.pouchStock[1].crateCount, 8);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchPouchStock sets errorMessage on failure', () async {
      fake.onGet('/pouch-stock', ApiResponse.error(
        statusCode: 500,
        message: 'Failed to load pouch stock.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Failed to load pouch stock.');
      expect(ctrl.pouchStock, isEmpty);
      expect(ctrl.isLoading.value, false);
    });

    test('PouchStockRow.fromJson parses milk_per_pouch, pouches_per_crate, crate_count', () {
      final row = PouchStockRow.fromJson({
        'pouch_type_id': '3',
        'name': '250ml',
        'milk_per_pouch': '0.25',
        'pouches_per_crate': '30',
        'crate_count': '22',
      });

      expect(row.pouchTypeId, 3);
      expect(row.name, '250ml');
      expect(row.milkPerPouch, 0.25);
      expect(row.pouchesPerCrate, 30);
      expect(row.crateCount, 22);
    });
  });
}
