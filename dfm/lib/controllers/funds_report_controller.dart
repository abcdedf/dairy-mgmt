// lib/controllers/funds_report_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';

class FundsReportController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final salesTotal   = 0.0.obs;
  final stockValue   = 0.0.obs;
  final vendorDue    = 0.0.obs;
  final freeCash     = 0.0.obs;

  @override
  void onInit() {
    super.onInit();
    fetchReport();
  }

  Future<void> fetchReport() async {
    isLoading.value    = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/funds-report');
    isLoading.value = false;
    if (res.ok) {
      salesTotal.value = (res.data['sales_total'] as num).toDouble();
      stockValue.value = (res.data['stock_value'] as num).toDouble();
      vendorDue.value  = (res.data['vendor_due']  as num).toDouble();
      freeCash.value   = (res.data['free_cash']   as num).toDouble();
    } else {
      errorMessage.value = res.message ?? 'Failed to load funds report.';
    }
  }
}
