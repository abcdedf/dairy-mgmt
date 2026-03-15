// lib/controllers/transactions_controller.dart

import 'dart:convert';
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
  final String locationName;

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
    required this.locationName,
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
      locationName: j['location_name']?.toString() ?? '',
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
  final String locationName;
  final Map<String, dynamic> raw; // all fields for detail display

  const ProdTx({
    required this.id,
    required this.type,
    required this.date,
    required this.createdAt,
    required this.userName,
    required this.locationName,
    required this.raw,
  });

  factory ProdTx.fromJson(Map<String, dynamic> j) => ProdTx(
    id:           num.tryParse(j['id']?.toString() ?? '')?.toInt() ?? 0,
    type:         j['type']?.toString() ?? '',
    date:         j['entry_date']?.toString() ?? '',
    createdAt:    j['created_at']?.toString() ?? '',
    userName:     j['user_name']?.toString() ?? '',
    locationName: j['location_name']?.toString() ?? '',
    raw:          j,
  );

  /// True if this is a reversal entry (primary lines have negative qty for purchases,
  /// positive qty for sales — opposite of normal sign convention).
  bool get isReversal {
    final lines = raw['lines'] as List?;
    if (lines == null || lines.isEmpty) return false;
    final txnType = raw['transaction_type']?.toString() ?? '';
    final procType = raw['processing_type']?.toString() ?? '';
    final firstQty = double.tryParse(
        (lines[0] as Map<String, dynamic>)['qty']?.toString() ?? '0') ?? 0;
    if (txnType == 'purchase' && firstQty < 0) {
      debugPrint('[isReversal] id=$id purchase firstQty=$firstQty → reversal');
      return true;
    }
    if (txnType == 'sale' && firstQty > 0) {
      debugPrint('[isReversal] id=$id sale firstQty=$firstQty → reversal');
      return true;
    }
    if (txnType == 'processing') {
      // Normal processing: inputs negative (consumed), outputs positive (produced).
      // A reversal flips ALL signs. Detect by checking if every qty is non-positive
      // (i.e. no positive outputs exist — everything was reversed).
      final typed = lines.cast<Map<String, dynamic>>();
      final allNonPositive = typed.every((l) =>
          (double.tryParse(l['qty']?.toString() ?? '0') ?? 0) <= 0);
      if (allNonPositive) {
        debugPrint('[isReversal] id=$id proc=$procType allNonPositive → reversal');
        return true;
      }
    }
    return false;
  }

  // Human-readable summary line of what this transaction contains.
  // Supports both V3 (flat fields) and V4 (lines array) data.
  String get summary {
    // V4 format: has 'lines' array
    final lines = raw['lines'] as List?;
    if (lines != null && lines.isNotEmpty) return _v4Summary(lines);
    // V3 fallback
    return _v3Summary();
  }

  String _v4Summary(List lines) {
    final party = raw['party_name']?.toString() ?? '';
    final partyStr = party.isNotEmpty && party != 'Internal' ? '  •  $party' : '';

    // Separate positive (outputs/purchases) and negative (inputs/sales)
    final typed = lines.cast<Map<String, dynamic>>();
    final pos = typed.where((l) => (double.tryParse(l['qty']?.toString() ?? '0') ?? 0) > 0).toList();
    final neg = typed.where((l) => (double.tryParse(l['qty']?.toString() ?? '0') ?? 0) < 0).toList();

    String fmtLine(Map<String, dynamic> l) {
      final name = l['product_name']?.toString() ?? '';
      final rawQty = double.tryParse(l['qty']?.toString() ?? '0') ?? 0;
      final rate = l['rate'] != null ? double.tryParse(l['rate'].toString()) : null;
      final snf = l['snf'] != null ? double.tryParse(l['snf'].toString()) : null;
      final fat = l['fat'] != null ? double.tryParse(l['fat'].toString()) : null;
      final parts = <String>['$name ${rawQty.toInt()} KG'];
      if (snf != null) parts.add('SNF $snf');
      if (fat != null) parts.add('Fat $fat');
      if (rate != null) parts.add('₹${rate.toStringAsFixed(2)}');
      return parts.join('  ');
    }

    final txnType = raw['transaction_type']?.toString() ?? '';
    if (txnType == 'purchase') {
      final display = pos.isNotEmpty ? pos : neg; // reversals have negative qty
      return '${display.map(fmtLine).join(', ')}$partyStr';
    }
    if (txnType == 'sale') {
      final display = neg.isNotEmpty ? neg : pos; // reversals have positive qty
      return '${display.map(fmtLine).join(', ')}$partyStr';
    }
    // Processing
    final totalIn = neg.fold<double>(0, (s, l) => s + (double.tryParse(l['qty']?.toString() ?? '0') ?? 0).abs());
    // Filter out product 12 (Pouch Milk aggregate) from generic output — show pouch details instead
    final procType = raw['processing_type']?.toString() ?? '';
    final displayPos = procType == 'pouch_production'
        ? pos.where((l) => (int.tryParse(l['product_id']?.toString() ?? '0') ?? 0) != 12).toList()
        : pos;
    final outStr = displayPos.map(fmtLine).join('  +  ');
    // Check for madhusudan (no outputs)
    if (displayPos.isEmpty && procType != 'pouch_production') {
      final notes = raw['notes'];
      String rateStr = '';
      if (notes != null) {
        try {
          final n = notes is Map ? notes : (notes is String ? Map<String, dynamic>.from(const JsonDecoder().convert(notes)) : {});
          final sr = n['sale_rate'];
          if (sr != null) rateStr = '  •  ₹${double.parse(sr.toString()).toStringAsFixed(2)}/KG';
        } catch (_) {}
      }
      return '${totalIn.toInt()} KG$rateStr';
    }
    // Pouch production: append pouch line details from notes
    if (procType == 'pouch_production') {
      String pouchStr = '';
      final notes = raw['notes'];
      if (notes != null) {
        try {
          final n = notes is Map ? notes : (notes is String ? Map<String, dynamic>.from(const JsonDecoder().convert(notes)) : {});
          final pouchLines = (n['pouch_lines'] as List?) ?? [];
          final parts = <String>[];
          for (final pl in pouchLines) {
            final name = pl['name']?.toString() ?? 'Pouch';
            final crates = pl['crate_count'] ?? 0;
            parts.add('$name: $crates crates');
          }
          if (parts.isNotEmpty) pouchStr = '  +  ${parts.join(', ')}';
        } catch (_) {}
      }
      return '${totalIn.toInt()} KG  →  $outStr$pouchStr';
    }
    return '${totalIn.toInt()} KG  →  $outStr';
  }

  String _v3Summary() {
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
      final res = await ApiClient.get(
          '/sales-transactions$locParam');
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
      final res = await ApiClient.get(
          '/production-transactions$locParam');
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
