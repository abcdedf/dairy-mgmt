import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/controllers/funds_report_controller.dart';
import '../helpers/test_helpers.dart';
import '../helpers/fake_api_client.dart';

void main() {
  late FakeApiClient fake;
  late FundsReportController ctrl;

  setUp(() {
    fake = setupFakeApi();
    setupLocation(id: 1, name: 'Test', code: 'TEST');
  });

  tearDown(() => cleanupTestState());

  FundsReportController createController() {
    ctrl = Get.put(FundsReportController());
    return ctrl;
  }

  group('FundsReportController', () {
    test('fetchReport populates all financial observables', () async {
      fake.onGet('/funds-report', ApiResponse.success(statusCode: 200, data: {
        'sales_total': 125000.50,
        'stock_value': 87500.75,
        'vendor_due': 45000.00,
        'free_cash': 80000.25,
      }));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.salesTotal.value, 125000.50);
      expect(ctrl.stockValue.value, 87500.75);
      expect(ctrl.vendorDue.value, 45000.00);
      expect(ctrl.freeCash.value, 80000.25);
      expect(ctrl.isLoading.value, false);
      expect(ctrl.errorMessage.value, isEmpty);
    });

    test('fetchReport sets errorMessage on failure', () async {
      fake.onGet('/funds-report', ApiResponse.error(
        statusCode: 500,
        message: 'Failed to load funds report.',
      ));

      createController();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.errorMessage.value, 'Failed to load funds report.');
      expect(ctrl.salesTotal.value, 0.0);
      expect(ctrl.stockValue.value, 0.0);
      expect(ctrl.vendorDue.value, 0.0);
      expect(ctrl.freeCash.value, 0.0);
    });
  });
}
