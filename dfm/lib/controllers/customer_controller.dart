// lib/controllers/customer_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../models/models.dart';

class CustomerController extends GetxController {
  final isLoading      = false.obs;
  final isSaving       = false.obs;
  final customers      = <Customer>[].obs;
  final products       = <DairyProduct>[].obs;
  final locations      = <DairyLocation>[].obs;
  final errorMessage   = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _loadAll();
  }

  Future<void> _loadAll() async {
    isLoading.value = true;
    await Future.wait([_loadCustomers(), _loadProducts(), _loadLocations()]);
    isLoading.value = false;
  }

  Future<void> _loadCustomers() async {
    final res = await ApiClient.get('/customers?all=1');
    if (res.ok) {
      customers.value = (res.data as List)
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
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

  Future<void> _loadLocations() async {
    final res = await ApiClient.get('/locations');
    if (res.ok) {
      locations.value = (res.data as List)
          .map((e) => DairyLocation.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  List<DairyProduct> get sellableProducts =>
      products.where((p) => ![6, 7, 8, 9].contains(p.id)).toList();

  Future<bool> saveCustomer(String name, List<int> productIds, List<int> locationIds) async {
    isSaving.value     = true;
    errorMessage.value = '';
    final res = await ApiClient.post('/customers', {
      'name': name,
      'product_ids': productIds,
      'location_ids': locationIds,
    });
    isSaving.value = false;
    if (res.ok) {
      await _loadCustomers();
      return true;
    }
    errorMessage.value = res.message ?? 'Save failed.';
    return false;
  }

  Future<bool> updateCustomer(int id, String name, List<int> productIds, List<int> locationIds, {bool? isActive}) async {
    isSaving.value     = true;
    errorMessage.value = '';
    final body = <String, dynamic>{
      'name': name,
      'product_ids': productIds,
      'location_ids': locationIds,
    };
    if (isActive != null) body['is_active'] = isActive ? 1 : 0;
    final res = await ApiClient.post('/customers/$id', body);
    isSaving.value = false;
    if (res.ok) {
      await _loadCustomers();
      return true;
    }
    errorMessage.value = res.message ?? 'Update failed.';
    return false;
  }
}
