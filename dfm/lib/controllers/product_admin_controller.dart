// lib/controllers/product_admin_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';

class AdminProduct {
  final int id;
  final String name;
  final String unit;
  final int sortOrder;
  final bool isActive;
  final double rate;
  const AdminProduct({required this.id, required this.name, required this.unit,
      required this.sortOrder, required this.isActive, required this.rate});
  factory AdminProduct.fromJson(Map<String, dynamic> j) => AdminProduct(
    id: int.parse(j['id'].toString()),
    name: j['name'].toString(),
    unit: j['unit']?.toString() ?? 'KG',
    sortOrder: int.tryParse(j['sort_order']?.toString() ?? '0') ?? 0,
    isActive: j['is_active']?.toString() != '0',
    rate: double.tryParse(j['rate']?.toString() ?? '0') ?? 0,
  );
}

class ProductAdminController extends GetxController {
  final isLoading    = false.obs;
  final isSaving     = false.obs;
  final products     = <AdminProduct>[].obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    isLoading.value = true;
    final res = await ApiClient.get('/admin/products');
    isLoading.value = false;
    if (res.ok) {
      products.value = (res.data as List)
          .map((e) => AdminProduct.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<bool> updateProduct(int id, {String? name, String? unit, double? rate, bool? isActive}) async {
    isSaving.value     = true;
    errorMessage.value = '';
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (unit != null) body['unit'] = unit;
    if (rate != null) body['rate'] = rate;
    if (isActive != null) body['is_active'] = isActive ? 1 : 0;
    final res = await ApiClient.post('/admin/products/$id', body);
    isSaving.value = false;
    if (res.ok) { await _load(); return true; }
    errorMessage.value = res.message ?? 'Update failed.';
    return false;
  }
}
