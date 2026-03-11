import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/controllers/madhusudan_pnl_controller.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late MadhusudanPnlController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  MadhusudanPnlController createController() {
    ctrl = Get.put(MadhusudanPnlController());
    return ctrl;
  }

  group('MadhusudanPnlController', () {
    test('fetchReport loads rows and totals from /madhusudan-pnl', () async {
      fake.onGet('/madhusudan-pnl', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {
            'id': '1',
            'entry_date': '2026-03-10',
            'total_ff_milk_kg': '500',
            'sale_rate': '55.00',
            'revenue': '27500.00',
            'cost': '22500.00',
            'profit': '5000.00',
          },
          {
            'id': '2',
            'entry_date': '2026-03-11',
            'total_ff_milk_kg': '300',
            'sale_rate': '60.00',
            'revenue': '18000.00',
            'cost': '13500.00',
            'profit': '4500.00',
          },
        ],
        'totals': {
          'total_ff_milk_kg': '800',
          'revenue': '45500.00',
          'cost': '36000.00',
          'profit': '9500.00',
        },
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.rows.length, 2);
      expect(ctrl.rows.first.entryDate, '2026-03-10');
      expect(ctrl.rows.first.revenue, 27500.0);
      expect(ctrl.rows.first.cost, 22500.0);
      expect(ctrl.rows.first.profit, 5000.0);
      expect(ctrl.totals.value, isNotNull);
      expect(ctrl.totals.value!.totalFfMilkKg, 800);
      expect(ctrl.totals.value!.revenue, 45500.0);
      expect(ctrl.totals.value!.cost, 36000.0);
      expect(ctrl.totals.value!.profit, 9500.0);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchReport sets errorMessage on API failure', () async {
      fake.onGet('/madhusudan-pnl', ApiResponse.error(
        statusCode: 500,
        message: 'Database error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Database error.');
      expect(ctrl.rows, isEmpty);
      expect(ctrl.isLoading.value, false);
    });

    test('empty response results in empty rows', () async {
      fake.onGet('/madhusudan-pnl', ApiResponse.success(statusCode: 200, data: {
        'rows': <dynamic>[],
        'totals': null,
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.rows, isEmpty);
      expect(ctrl.totals.value, isNull);
      expect(ctrl.isLoading.value, false);
    });

    test('MadhusudanPnlRow.fromJson parses correctly', () {
      final row = MadhusudanPnlRow.fromJson({
        'id': '42',
        'entry_date': '2026-03-05',
        'total_ff_milk_kg': '750',
        'sale_rate': '52.50',
        'revenue': '39375.00',
        'cost': '33750.00',
        'profit': '5625.00',
      });

      expect(row.id, 42);
      expect(row.entryDate, '2026-03-05');
      expect(row.totalFfMilkKg, 750);
      expect(row.saleRate, 52.5);
      expect(row.revenue, 39375.0);
      expect(row.cost, 33750.0);
      expect(row.profit, 5625.0);
    });

    test('MadhusudanPnlTotals.fromJson parses correctly', () {
      final totals = MadhusudanPnlTotals.fromJson({
        'total_ff_milk_kg': '1200',
        'revenue': '66000.00',
        'cost': '54000.00',
        'profit': '12000.00',
      });

      expect(totals.totalFfMilkKg, 1200);
      expect(totals.revenue, 66000.0);
      expect(totals.cost, 54000.0);
      expect(totals.profit, 12000.0);
    });
  });
}
