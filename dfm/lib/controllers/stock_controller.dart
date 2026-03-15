// lib/controllers/stock_controller.dart

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';
import '../models/models.dart';

class StockController extends GetxController {
  final isLoading    = false.obs;
  final products     = <DairyProduct>[].obs;
  final stockDays    = <StockDayRow>[].obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchStock();
    ever(LocationService.instance.selected, (_) => fetchStock());
  }

  Future<void> fetchStock() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    isLoading.value    = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/v4/stock?location_id=$locId');
    isLoading.value = false;
    if (res.ok) {
      products.value  = (res.data['products'] as List)
          .map((e) => DairyProduct.fromJson(e)).toList();
      stockDays.value = (res.data['dates'] as List)
          .map((e) => StockDayRow.fromJson(e)).toList().reversed.toList();
      if (kDebugMode) debugPrint('[StockController] loaded ${stockDays.length} days');
    } else {
      errorMessage.value = res.message ?? 'Error loading stock.';
    }
  }
}
