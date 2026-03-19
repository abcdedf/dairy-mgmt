// lib/controllers/challan_controller.dart

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

// ── Models ────────────────────────────────────────────────

class ChallanLine {
  final int? id;
  final int? productId;
  final int? pouchProductId;
  final String productName;
  final String productUnit;
  final double qty;
  final double rate;
  final double amount;

  const ChallanLine({
    this.id,
    this.productId,
    this.pouchProductId,
    this.productName = '',
    this.productUnit = '',
    required this.qty,
    required this.rate,
    required this.amount,
  });

  bool get isPouch => pouchProductId != null;

  factory ChallanLine.fromJson(Map<String, dynamic> j) => ChallanLine(
    id:              int.tryParse(j['id']?.toString() ?? ''),
    productId:       int.tryParse(j['product_id']?.toString() ?? ''),
    pouchProductId:  int.tryParse(j['pouch_product_id']?.toString() ?? ''),
    productName:     j['product_name']?.toString() ?? '',
    productUnit:     j['product_unit']?.toString() ?? '',
    qty:             double.tryParse(j['qty']?.toString() ?? '') ?? 0,
    rate:            double.tryParse(j['rate']?.toString() ?? '') ?? 0,
    amount:          double.tryParse(j['amount']?.toString() ?? '') ?? 0,
  );
}

class Challan {
  final int id;
  final int locationId;
  final int partyId;
  final String partyName;
  final int challanNumber;
  final String challanDate;
  final String? deliveryAddress;
  final String? billingAddressSnapshot;
  final String? shippingAddressSnapshot;
  final String status;
  final String? notes;
  final List<ChallanLine> lines;
  final String createdAt;

  const Challan({
    required this.id,
    required this.locationId,
    required this.partyId,
    this.partyName = '',
    required this.challanNumber,
    required this.challanDate,
    this.deliveryAddress,
    this.billingAddressSnapshot,
    this.shippingAddressSnapshot,
    required this.status,
    this.notes,
    required this.lines,
    this.createdAt = '',
  });

  factory Challan.fromJson(Map<String, dynamic> j) => Challan(
    id:              int.parse(j['id'].toString()),
    locationId:      int.parse(j['location_id'].toString()),
    partyId:         int.parse(j['party_id'].toString()),
    partyName:       j['party_name']?.toString() ?? '',
    challanNumber:   int.parse(j['challan_number'].toString()),
    challanDate:     j['challan_date']?.toString() ?? '',
    deliveryAddress: j['delivery_address']?.toString(),
    billingAddressSnapshot:  j['billing_address_snapshot']?.toString(),
    shippingAddressSnapshot: j['shipping_address_snapshot']?.toString(),
    status:          j['status']?.toString() ?? 'pending',
    notes:           j['notes']?.toString(),
    lines:           (j['lines'] as List? ?? [])
        .map((e) => ChallanLine.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt:       j['created_at']?.toString() ?? '',
  );

  double get total => lines.fold(0.0, (s, l) => s + l.amount);
  bool get isPending => status == 'pending';
}

class ChallanCustomer {
  final int id;
  final String name;
  final List<int> productIds;
  const ChallanCustomer({required this.id, required this.name, this.productIds = const []});
  factory ChallanCustomer.fromJson(Map<String, dynamic> j) => ChallanCustomer(
    id:         int.parse(j['id'].toString()),
    name:       j['name']?.toString() ?? '',
    productIds: (j['product_ids'] as List?)
        ?.map((e) => int.tryParse(e.toString()) ?? 0)
        .toList() ?? [],
  );
  bool get hasPouch => productIds.contains(12);
}

class ChallanProduct {
  final int id;
  final String name;
  final String unit;
  const ChallanProduct({required this.id, required this.name, required this.unit});
  factory ChallanProduct.fromJson(Map<String, dynamic> j) => ChallanProduct(
    id:   int.parse(j['id'].toString()),
    name: j['name']?.toString() ?? '',
    unit: j['unit']?.toString() ?? '',
  );
}

class ChallanPouchProduct {
  final int id;
  final String name;
  final int pouchesPerCrate;
  final double crateRate;
  const ChallanPouchProduct({required this.id, required this.name, required this.pouchesPerCrate, required this.crateRate});
  factory ChallanPouchProduct.fromJson(Map<String, dynamic> j) => ChallanPouchProduct(
    id:              int.parse(j['id'].toString()),
    name:            j['name']?.toString() ?? '',
    pouchesPerCrate: int.tryParse(j['pouches_per_crate']?.toString() ?? '12') ?? 12,
    crateRate:       double.tryParse(j['crate_rate']?.toString() ?? '0') ?? 0,
  );
}

class CustomerPouchRate {
  final int partyId;
  final int pouchProductId;
  final double crateRate;
  const CustomerPouchRate({required this.partyId, required this.pouchProductId, required this.crateRate});
  factory CustomerPouchRate.fromJson(Map<String, dynamic> j) => CustomerPouchRate(
    partyId:        int.parse(j['party_id'].toString()),
    pouchProductId: int.parse(j['pouch_product_id'].toString()),
    crateRate:      double.tryParse(j['crate_rate']?.toString() ?? '0') ?? 0,
  );
}

// ── Controller ────────────────────────────────────────────

class ChallanController extends GetxController {
  final isLoading    = false.obs;
  final isSaving     = false.obs;
  final errorMessage = ''.obs;
  final challans     = <Challan>[].obs;
  final customers     = <ChallanCustomer>[].obs;
  final products      = <ChallanProduct>[].obs;
  final pouchProducts = <ChallanPouchProduct>[].obs;
  final customerPouchRates = <CustomerPouchRate>[].obs;
  final statusFilter  = 'all'.obs;
  final reportLocId  = RxnInt();

  int? _effectiveLocId() {
    final appBarLoc = LocationService.instance.selected.value;
    if (appBarLoc != null && appBarLoc.code.toLowerCase() == 'test') {
      return appBarLoc.id;
    }
    return reportLocId.value ?? LocationService.instance.locId;
  }

  @override
  void onInit() {
    super.onInit();
    fetchChallans();
    ever(LocationService.instance.selected, (_) {
      reportLocId.value = null;
      fetchChallans();
    });
  }

  Future<void> fetchChallans() async {
    final locId = _effectiveLocId();
    if (locId == null) return;
    isLoading.value    = true;
    errorMessage.value = '';
    try {
      final status = statusFilter.value;
      final res = await ApiClient.get(
          '/v4/challans?location_id=$locId&status=$status');
      isLoading.value = false;
      if (res.ok) {
        challans.value = (res.data['challans'] as List)
            .map((e) => Challan.fromJson(e as Map<String, dynamic>))
            .toList();
        if (res.data['customers'] != null) {
          customers.value = (res.data['customers'] as List)
              .map((e) => ChallanCustomer.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (res.data['products'] != null) {
          products.value = (res.data['products'] as List)
              .map((e) => ChallanProduct.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (res.data['pouch_products'] != null) {
          pouchProducts.value = (res.data['pouch_products'] as List)
              .map((e) => ChallanPouchProduct.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (res.data['customer_pouch_rates'] != null) {
          customerPouchRates.value = (res.data['customer_pouch_rates'] as List)
              .map((e) => CustomerPouchRate.fromJson(e as Map<String, dynamic>))
              .toList();
          debugPrint('[ChallanController] loaded ${customerPouchRates.length} customer pouch rates');
        }
      } else {
        errorMessage.value = res.message ?? 'Failed to load challans.';
      }
    } catch (e, st) {
      isLoading.value = false;
      errorMessage.value = 'Unexpected error loading challans.';
      if (kDebugMode) debugPrint('[ChallanController] fetchChallans error: $e\n$st');
    }
  }

  /// Returns customer-specific rate if one exists, otherwise the global pouch product rate.
  double rateForCustomerPouch(int partyId, int pouchProductId) {
    final override = customerPouchRates.firstWhereOrNull(
      (r) => r.partyId == partyId && r.pouchProductId == pouchProductId,
    );
    if (override != null) return override.crateRate;
    final pp = pouchProducts.firstWhereOrNull((p) => p.id == pouchProductId);
    return pp?.crateRate ?? 0;
  }

  Future<bool> saveChallan({
    required int locationId,
    required int partyId,
    required String challanDate,
    required String deliveryAddress,
    String billingAddressSnapshot = '',
    String shippingAddressSnapshot = '',
    required String notes,
    required List<Map<String, dynamic>> lines,
  }) async {
    final locId = locationId;
    isSaving.value     = true;
    errorMessage.value = '';
    try {
      debugPrint('[ChallanController] saveChallan: locId=$locId, partyId=$partyId, billingSnap=${billingAddressSnapshot.length} chars, shippingSnap=${shippingAddressSnapshot.length} chars');
      final res = await ApiClient.post('/v4/challan', {
        'location_id':               locId,
        'party_id':                  partyId,
        'challan_date':              challanDate,
        'delivery_address':          deliveryAddress,
        'billing_address_snapshot':  billingAddressSnapshot,
        'shipping_address_snapshot': shippingAddressSnapshot,
        'notes':                     notes,
        'lines':                     lines,
      });
      isSaving.value = false;
      if (res.ok) return true;
      errorMessage.value = res.message ?? 'Failed to save challan.';
      return false;
    } catch (e, st) {
      isSaving.value = false;
      errorMessage.value = 'Unexpected error saving challan.';
      if (kDebugMode) debugPrint('[ChallanController] saveChallan error: $e\n$st');
      return false;
    }
  }

  Future<bool> deleteChallan(int id) async {
    errorMessage.value = '';
    try {
      final res = await ApiClient.delete('/v4/challan/$id');
      if (res.ok) return true;
      errorMessage.value = res.message ?? 'Failed to delete challan.';
      return false;
    } catch (e, st) {
      errorMessage.value = 'Unexpected error deleting challan.';
      if (kDebugMode) debugPrint('[ChallanController] deleteChallan error: $e\n$st');
      return false;
    }
  }
}
