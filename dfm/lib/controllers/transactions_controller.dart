// lib/controllers/transactions_controller.dart

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

// ── Sales transaction row ─────────────────────────────────────

class SaleTx {
  final int    id;
  final String date;
  final String productName;
  final String customerName;
  final int    quantityKg;
  final double rate;
  final double total;
  final String createdAt;
  final String userName;

  const SaleTx({
    required this.id,
    required this.date,
    required this.productName,
    required this.customerName,
    required this.quantityKg,
    required this.rate,
    required this.total,
    required this.createdAt,
    required this.userName,
  });

  factory SaleTx.fromJson(Map<String, dynamic> j) {
    // ARRAY_A returns all values as strings — parse safely
    num n(String k) => num.tryParse(j[k]?.toString() ?? '') ?? 0;
    return SaleTx(
      id:           n('id').toInt(),
      date:         j['entry_date']?.toString() ?? '',
      productName:  j['product_name']?.toString() ?? '',
      customerName: j['customer_name']?.toString() ?? '',
      quantityKg:   n('quantity_kg').toInt(),
      rate:         n('rate').toDouble(),
      total:        n('total').toDouble(),
      createdAt:    j['created_at']?.toString() ?? '',
      userName:     j['user_name']?.toString() ?? '',
    );
  }
}

// ── Production transaction row ────────────────────────────────

class ProdTx {
  final int    id;
  final String type;       // e.g. "FF Milk Purchase", "Cream Processing"
  final String date;
  final String createdAt;
  final String userName;
  final Map<String, dynamic> raw; // all fields for detail display

  const ProdTx({
    required this.id,
    required this.type,
    required this.date,
    required this.createdAt,
    required this.userName,
    required this.raw,
  });

  factory ProdTx.fromJson(Map<String, dynamic> j) => ProdTx(
    id:        num.tryParse(j['id']?.toString() ?? '')?.toInt() ?? 0,
    type:      j['type']?.toString() ?? '',
    date:      j['entry_date']?.toString() ?? '',
    createdAt: j['created_at']?.toString() ?? '',
    userName:  j['user_name']?.toString() ?? '',
    raw:       j,
  );

  // Human-readable summary line of what this transaction contains
  String get summary {
    num n(String k) => num.tryParse(raw[k]?.toString() ?? '') ?? 0;
    String s(String k) => raw[k]?.toString() ?? '';
    switch (type) {
      case 'FF Milk Purchase':
        final vendor = s('vendor_name').isNotEmpty ? '  •  ${s('vendor_name')}' : '';
        return '${n('input_ff_milk_kg').toInt()} KG$vendor  •  '
               'SNF ${n('input_snf')}  Fat ${n('input_fat')}  '
               '₹${n('input_rate').toStringAsFixed(2)}/KG';
      case 'FF Milk Processing':
        return 'Used ${n('input_ff_milk_used_kg').toInt()} KG  →  '
               'Skim ${n('output_skim_milk_kg').toInt()} KG (SNF ${n('output_skim_snf')})  '
               'Cream ${n('output_cream_kg').toInt()} KG (Fat ${n('output_cream_fat')})';
      case 'Cream Purchase':
        final vendor = s('vendor_name').isNotEmpty ? '  •  ${s('vendor_name')}' : '';
        return '${n('input_cream_kg').toInt()} KG$vendor  •  '
               'Fat ${n('input_fat')}  ₹${n('input_rate').toStringAsFixed(2)}/KG';
      case 'Cream Processing':
        return 'Used ${n('input_cream_used_kg').toInt()} KG  →  '
               'Butter ${n('output_butter_kg').toInt()} KG (Fat ${n('output_butter_fat')})  '
               'Ghee ${n('output_ghee_kg').toInt()} KG';
      case 'Butter Purchase':
        final vendor = s('vendor_name').isNotEmpty ? '  •  ${s('vendor_name')}' : '';
        return '${n('input_butter_kg').toInt()} KG$vendor  •  '
               'Fat ${n('input_fat')}  ₹${n('input_rate').toStringAsFixed(2)}/KG';
      case 'Butter Processing':
        return 'Used ${n('input_butter_used_kg').toInt()} KG  →  '
               'Ghee ${n('output_ghee_kg').toInt()} KG';
      case 'Dahi Production':
        return 'SMP ${n('input_smp_bags').toInt()} bags  '
               'Culture ${n('input_culture_kg').toInt()} KG  '
               'Protein ${n('input_protein_kg').toInt()} KG  '
               'Skim ${n('input_skim_milk_kg').toInt()} KG  →  '
               '${n('output_container_count').toInt()} containers';
      case 'Pouch Production':
        return 'FF Milk ${n('total_ff_milk_kg').toInt()} KG  →  '
               'Cream ${n('output_cream_kg').toInt()} KG (Fat ${n('output_cream_fat')})';
      case 'Curd Production':
        return 'FF Milk ${n('total_ff_milk_kg').toInt()} KG  →  '
               'Cream ${n('output_cream_kg').toInt()} KG (Fat ${n('output_cream_fat')})  +  '
               '${n('output_curd_matka').toInt()} Matka';
      case 'Madhusudan Sale':
        return '${n('total_ff_milk_kg').toInt()} KG  •  '
               '₹${n('sale_rate').toStringAsFixed(2)}/KG';
      case 'Ingredient Purchase':
        return '${s('product_name')} ${n('quantity')} — ₹${n('rate').toStringAsFixed(2)}';
      default:
        return type;
    }
  }
}

// ── Sales Transactions Controller ────────────────────────────

class SalesTransactionsController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final rows         = <SaleTx>[].obs;
  final days         = 7.obs;

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
      final res = await ApiClient.get(
          '/sales-transactions?location_id=$locId');
      isLoading.value = false;
      if (!res.ok) {
        errorMessage.value = res.message ?? 'Error loading transactions.';
        return;
      }
      days.value = num.tryParse(res.data['days']?.toString() ?? '')?.toInt() ?? 7;
      rows.value = (res.data['rows'] as List)
          .map((e) => SaleTx.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      isLoading.value    = false;
      errorMessage.value = 'Unexpected error loading sales transactions.';
      debugPrint('[SalesTransactionsController] fetchReport error: $e\n$st');
    }
  }
}

// ── Production Transactions Controller ───────────────────────

class ProductionTransactionsController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final rows         = <ProdTx>[].obs;
  final days         = 7.obs;

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
      final res = await ApiClient.get(
          '/production-transactions?location_id=$locId');
      isLoading.value = false;
      if (!res.ok) {
        errorMessage.value = res.message ?? 'Error loading transactions.';
        return;
      }
      final rawRows = res.data['rows'] as List;
      days.value = num.tryParse(res.data['days']?.toString() ?? '')?.toInt() ?? 7;
      rows.value = rawRows
          .map((e) => ProdTx.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      isLoading.value    = false;
      errorMessage.value = 'Unexpected error loading production transactions.';
      if (kDebugMode) debugPrint('[ProdTx] fetchReport error: $e\n$st');
    }
  }
}
