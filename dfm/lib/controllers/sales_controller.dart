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

class SalesController extends GetxController {
  final isLoading           = false.obs;
  final isSaving            = false.obs;
  final products            = <DairyProduct>[].obs;
  final allCustomers        = <Customer>[].obs;
  final filteredCustomers   = <Customer>[].obs;
  final entries             = <SaleEntry>[].obs;
  final entryDate           = DateTime.now().obs;
  final errorMessage        = ''.obs;
  final successMessage      = ''.obs;
  final formKey             = GlobalKey<FormState>();
  final _deletableIds       = <int>{};

  // Single-entry form fields
  final customerId = RxnInt();
  final productId  = RxnInt();
  final qtyCtrl    = TextEditingController();
  final rateCtrl   = TextEditingController();

  // Stock as-of selected date
  final stockSkimMilk = RxnInt();
  final stockCream    = RxnInt();
  final stockCurd     = RxnInt();
  final stockGhee     = RxnInt();

  String get _date => DateFormat('yyyy-MM-dd').format(entryDate.value);
  int    get dayQty   => entries.fold(0, (s, e) => s + e.quantityKg);
  double get dayTotal => entries.fold(0.0, (s, e) => s + e.total);
  bool canDelete(int id) => _deletableIds.contains(id);

  /// Unit label for the currently selected product.
  String get selectedUnit =>
      products.firstWhereOrNull((p) => p.id == productId.value)?.unit ?? 'KG';

  @override
  void onInit() {
    super.onInit();
    _loadInit();
    ever(LocationService.instance.selected, (_) { fetchSales(); _fetchStock(); });
  }

  @override
  void onClose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
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
      allCustomers.value = (res.data as List)
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  /// Filter customers by the currently selected product.
  void _filterCustomers() {
    final pid = productId.value;
    if (pid == null) {
      filteredCustomers.value = allCustomers;
    } else {
      filteredCustomers.value = allCustomers
          .where((c) => c.productIds.contains(pid))
          .toList();
    }
    // Reset customer selection if current customer is not in filtered list
    if (customerId.value != null &&
        !filteredCustomers.any((c) => c.id == customerId.value)) {
      customerId.value = filteredCustomers.isNotEmpty
          ? filteredCustomers.first.id : null;
    }
    // Auto-select first customer if none selected
    if (customerId.value == null && filteredCustomers.isNotEmpty) {
      customerId.value = filteredCustomers.first.id;
    }
  }

  void onProductChanged(int? id) {
    productId.value = id;
    _filterCustomers();
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
    const salesOrder = <int, int>{1: 0, 2: 1, 5: 2, 10: 3, 4: 4, 3: 5};
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

    // Set default product if not already chosen
    if (productId.value == null && products.isNotEmpty) {
      productId.value = products.first.id;
    }
    _filterCustomers();
  }

  /// Save a single sale entry.
  Future<void> save() async {
    final qty  = int.tryParse(qtyCtrl.text) ?? 0;
    final rate = double.tryParse(rateCtrl.text) ?? 0.0;

    if (productId.value == null) {
      errorMessage.value = 'Select a product.';
      return;
    }
    if (customerId.value == null) {
      errorMessage.value = 'Select a customer.';
      return;
    }
    if (qty <= 0) {
      errorMessage.value = 'Qty must be > 0.';
      return;
    }
    if (rate < 0) {
      errorMessage.value = 'Rate must be >= 0.';
      return;
    }

    final locId = LocationService.instance.locId;
    if (locId == null) return;

    isSaving.value       = true;
    errorMessage.value   = '';
    successMessage.value = '';

    final res = await ApiClient.post('/sales', {
      'location_id': locId,
      'entry_date':  _date,
      'product_id':  productId.value,
      'customer_id': customerId.value,
      'quantity_kg': qty,
      'rate':        rate,
    });

    isSaving.value = false;

    if (res.ok) {
      final newId = res.data['id'];
      if (newId != null) _deletableIds.add(int.parse(newId.toString()));
      Get.showSnackbar(GetSnackBar(
        message: 'Sale saved.',
        duration: const Duration(seconds: 2),
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1E8449),
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
      ));
      qtyCtrl.clear();
      rateCtrl.clear();
      await fetchSales(keepDeletable: true);
      _fetchStock();
    } else {
      errorMessage.value = res.message ?? 'Save failed.';
    }
  }

  Future<void> deleteEntry(int id) async {
    errorMessage.value   = '';
    successMessage.value = '';
    final res = await ApiClient.delete('/sales/$id');
    if (res.ok) {
      _deletableIds.remove(id);
      entries.removeWhere((e) => e.id == id);
      Get.showSnackbar(GetSnackBar(
        message: 'Entry deleted.',
        duration: const Duration(seconds: 2),
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1E8449),
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
      ));
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
