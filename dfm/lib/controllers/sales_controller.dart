// lib/controllers/sales_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';
import '../models/models.dart';

class SaleEntry {
  final int    id;
  final String date;
  final int    productId;
  final String productName;
  final int?   customerId;
  final String customerName;
  final int    quantityKg;
  final double rate;
  final double total;

  const SaleEntry({
    required this.id,
    required this.date,
    required this.productId,
    required this.productName,
    this.customerId,
    required this.customerName,
    required this.quantityKg,
    required this.rate,
    required this.total,
  });

  /// Parse from V4 transaction row (with lines array).
  factory SaleEntry.fromV4(Map<String, dynamic> j) {
    final lines = j['lines'] as List? ?? [];
    final line = lines.isNotEmpty ? lines[0] as Map<String, dynamic> : <String, dynamic>{};
    final qty = (double.tryParse(line['qty']?.toString() ?? '0') ?? 0).abs();
    final rate = double.tryParse(line['rate']?.toString() ?? '0') ?? 0;
    return SaleEntry(
      id:           int.parse(j['id'].toString()),
      date:         j['transaction_date']?.toString() ?? j['entry_date']?.toString() ?? '',
      productId:    int.tryParse(line['product_id']?.toString() ?? '0') ?? 0,
      productName:  line['product_name']?.toString() ?? '',
      customerId:   j['party_id'] != null ? int.tryParse(j['party_id'].toString()) : null,
      customerName: j['party_name']?.toString() ?? '',
      quantityKg:   qty.toInt(),
      rate:         rate,
      total:        qty * rate,
    );
  }
}

class SalesController extends GetxController {
  final isLoading           = false.obs;
  final isSaving            = false.obs;
  final products            = <DairyProduct>[].obs;
  final allCustomers        = <Party>[].obs;  // V4: unified parties
  final filteredCustomers   = <Party>[].obs;
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
  bool canDelete(int id) => _deletableIds.contains(id);

  /// Entries filtered by selected product — last 7 days.
  List<SaleEntry> get filteredEntries {
    final pid = productId.value;
    if (pid == null) return entries;
    return entries.where((e) => e.productId == pid).toList();
  }

  int    get dayQty   => filteredEntries.fold(0, (s, e) => s + e.quantityKg);
  double get dayTotal => filteredEntries.fold(0.0, (s, e) => s + e.total);

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
    await _loadProducts();
    await _loadCustomers();
    await fetchSales();
    _fetchStock();
  }

  Future<void> _loadProducts() async {
    final res = await ApiClient.get('/products');
    if (res.ok) {
      const salesOrder = <int, int>{1: 0, 2: 1, 5: 2, 10: 3, 4: 4, 3: 5};
      final fallback = salesOrder.length;
      products.value = (res.data as List)
          .map((e) => DairyProduct.fromJson(e as Map<String, dynamic>))
          .where((p) => p.id != 12) // Pouch Milk sold via challans, not sales
          .toList()
        ..sort((a, b) =>
            (salesOrder[a.id] ?? fallback).compareTo(salesOrder[b.id] ?? fallback));
      if (productId.value == null && products.isNotEmpty) {
        productId.value = products.first.id;
      }
    }
  }

  // V4: Load customers from unified parties table
  Future<void> _loadCustomers() async {
    final res = await ApiClient.get('/v4/parties?party_type=customer');
    if (res.ok) {
      allCustomers.value = (res.data as List)
          .map((e) => Party.fromJson(e as Map<String, dynamic>))
          .toList();
      _filterCustomers();
    }
  }

  /// Filter customers by selected product — only show customers assigned to this product.
  void _filterCustomers() {
    final pid = productId.value;
    if (pid != null) {
      filteredCustomers.value = allCustomers
          .where((c) => c.productIds.isEmpty || c.productIds.contains(pid))
          .toList();
    } else {
      filteredCustomers.value = allCustomers.toList();
    }
    debugPrint('[Sales] filterCustomers: product=$pid → ${filteredCustomers.length} customers');
    if (customerId.value != null &&
        !filteredCustomers.any((c) => c.id == customerId.value)) {
      customerId.value = filteredCustomers.isNotEmpty
          ? filteredCustomers.first.id : null;
    }
    if (customerId.value == null && filteredCustomers.isNotEmpty) {
      customerId.value = filteredCustomers.first.id;
    }
  }

  void onProductChanged(int? id) {
    productId.value = id;
    _loadCustomers(); // Reload from server to pick up newly added customers
  }

  /// Refresh customers from server — call when page regains focus.
  Future<void> refreshCustomers() async {
    await _loadCustomers();
  }

  // V4: Fetch sales from V4 transactions — last 7 days up to selected date
  Future<void> fetchSales({bool keepDeletable = false}) async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    if (!keepDeletable) _deletableIds.clear();
    isLoading.value    = true;
    errorMessage.value = '';
    final from = DateFormat('yyyy-MM-dd')
        .format(entryDate.value.subtract(const Duration(days: 6)));
    final res = await ApiClient.get(
        '/v4/transactions?location_id=$locId&from=$from&to=$_date&transaction_type=sale');
    isLoading.value = false;
    if (!res.ok) {
      errorMessage.value = res.message ?? 'Error fetching sales.';
      return;
    }
    final rows = res.data['rows'] as List? ?? [];
    entries.value = rows.map((e) => SaleEntry.fromV4(e as Map<String, dynamic>)).toList();
  }

  /// V4: Save a single sale entry.
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
    if (qty == 0) {
      errorMessage.value = 'Qty must not be 0.';
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

    final res = await ApiClient.post('/v4/transaction', {
      'location_id':      locId,
      'transaction_date': _date,
      'transaction_type': 'sale',
      'party_id':         customerId.value,
      'lines': [{
        'product_id': productId.value,
        'qty':        qty,
        'rate':       rate,
      }],
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

  // V4: Delete a transaction
  Future<void> deleteEntry(int id) async {
    errorMessage.value   = '';
    successMessage.value = '';
    final res = await ApiClient.delete('/v4/transaction/$id');
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

  // V4: Fetch stock
  Future<void> _fetchStock() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    final date = _date;
    final from = DateFormat('yyyy-MM-dd')
        .format(DateTime.parse(date).subtract(const Duration(days: 29)));
    final res = await ApiClient.get(
        '/v4/stock?location_id=$locId&from=$from&to=$date');
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
