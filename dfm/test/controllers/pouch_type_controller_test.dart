import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/controllers/pouch_type_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late PouchTypeController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  PouchTypeController createController() {
    ctrl = Get.put(PouchTypeController());
    return ctrl;
  }

  group('PouchTypeController', () {
    test('fetchPouchTypes loads types with milkPerPouch and pouchesPerCrate', () async {
      fake.onGet('/pouch-products', ApiResponse.success(statusCode: 200, data: [
        {
          'id': '1',
          'name': '500ml',
          'milk_per_pouch': '0.50',
          'pouches_per_crate': '20',
          'crate_rate': '0.00',
          'is_active': '1',
        },
        {
          'id': '2',
          'name': '1L',
          'milk_per_pouch': '1.00',
          'pouches_per_crate': '12',
          'crate_rate': '0.00',
          'is_active': '1',
        },
      ]));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.pouchTypes.length, 2);
      expect(ctrl.pouchTypes.first.name, '500ml');
      expect(ctrl.pouchTypes.first.milkPerPouch, 0.5);
      expect(ctrl.pouchTypes.first.pouchesPerCrate, 20);
      expect(ctrl.pouchTypes[1].name, '1L');
      expect(ctrl.pouchTypes[1].milkPerPouch, 1.0);
      expect(ctrl.pouchTypes[1].pouchesPerCrate, 12);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('savePouchType posts with milk_per_pouch, pouches_per_crate, and crate_rate keys', () async {
      // Stub initial fetch and re-fetch after save
      fake.onGet('/pouch-products', ApiResponse.success(statusCode: 200, data: []));
      // Stub the save POST
      fake.onPost('/pouch-products', ApiResponse.success(statusCode: 201, data: {'id': 3}));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final result = await ctrl.savePouchType('250ml', 0.25, 30);

      expect(result, true);
      expect(ctrl.successMessage.value, 'Pouch type added.');

      // Verify the POST call was made with correct keys
      final postCalls = fake.calls.where((c) => c.method == 'POST').toList();
      expect(postCalls.length, 1);
      expect(postCalls.first.body!['name'], '250ml');
      expect(postCalls.first.body!['milk_per_pouch'], 0.25);
      expect(postCalls.first.body!['pouches_per_crate'], 30);
      expect(postCalls.first.body!['crate_rate'], 0);
    });

    test('updatePouchType posts with correct keys', () async {
      // Stub initial fetch and re-fetch after update
      fake.onGet('/pouch-products', ApiResponse.success(statusCode: 200, data: [
        {'id': '1', 'name': '500ml', 'milk_per_pouch': '0.50', 'pouches_per_crate': '20', 'crate_rate': '0.00', 'is_active': '1'},
      ]));
      // Stub the update POST
      fake.onPost('/pouch-products/1', ApiResponse.success(statusCode: 200, data: {'updated': true}));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final result = await ctrl.updatePouchType(1, name: '500ml Premium', milkPerPouch: 0.55, pouchesPerCrate: 18);

      expect(result, true);
      expect(ctrl.successMessage.value, 'Pouch type updated.');

      final postCalls = fake.calls.where((c) => c.method == 'POST' && c.path.contains('/pouch-products/1')).toList();
      expect(postCalls.length, 1);
      expect(postCalls.first.body!['name'], '500ml Premium');
      expect(postCalls.first.body!['milk_per_pouch'], 0.55);
      expect(postCalls.first.body!['pouches_per_crate'], 18);
    });

    test('PouchType.fromJson parses milk_per_pouch, pouches_per_crate, and crate_rate', () {
      final pt = PouchType.fromJson({
        'id': '5',
        'name': '200ml',
        'milk_per_pouch': '0.20',
        'pouches_per_crate': '30',
        'crate_rate': '15.50',
        'is_active': '1',
      });

      expect(pt.id, 5);
      expect(pt.name, '200ml');
      expect(pt.milkPerPouch, 0.2);
      expect(pt.pouchesPerCrate, 30);
      expect(pt.crateRate, 15.5);
      expect(pt.isActive, true);
    });
  });
}
