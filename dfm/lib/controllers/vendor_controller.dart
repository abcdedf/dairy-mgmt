// lib/controllers/vendor_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../models/models.dart';

class VendorAdminController extends GetxController {
  final isLoading    = false.obs;
  final isSaving     = false.obs;
  final vendors      = <Vendor>[].obs;
  final locations    = <DairyLocation>[].obs;
  final products     = <DairyProduct>[].obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _loadAll();
  }

  Future<void> _loadAll() async {
    isLoading.value = true;
    await Future.wait([_loadVendors(), _loadLocations(), _loadProducts()]);
    isLoading.value = false;
  }

  Future<void> _loadVendors() async {
    final res = await ApiClient.get('/vendors?all=1');
    if (res.ok) {
      vendors.value = (res.data as List)
          .map((e) => Vendor.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadLocations() async {
    final res = await ApiClient.get('/locations');
    if (res.ok) {
      locations.value = (res.data as List)
          .map((e) => DairyLocation.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadProducts() async {
    final res = await ApiClient.get('/products');
    if (res.ok) {
      products.value = (res.data as List)
          .map((e) => DairyProduct.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<bool> saveVendor(String name, List<int> locationIds, List<int> productIds) async {
    isSaving.value     = true;
    errorMessage.value = '';
    final res = await ApiClient.post('/vendors', {
      'name': name,
      'location_ids': locationIds,
      'product_ids': productIds,
    });
    isSaving.value = false;
    if (res.ok) { await _loadVendors(); return true; }
    errorMessage.value = res.message ?? 'Save failed.';
    return false;
  }

  Future<bool> updateVendor(int id, String name, List<int> locationIds, List<int> productIds, {bool? isActive}) async {
    isSaving.value     = true;
    errorMessage.value = '';
    final body = <String, dynamic>{
      'name': name,
      'location_ids': locationIds,
      'product_ids': productIds,
    };
    if (isActive != null) body['is_active'] = isActive ? 1 : 0;
    final res = await ApiClient.post('/vendors/$id', body);
    isSaving.value = false;
    if (res.ok) { await _loadVendors(); return true; }
    errorMessage.value = res.message ?? 'Update failed.';
    return false;
  }
}
