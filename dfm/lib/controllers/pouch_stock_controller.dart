// lib/controllers/pouch_stock_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';
import '../models/models.dart';

class PouchStockController extends GetxController {
  final pouchStock    = <PouchStockRow>[].obs;
  final isLoading     = false.obs;
  final errorMessage  = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchPouchStock();
    ever(LocationService.instance.selected, (_) => fetchPouchStock());
  }

  Future<void> fetchPouchStock() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    isLoading.value = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/pouch-stock?location_id=$locId');
    if (res.ok) {
      pouchStock.value = (res.data as List)
          .map((e) => PouchStockRow.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      errorMessage.value = res.message ?? 'Failed to load pouch stock.';
    }
    isLoading.value = false;
  }
}
