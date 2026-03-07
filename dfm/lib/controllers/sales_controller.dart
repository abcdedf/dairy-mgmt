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
  final customers           = <Customer>[].obs;
  final entries             = <SaleEntry>[].obs;
  final selectedProdId      = RxnInt();
  final selectedCustomerId  = RxnInt();
  final entryDate           = DateTime.now().obs;
  final errorMessage        = ''.obs;
  final successMessage      = ''.obs;

  final qtyCtrl  = TextEditingController();
  final rateCtrl = TextEditingController();
  final formKey  = GlobalKey<FormState>();
  final _deletableIds = <int>{};          // entries added this session

  String get _date => DateFormat('yyyy-MM-dd').format(entryDate.value);
  int    get dayQty   => entries.fold(0, (s, e) => s + e.quantityKg);
  double get dayTotal => entries.fold(0.0, (s, e) => s + e.total);
  bool canDelete(int id) => _deletableIds.contains(id);

  @override
  void onInit() {
    super.onInit();
    _loadInit();
    ever(LocationService.instance.selected, (_) => fetchSales());
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
  }

  Future<void> _loadCustomers() async {
    final res = await ApiClient.get('/customers');
    if (res.ok) {
      customers.value = (res.data as List)
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
          .toList();
      if (customers.isNotEmpty) {
        selectedCustomerId.value = customers.first.id;
      }
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
    // Preferred dropdown order: commonly sold items first, raw/ingredient last
    const salesOrder = <int, int>{2: 0, 5: 1, 6: 2, 4: 3, 3: 4};
    final fallback = salesOrder.length;
    products.value = (res.data['products'] as List)
        .map((e) => DairyProduct.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) =>
          (salesOrder[a.id] ?? fallback).compareTo(
              salesOrder[b.id] ?? fallback));
    if (products.isNotEmpty && selectedProdId.value == null) {
      selectedProdId.value = products.first.id;
    }
    entries.value = (res.data['entries'] as List)
        .map((e) => SaleEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final locId      = LocationService.instance.locId;
    final prodId     = selectedProdId.value;
    final customerId = selectedCustomerId.value;
    if (locId == null || prodId == null) return;
    if (customerId == null) {
      errorMessage.value = 'Please select a customer.';
      return;
    }
    isSaving.value       = true;
    errorMessage.value   = '';
    successMessage.value = '';
    final res = await ApiClient.post('/sales', {
      'location_id': locId,
      'entry_date':  _date,
      'product_id':  prodId,
      'customer_id': customerId,
      'quantity_kg': int.tryParse(qtyCtrl.text) ?? 0,
      'rate':        double.tryParse(rateCtrl.text) ?? 0.0,
    });
    isSaving.value = false;
    if (res.ok) {
      successMessage.value = 'Saved.';
      qtyCtrl.clear();
      rateCtrl.clear();
      final newId = res.data['id'];
      if (newId != null) _deletableIds.add(int.parse(newId.toString()));
      await fetchSales(keepDeletable: true);
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
    }
  }
}
