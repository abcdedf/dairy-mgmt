// lib/controllers/vendor_ledger_controller.dart

import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class VendorLedgerRow {
  final String date;
  final String locationName;
  final String vendorName;
  final double purchases;
  final double payments;
  final double balance;

  const VendorLedgerRow({
    required this.date,
    required this.locationName,
    required this.vendorName,
    required this.purchases,
    required this.payments,
    required this.balance,
  });

  factory VendorLedgerRow.fromJson(Map<String, dynamic> j) => VendorLedgerRow(
    date:         j['date']?.toString() ?? '',
    locationName: j['location_name']?.toString() ?? '',
    vendorName:   j['vendor_name']?.toString() ?? '',
    purchases:    double.tryParse(j['purchases']?.toString() ?? '') ?? 0,
    payments:     double.tryParse(j['payments']?.toString() ?? '') ?? 0,
    balance:      double.tryParse(j['balance']?.toString() ?? '') ?? 0,
  );
}

class VendorDropdownItem {
  final int id;
  final String name;
  const VendorDropdownItem({required this.id, required this.name});
  factory VendorDropdownItem.fromJson(Map<String, dynamic> j) => VendorDropdownItem(
    id:   int.parse(j['id'].toString()),
    name: j['name']?.toString() ?? '',
  );
}

class VendorLedgerController extends GetxController {
  final isLoading        = false.obs;
  final isSaving         = false.obs;
  final errorMessage     = ''.obs;
  final rows             = <VendorLedgerRow>[].obs;
  final vendorList       = <VendorDropdownItem>[].obs;
  final selectedVendorId = 0.obs;  // 0 = All
  final reportLocId      = RxnInt();

  final _fmt = DateFormat('yyyy-MM-dd');

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
    fetchLedger();
    ever(LocationService.instance.selected, (_) {
      reportLocId.value = null;
      fetchLedger();
    });
  }

  Future<void> fetchLedger() async {
    isLoading.value    = true;
    errorMessage.value = '';
    final locId = _effectiveLocId();
    final params = <String>[];
    if (locId != null) params.add('location_id=$locId');
    if (selectedVendorId.value > 0) params.add('vendor_id=${selectedVendorId.value}');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    final res = await ApiClient.get('/vendor-ledger$query');
    isLoading.value = false;
    if (res.ok) {
      rows.value = (res.data['rows'] as List)
          .map((e) => VendorLedgerRow.fromJson(e as Map<String, dynamic>))
          .toList();
      if (res.data['vendors'] != null) {
        vendorList.value = (res.data['vendors'] as List)
            .map((e) => VendorDropdownItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } else {
      errorMessage.value = res.message ?? 'Failed to load vendor ledger.';
    }
  }

  Future<bool> savePayment({
    required int    vendorId,
    required DateTime date,
    required double amount,
    required String method,
    String? note,
  }) async {
    isSaving.value     = true;
    errorMessage.value = '';
    final res = await ApiClient.post('/vendor-payment', {
      'vendor_id':    vendorId,
      'payment_date': _fmt.format(date),
      'amount':       amount,
      'method':       method,
      'note':         note ?? '',
    });
    isSaving.value = false;
    if (res.ok) {
      return true;
    } else {
      errorMessage.value = res.message ?? 'Failed to save payment.';
      return false;
    }
  }
}
