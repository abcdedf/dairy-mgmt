// lib/controllers/pouch_type_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../models/models.dart';

class PouchTypeController extends GetxController {
  final pouchTypes    = <PouchType>[].obs;
  final isLoading     = false.obs;
  final errorMessage  = ''.obs;
  final successMessage= ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchPouchTypes();
  }

  Future<void> fetchPouchTypes() async {
    isLoading.value = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/pouch-types');
    if (res.ok) {
      pouchTypes.value = (res.data as List)
          .map((e) => PouchType.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      errorMessage.value = res.message ?? 'Failed to load pouch types.';
    }
    isLoading.value = false;
  }

  Future<bool> savePouchType(String name, double litre, double price) async {
    errorMessage.value = '';
    successMessage.value = '';
    final res = await ApiClient.post('/pouch-types', {
      'name': name,
      'litre': litre,
      'price': price,
    });
    if (res.ok) {
      successMessage.value = 'Pouch type added.';
      await fetchPouchTypes();
      return true;
    }
    errorMessage.value = res.message ?? 'Failed to save.';
    return false;
  }

  Future<bool> updatePouchType(int id, {String? name, double? litre, double? price, int? isActive}) async {
    errorMessage.value = '';
    successMessage.value = '';
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (litre != null) body['litre'] = litre;
    if (price != null) body['price'] = price;
    if (isActive != null) body['is_active'] = isActive;
    final res = await ApiClient.post('/pouch-types/$id', body);
    if (res.ok) {
      successMessage.value = 'Pouch type updated.';
      await fetchPouchTypes();
      return true;
    }
    errorMessage.value = res.message ?? 'Failed to update.';
    return false;
  }
}
