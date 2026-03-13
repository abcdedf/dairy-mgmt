// lib/controllers/sales_report_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

// ── Pivot model (existing Daily Sales Summary) ──────────────

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
  final colOrder          = <int>[].obs;
  final prodNames         = <int, String>{}.obs;
  final rows              = <SalesReportRow>[].obs;
  final selectedProductId = 0.obs;  // 0 = All

  /// Columns to display — filtered by selectedProductId
  List<int> get visibleCols =>
      selectedProductId.value == 0
          ? colOrder
          : colOrder.where((pid) => pid == selectedProductId.value).toList();

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

// ── Flat sales ledger model ─────────────────────────────────

class SalesLedgerRow {
  final int    id;
  final String date;
  final String customerName;
  final String productName;
  final String unit;
  final double quantity;
  final double rate;
  final double total;

  const SalesLedgerRow({
    required this.id,
    required this.date,
    required this.customerName,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.rate,
    required this.total,
  });

  factory SalesLedgerRow.fromJson(Map<String, dynamic> j) {
    double d(String k) => double.tryParse(j[k]?.toString() ?? '') ?? 0;
    return SalesLedgerRow(
      id:           int.tryParse(j['id']?.toString() ?? '') ?? 0,
      date:         j['entry_date']?.toString() ?? '',
      customerName: j['customer_name']?.toString() ?? '',
      productName:  j['product_name']?.toString() ?? '',
      unit:         j['unit']?.toString() ?? '',
      quantity:     d('quantity_kg'),
      rate:         d('rate'),
      total:        d('total'),
    );
  }
}

class SalesLedgerCustomer {
  final int id;
  final String name;
  const SalesLedgerCustomer({required this.id, required this.name});
  factory SalesLedgerCustomer.fromJson(Map<String, dynamic> j) => SalesLedgerCustomer(
    id:   int.parse(j['id'].toString()),
    name: j['name']?.toString() ?? '',
  );
}

class SalesLedgerController extends GetxController {
  final isLoading          = false.obs;
  final errorMessage       = ''.obs;
  final rows               = <SalesLedgerRow>[].obs;
  final customers          = <SalesLedgerCustomer>[].obs;
  final selectedCustomerId = 0.obs;  // 0 = All

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
    try {
      final custParam = selectedCustomerId.value > 0
          ? '&customer_id=${selectedCustomerId.value}' : '';
      final res = await ApiClient.get(
          '/sales-ledger?location_id=$locId$custParam');
      isLoading.value = false;
      if (!res.ok) {
        errorMessage.value = res.message ?? 'Error loading sales ledger.';
        return;
      }
      rows.value = (res.data['rows'] as List)
          .map((e) => SalesLedgerRow.fromJson(e as Map<String, dynamic>))
          .toList();
      if (res.data['customers'] != null) {
        customers.value = (res.data['customers'] as List)
            .map((e) => SalesLedgerCustomer.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      isLoading.value    = false;
      errorMessage.value = 'Unexpected error loading sales ledger.';
    }
  }
}
