// lib/controllers/cashflow_report_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';

class CashflowDay {
  final String date;
  final double beginningCash;
  final double sales;
  final double purchases;
  final double payments;
  final double endCash;

  const CashflowDay({
    required this.date,
    required this.beginningCash,
    required this.sales,
    required this.purchases,
    required this.payments,
    required this.endCash,
  });

  factory CashflowDay.fromJson(Map<String, dynamic> j) {
    double d(String k) => double.tryParse(j[k]?.toString() ?? '') ?? 0;
    return CashflowDay(
      date:           j['date']?.toString() ?? '',
      beginningCash:  d('beginning_cash'),
      sales:          d('sales'),
      purchases:      d('purchases'),
      payments:       d('payments'),
      endCash:        d('end_cash'),
    );
  }
}

class CashflowReportController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final rows         = <CashflowDay>[].obs;
  final fromDate     = ''.obs;
  final toDate       = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchReport();
  }

  Future<void> fetchReport() async {
    isLoading.value    = true;
    errorMessage.value = '';
    try {
      final res = await ApiClient.get('/cashflow-report');
      isLoading.value = false;
      if (!res.ok) {
        errorMessage.value = res.message ?? 'Error loading cash flow report.';
        return;
      }
      fromDate.value = res.data['from']?.toString() ?? '';
      toDate.value   = res.data['to']?.toString() ?? '';
      rows.value = (res.data['rows'] as List)
          .map((e) => CashflowDay.fromJson(e as Map<String, dynamic>))
          .toList()
          .reversed.toList();
    } catch (e) {
      isLoading.value    = false;
      errorMessage.value = 'Unexpected error loading cash flow report.';
    }
  }
}
