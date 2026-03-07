import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/core/location_service.dart';
import 'package:dairy_mgmt/controllers/vendor_purchase_report_controller.dart';
import 'package:dairy_mgmt/models/models.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late VendorPurchaseReportController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  VendorPurchaseReportController createController() {
    ctrl = Get.put(VendorPurchaseReportController());
    return ctrl;
  }

  group('VendorPurchaseReportController', () {
    test('fetchReport populates rows, totalQty, and totalAmount', () async {
      fake.onGet('/vendor-purchase-report', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {
            'entry_date': '2026-03-05',
            'vendor': 'Vendor A',
            'product': 'FF Milk',
            'quantity_kg': '500',
            'fat': '4.5',
            'rate': '45.00',
            'amount': '22500.00',
          },
          {
            'entry_date': '2026-03-06',
            'vendor': 'Vendor B',
            'product': 'FF Milk',
            'quantity_kg': '300',
            'fat': '4.2',
            'rate': '44.00',
            'amount': '13200.00',
          },
        ],
        'total_qty': '800',
        'total_amount': '35700.00',
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.rows.length, 2);
      expect(ctrl.rows.first.date, '2026-03-05');
      expect(ctrl.rows.first.vendor, 'Vendor A');
      expect(ctrl.rows.first.quantityKg, 500);
      expect(ctrl.rows.first.fat, 4.5);
      expect(ctrl.rows.first.rate, 45.0);
      expect(ctrl.rows.first.amount, 22500.0);
      expect(ctrl.rows.last.vendor, 'Vendor B');
      expect(ctrl.totalQty.value, 800);
      expect(ctrl.totalAmount.value, 35700.0);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchReport sets errorMessage on failure', () async {
      fake.onGet('/vendor-purchase-report', ApiResponse.error(
        statusCode: 500,
        message: 'Database error.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Database error.');
      expect(ctrl.rows, isEmpty);
    });

    test('fetchReport skips when no location selected', () async {
      LocationService.instance.clear();
      fake.reset();

      fake.onGet('/vendor-purchase-report', ApiResponse.success(statusCode: 200, data: {
        'rows': [],
        'total_qty': '0',
        'total_amount': '0',
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final reportCalls = fake.calls.where(
          (c) => c.method == 'GET' && c.path.startsWith('/vendor-purchase-report'));
      expect(reportCalls, isEmpty);
    });

    test('fetchReport re-runs when location changes', () async {
      fake.onGet('/vendor-purchase-report', ApiResponse.success(statusCode: 200, data: {
        'rows': [
          {
            'entry_date': '2026-03-05',
            'vendor': 'Vendor A',
            'product': 'FF Milk',
            'quantity_kg': '500',
            'fat': '4.5',
            'rate': '45.00',
            'amount': '22500.00',
          },
        ],
        'total_qty': '500',
        'total_amount': '22500.00',
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
          (c) => c.method == 'GET' && c.path.startsWith('/vendor-purchase-report'));
      expect(reportCalls.length, greaterThanOrEqualTo(2));
    });
  });
}
