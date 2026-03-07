// lib/controllers/sales_report_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class SalesReportCell {
  final int    qtyKg;
  final double totalValue;
  const SalesReportCell({required this.qtyKg, required this.totalValue});
  factory SalesReportCell.fromJson(Map<String, dynamic> j) => SalesReportCell(
    qtyKg:      int.tryParse(j['qty_kg'].toString())      ?? 0,
    totalValue: double.tryParse(j['total_value'].toString()) ?? 0,
  );
}

class SalesReportRow {
  final String date;
  final Map<int, SalesReportCell?> products;
  final double rowTotal;
  const SalesReportRow({
    required this.date,
    required this.products,
    required this.rowTotal,
  });
}

class SalesReportController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final colOrder     = <int>[].obs;
  final prodNames    = <int, String>{}.obs;
  final rows         = <SalesReportRow>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchReport();
    ever(LocationService.instance.selected, (_) => fetchReport());
  }

  Future<void> fetchReport() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    isLoading.value    = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/sales-report?location_id=$locId');
    isLoading.value = false;
    if (!res.ok) { errorMessage.value = res.message ?? 'Error fetching report.'; return; }

    colOrder.value = (res.data['col_order'] as List)
        .map((e) => int.parse(e.toString())).toList();

    final names = <int, String>{};
    (res.data['prod_names'] as Map<String, dynamic>).forEach((k, v) {
      names[int.parse(k)] = v.toString();
    });
    prodNames.value = names;

    rows.value = (res.data['rows'] as List).map((r) {
      final rm = r as Map<String, dynamic>;
      final prods = <int, SalesReportCell?>{};
      (rm['products'] as Map<String, dynamic>).forEach((k, v) {
        final pid = int.parse(k);
        prods[pid] = v == null ? null
            : SalesReportCell.fromJson(v as Map<String, dynamic>);
      });
      return SalesReportRow(
        date:     rm['date'],
        products: prods,
        rowTotal: double.tryParse(rm['row_total'].toString()) ?? 0,
      );
    }).toList();
  }
}
