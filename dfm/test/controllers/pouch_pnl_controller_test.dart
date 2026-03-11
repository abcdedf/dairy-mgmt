import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/controllers/pouch_pnl_controller.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late PouchPnlController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  PouchPnlController createController() {
    ctrl = Get.put(PouchPnlController());
    return ctrl;
  }

  group('PouchPnlController', () {
    test('fetchReport loads rows and totals from /pouch-pnl', () async {
      fake.onGet('/pouch-pnl', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {
            'id': '1',
            'entry_date': '2026-03-10',
            'total_crates': '50',
            'revenue': '25000.00',
            'cost': '18000.00',
            'profit': '7000.00',
          },
          {
            'id': '2',
            'entry_date': '2026-03-11',
            'total_crates': '30',
            'revenue': '15000.00',
            'cost': '10800.00',
            'profit': '4200.00',
          },
        ],
        'totals': {
          'total_crates': '80',
          'revenue': '40000.00',
          'cost': '28800.00',
          'profit': '11200.00',
        },
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.rows.length, 2);
      expect(ctrl.rows.first.entryDate, '2026-03-10');
      expect(ctrl.rows.first.totalCrates, 50);
      expect(ctrl.rows.first.revenue, 25000.0);
      expect(ctrl.rows.first.cost, 18000.0);
      expect(ctrl.rows.first.profit, 7000.0);
      expect(ctrl.totals.value, isNotNull);
      expect(ctrl.totals.value!.totalCrates, 80);
      expect(ctrl.totals.value!.revenue, 40000.0);
      expect(ctrl.totals.value!.cost, 28800.0);
      expect(ctrl.totals.value!.profit, 11200.0);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchReport sets errorMessage on API failure', () async {
      fake.onGet('/pouch-pnl', ApiResponse.error(
        statusCode: 500,
        message: 'Server error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Server error.');
      expect(ctrl.rows, isEmpty);
      expect(ctrl.isLoading.value, false);
    });

    test('PouchPnlRow.fromJson parses correctly', () {
      final row = PouchPnlRow.fromJson({
        'id': '5',
        'entry_date': '2026-03-08',
        'total_crates': '25',
        'revenue': '12500.00',
        'cost': '9000.00',
        'profit': '3500.00',
      });

      expect(row.id, 5);
      expect(row.entryDate, '2026-03-08');
      expect(row.totalCrates, 25);
      expect(row.revenue, 12500.0);
      expect(row.cost, 9000.0);
      expect(row.profit, 3500.0);
    });

    test('PouchPnlTotals.fromJson parses correctly', () {
      final totals = PouchPnlTotals.fromJson({
        'total_crates': '120',
        'revenue': '60000.00',
        'cost': '43200.00',
        'profit': '16800.00',
      });

      expect(totals.totalCrates, 120);
      expect(totals.revenue, 60000.0);
      expect(totals.cost, 43200.0);
      expect(totals.profit, 16800.0);
    });
  });
}
