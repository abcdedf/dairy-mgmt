// lib/controllers/cash_stock_report_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class CashStockRow {
  final String date;
  final double beginningCash;
  final double sales;
  final double purchases;
  final double payments;
  final double endCash;
  final double skimMilk;
  final double curd;
  final double cream;
  final double ghee;
  final double butter;
  final double ffMilk;
  final double smpCulPro;
  final double totalStock;
  final double cashPlusStock;

  const CashStockRow({
    required this.date,
    required this.beginningCash,
    required this.sales,
    required this.purchases,
    required this.payments,
    required this.endCash,
    required this.skimMilk,
    required this.curd,
    required this.cream,
    required this.ghee,
    required this.butter,
    required this.ffMilk,
    required this.smpCulPro,
    required this.totalStock,
    required this.cashPlusStock,
  });

  factory CashStockRow.fromJson(Map<String, dynamic> j) {
    double d(String k) => double.tryParse(j[k]?.toString() ?? '') ?? 0;
    return CashStockRow(
      date:           j['date']?.toString() ?? '',
      beginningCash:  d('beginning_cash'),
      sales:          d('sales'),
      purchases:      d('purchases'),
      payments:       d('payments'),
      endCash:        d('end_cash'),
      skimMilk:       d('skim_milk'),
      curd:           d('curd'),
      cream:          d('cream'),
      ghee:           d('ghee'),
      butter:         d('butter'),
      ffMilk:         d('ff_milk'),
      smpCulPro:      d('smp_cul_pro'),
      totalStock:     d('total_stock'),
      cashPlusStock:  d('cash_plus_stock'),
    );
  }
}

class CashStockReportController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final rows         = <CashStockRow>[].obs;
  final reportLocId  = RxnInt();

  int? _effectiveLocId() {
    final appBarLoc = LocationService.instance.selected.value;
    if (appBarLoc != null && appBarLoc.code.toLowerCase() == 'test') {
      return appBarLoc.id;
    }
    return reportLocId.value;
  }

  @override
  void onInit() {
    super.onInit();
    fetchReport();
    ever(LocationService.instance.selected, (_) {
      reportLocId.value = null;
      fetchReport();
    });
  }

  Future<void> fetchReport() async {
    isLoading.value    = true;
    errorMessage.value = '';
    try {
      final locId = _effectiveLocId();
      final locParam = locId != null ? '?location_id=$locId' : '';
      final res = await ApiClient.get('/cash-stock-report$locParam');
      isLoading.value = false;
      if (!res.ok) {
        errorMessage.value = res.message ?? 'Error loading report.';
        return;
      }
      rows.value = (res.data['rows'] as List)
          .map((e) => CashStockRow.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      isLoading.value    = false;
      errorMessage.value = 'Unexpected error loading report.';
    }
  }
}
