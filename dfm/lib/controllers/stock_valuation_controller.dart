// lib/controllers/stock_valuation_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';
import '../models/models.dart';

class StockValuationController extends GetxController {
  final isLoading      = false.obs;
  final isSavingRates  = false.obs;
  final products       = <DairyProduct>[].obs;
  final stockDays      = <StockDayRow>[].obs;
  final estimatedRates = <EstimatedRate>[].obs;
  final errorMessage   = ''.obs;
  final successMessage = ''.obs;
  final showRateEditor = false.obs;
  final reportLocId    = RxnInt();

  final Map<int, TextEditingController> rateCtrlMap = {};
  final ratesFormKey = GlobalKey<FormState>();

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
    _loadInitial();
    ever(LocationService.instance.selected, (_) {
      reportLocId.value = null;
      fetchValuation();
    });
  }

  @override
  void onClose() { for (final c in rateCtrlMap.values) { c.dispose(); } super.onClose(); }

  Future<void> _loadInitial() async {
    isLoading.value = true;
    final rateRes = await ApiClient.get('/estimated-rates');
    isLoading.value = false;
    if (!rateRes.ok) {
      errorMessage.value = rateRes.message ?? 'Failed to load estimated rates.';
      return;
    }
    estimatedRates.value = (rateRes.data as List)
        .map((e) => EstimatedRate.fromJson(e as Map<String, dynamic>)).toList();
    for (final r in estimatedRates) {
      rateCtrlMap[r.productId] =
          TextEditingController(text: r.rate.toStringAsFixed(2));
    }
    await fetchValuation();
  }

  Future<void> fetchValuation() async {
    final locId = _effectiveLocId();
    if (locId == null) {
      // Stock valuation requires a specific location
      stockDays.clear();
      products.clear();
      errorMessage.value = 'Select a location to view stock valuation.';
      return;
    }
    isLoading.value    = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/stock-valuation?location_id=$locId');
    isLoading.value = false;
    if (res.ok) {
      products.value  = (res.data['products'] as List)
          .map((e) => DairyProduct.fromJson(e)).toList();
      stockDays.value = (res.data['dates'] as List)
          .map((e) => StockDayRow.fromJson(e)).toList().reversed.toList();
      debugPrint('[StockValuationController] loaded ${stockDays.length} days');
    } else {
      errorMessage.value = res.message ?? 'Valuation load failed.';
    }
  }

  Future<void> saveRates() async {
    if (!(ratesFormKey.currentState?.validate() ?? false)) return;
    isSavingRates.value  = true;
    errorMessage.value   = '';
    successMessage.value = '';
    final rates = estimatedRates.map((r) => {
      'product_id': r.productId,
      'rate': double.tryParse(rateCtrlMap[r.productId]?.text ?? '') ?? r.rate,
    }).toList();
    final res = await ApiClient.post('/estimated-rates', {'rates': rates});
    isSavingRates.value = false;
    if (res.ok) {
      successMessage.value = 'Rates updated.';
      showRateEditor.value = false;
      await fetchValuation();
    } else {
      errorMessage.value = res.message ?? 'Save failed.';
    }
  }
}
