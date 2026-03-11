// lib/controllers/sales_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';
import '../models/models.dart';

class SaleEntry {
  final int    id;
  final int    productId;
  final String productName;
  final int?   customerId;
  final String customerName;
  final int    quantityKg;
  final double rate;
  final double total;

  const SaleEntry({
    required this.id,
    required this.productId,
    required this.productName,
    this.customerId,
    required this.customerName,
    required this.quantityKg,
    required this.rate,
    required this.total,
  });

  factory SaleEntry.fromJson(Map<String, dynamic> j) => SaleEntry(
    id:           int.parse(j['id'].toString()),
    productId:    int.parse(j['product_id'].toString()),
    productName:  j['product_name']  ?? '',
    customerId:   j['customer_id'] != null
                    ? int.tryParse(j['customer_id'].toString()) : null,
    customerName: j['customer_name'] ?? '',
    quantityKg:   int.parse(j['quantity_kg'].toString()),
    rate:         double.parse(j['rate'].toString()),
    total:        double.parse(j['total'].toString()),
  );
}

/// A pending sale row with its own form state.
class PendingRow {
  final RxnInt customerId;
  final RxnInt productId;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;

  PendingRow({int? initialCustomerId, int? initialProductId})
      : customerId = RxnInt(initialCustomerId),
        productId  = RxnInt(initialProductId),
        qtyCtrl    = TextEditingController(),
        rateCtrl   = TextEditingController();

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}

class SalesController extends GetxController {
  final isLoading           = false.obs;
  final isSaving            = false.obs;
  final products            = <DairyProduct>[].obs;
  final customers           = <Customer>[].obs;
  final entries             = <SaleEntry>[].obs;
  final pendingRows         = <PendingRow>[].obs;
  final entryDate           = DateTime.now().obs;
  final errorMessage        = ''.obs;
  final successMessage      = ''.obs;
  final formKey             = GlobalKey<FormState>();
  final _deletableIds       = <int>{};

  // Stock as-of selected date
  final stockSkimMilk = RxnInt();
  final stockCream    = RxnInt();
  final stockCurd     = RxnInt();
  final stockGhee     = RxnInt();

  String get _date => DateFormat('yyyy-MM-dd').format(entryDate.value);
  int    get dayQty   => entries.fold(0, (s, e) => s + e.quantityKg);
  double get dayTotal => entries.fold(0.0, (s, e) => s + e.total);
  bool canDelete(int id) => _deletableIds.contains(id);

  @override
  void onInit() {
    super.onInit();
    _loadInit();
    ever(LocationService.instance.selected, (_) { fetchSales(); _fetchStock(); });
  }

  @override
  void onClose() {
    for (final row in pendingRows) { row.dispose(); }
    super.onClose();
  }

  Future<void> _loadInit() async {
    await _loadCustomers();
    await fetchSales();
    _fetchStock();
  }

  Future<void> _loadCustomers() async {
    final res = await ApiClient.get('/customers');
    if (res.ok) {
      customers.value = (res.data as List)
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> fetchSales({bool keepDeletable = false}) async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    if (!keepDeletable) _deletableIds.clear();
    isLoading.value    = true;
    errorMessage.value = '';
    final res = await ApiClient.get(
        '/sales?location_id=$locId&entry_date=$_date');
    isLoading.value = false;
    if (!res.ok) {
      errorMessage.value = res.message ?? 'Error fetching sales.';
      return;
    }
    const salesOrder = <int, int>{2: 0, 5: 1, 10: 2, 4: 3, 3: 4};
    final fallback = salesOrder.length;
    products.value = (res.data['products'] as List)
        .map((e) => DairyProduct.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) =>
          (salesOrder[a.id] ?? fallback).compareTo(
              salesOrder[b.id] ?? fallback));
    entries.value = (res.data['entries'] as List)
        .map((e) => SaleEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    // Start with one blank row if none pending
    if (pendingRows.isEmpty) addRow();
  }

  void addRow() {
    final defaultCust = customers.isNotEmpty ? customers.first.id : null;
    final defaultProd = products.isNotEmpty ? products.first.id : null;
    pendingRows.add(PendingRow(
      initialCustomerId: defaultCust,
      initialProductId: defaultProd,
    ));
  }

  void removeRow(int index) {
    if (index >= 0 && index < pendingRows.length) {
      pendingRows[index].dispose();
      pendingRows.removeAt(index);
    }
  }

  /// Save all non-empty pending rows to the server.
  Future<void> saveAll() async {
    // Collect rows that have qty filled
    final toSave = <PendingRow>[];
    for (final row in pendingRows) {
      final qty = int.tryParse(row.qtyCtrl.text) ?? 0;
      if (qty > 0 && row.customerId.value != null && row.productId.value != null) {
        toSave.add(row);
      }
    }
    if (toSave.isEmpty) {
      errorMessage.value = 'Fill in at least one row with qty > 0.';
      return;
    }

    // Validate rates
    for (final row in toSave) {
      final rate = double.tryParse(row.rateCtrl.text) ?? 0.0;
      if (rate < 0) {
        errorMessage.value = 'Rate must be >= 0.';
        return;
      }
    }

    final locId = LocationService.instance.locId;
    if (locId == null) return;

    isSaving.value       = true;
    errorMessage.value   = '';
    successMessage.value = '';

    int saved = 0;
    String? firstError;
    for (final row in toSave) {
      final res = await ApiClient.post('/sales', {
        'location_id': locId,
        'entry_date':  _date,
        'product_id':  row.productId.value,
        'customer_id': row.customerId.value,
        'quantity_kg': int.tryParse(row.qtyCtrl.text) ?? 0,
        'rate':        double.tryParse(row.rateCtrl.text) ?? 0.0,
      });
      if (res.ok) {
        saved++;
        final newId = res.data['id'];
        if (newId != null) _deletableIds.add(int.parse(newId.toString()));
      } else {
        firstError ??= res.message ?? 'Failed.';
      }
    }

    isSaving.value = false;

    // Clear pending rows and add one fresh blank
    for (final row in pendingRows) { row.dispose(); }
    pendingRows.clear();

    if (firstError != null) {
      errorMessage.value = '$saved saved, error: $firstError';
    } else {
      successMessage.value = '$saved sale${saved > 1 ? 's' : ''} saved.';
    }
    await fetchSales(keepDeletable: true);
    _fetchStock();
  }

  Future<void> deleteEntry(int id) async {
    errorMessage.value   = '';
    successMessage.value = '';
    final res = await ApiClient.delete('/sales/$id');
    if (res.ok) {
      _deletableIds.remove(id);
      entries.removeWhere((e) => e.id == id);
      successMessage.value = 'Entry deleted.';
    } else {
      errorMessage.value = res.message ?? 'Delete failed.';
    }
  }

  void pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: entryDate.value,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      entryDate.value = picked;
      await fetchSales();
      _fetchStock();
    }
  }

  Future<void> _fetchStock() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    final date = _date;
    final from = DateFormat('yyyy-MM-dd')
        .format(DateTime.parse(date).subtract(const Duration(days: 29)));
    final res = await ApiClient.get(
        '/stock?location_id=$locId&from=$from&to=$date');
    if (!res.ok) return;
    final dates = res.data['dates'] as List?;
    if (dates == null || dates.isEmpty) {
      stockSkimMilk.value = null;
      stockCream.value    = null;
      stockCurd.value     = null;
      stockGhee.value     = null;
      return;
    }
    final last   = dates.last as Map<String, dynamic>;
    final stocks = last['stocks'] as Map<String, dynamic>? ?? {};
    int? val(int id) {
      final v = stocks[id.toString()];
      return v == null ? null : num.tryParse(v.toString())?.toInt();
    }
    stockSkimMilk.value = val(ProductIds.skimMilk);
    stockCream.value    = val(ProductIds.cream);
    stockCurd.value     = val(ProductIds.curd);
    stockGhee.value     = val(ProductIds.ghee);
  }
}
