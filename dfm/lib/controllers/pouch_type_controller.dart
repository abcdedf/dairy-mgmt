// lib/controllers/pouch_type_controller.dart

import 'package:flutter/foundation.dart';
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
    final res = await ApiClient.get('/pouch-products');
    if (res.ok) {
      pouchTypes.value = (res.data as List)
          .map((e) => PouchType.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      errorMessage.value = res.message ?? 'Failed to load pouch types.';
    }
    isLoading.value = false;
  }

  Future<bool> savePouchType(String name, double milkPerPouch, int pouchesPerCrate, {double crateRate = 0}) async {
    errorMessage.value = '';
    successMessage.value = '';
    final res = await ApiClient.post('/pouch-products', {
      'name': name,
      'milk_per_pouch': milkPerPouch,
      'pouches_per_crate': pouchesPerCrate,
      'crate_rate': crateRate,
    });
    if (res.ok) {
      successMessage.value = 'Pouch type added.';
      await fetchPouchTypes();
      return true;
    }
    errorMessage.value = res.message ?? 'Failed to save.';
    return false;
  }

  Future<bool> updatePouchType(int id, {String? name, double? milkPerPouch, int? pouchesPerCrate, double? crateRate, int? isActive}) async {
    errorMessage.value = '';
    successMessage.value = '';
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (milkPerPouch != null) body['milk_per_pouch'] = milkPerPouch;
    if (pouchesPerCrate != null) body['pouches_per_crate'] = pouchesPerCrate;
    if (crateRate != null) body['crate_rate'] = crateRate;
    if (isActive != null) body['is_active'] = isActive;
    final res = await ApiClient.post('/pouch-products/$id', body);
    if (res.ok) {
      successMessage.value = 'Pouch type updated.';
      await fetchPouchTypes();
      return true;
    }
    errorMessage.value = res.message ?? 'Failed to update.';
    return false;
  }

  // ── Customer pouch rates ──────────────────────────────

  Future<List<Map<String, dynamic>>> fetchCustomerPouchRates(int pouchProductId) async {
    debugPrint('[PouchTypeController] fetchCustomerPouchRates: ppId=$pouchProductId');
    final res = await ApiClient.get('/customer-pouch-rates?pouch_product_id=$pouchProductId');
    if (res.ok) {
      final rows = List<Map<String, dynamic>>.from(res.data as List);
      debugPrint('[PouchTypeController] got ${rows.length} customer rates');
      return rows;
    }
    return [];
  }

  Future<bool> saveCustomerPouchRate(int partyId, int pouchProductId, double crateRate) async {
    debugPrint('[PouchTypeController] saveCustomerPouchRate: party=$partyId pouch=$pouchProductId rate=$crateRate');
    final res = await ApiClient.post('/customer-pouch-rates', {
      'party_id': partyId,
      'pouch_product_id': pouchProductId,
      'crate_rate': crateRate,
    });
    return res.ok;
  }

  Future<bool> deleteCustomerPouchRate(int id) async {
    debugPrint('[PouchTypeController] deleteCustomerPouchRate: id=$id');
    final res = await ApiClient.delete('/customer-pouch-rates/$id');
    return res.ok;
  }

  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    final res = await ApiClient.get('/customers?all=1');
    if (res.ok) {
      return (res.data as List).map((e) => {
        'id': int.parse(e['id'].toString()),
        'name': e['name']?.toString() ?? '',
      }).toList();
    }
    return [];
  }
}
