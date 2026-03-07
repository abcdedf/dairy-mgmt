// lib/controllers/vendor_ledger_controller.dart

import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class VendorSummary {
  final int    vendorId;
  final String vendorName;
  final double totalPurchases;
  final double totalPayments;
  final double balanceDue;

  const VendorSummary({
    required this.vendorId,
    required this.vendorName,
    required this.totalPurchases,
    required this.totalPayments,
    required this.balanceDue,
  });

  factory VendorSummary.fromJson(Map<String, dynamic> j) => VendorSummary(
    vendorId:       int.parse(j['vendor_id'].toString()),
    vendorName:     j['vendor_name'] ?? '',
    totalPurchases: double.parse(j['total_purchases'].toString()),
    totalPayments:  double.parse(j['total_payments'].toString()),
    balanceDue:     double.parse(j['balance_due'].toString()),
  );
}

class LedgerTransaction {
  final String  type;         // 'purchase' or 'payment'
  final String  date;
  final String? product;
  final double? quantity;
  final double? rate;
  final double  amount;
  final String? method;
  final String? note;
  final String? locationName;
  final String? userName;

  const LedgerTransaction({
    required this.type,
    required this.date,
    this.product,
    this.quantity,
    this.rate,
    required this.amount,
    this.method,
    this.note,
    this.locationName,
    this.userName,
  });

  factory LedgerTransaction.fromJson(Map<String, dynamic> j) => LedgerTransaction(
    type:         j['type'] ?? '',
    date:         j['date'] ?? '',
    product:      j['product'],
    quantity:     j['quantity'] != null ? double.parse(j['quantity'].toString()) : null,
    rate:         j['rate'] != null ? double.parse(j['rate'].toString()) : null,
    amount:       double.parse(j['amount'].toString()),
    method:       j['method'],
    note:         j['note'],
    locationName: j['location_name'],
    userName:     j['user_name'],
  );
}

class VendorLedgerController extends GetxController {
  final isLoading        = false.obs;
  final isLoadingDetail  = false.obs;
  final isSaving         = false.obs;
  final errorMessage     = ''.obs;
  final vendors          = <VendorSummary>[].obs;
  final transactions     = <LedgerTransaction>[].obs;
  final detailVendorName = ''.obs;
  final detailPurchases  = 0.0.obs;
  final detailPayments   = 0.0.obs;
  final detailBalance    = 0.0.obs;

  final _fmt = DateFormat('yyyy-MM-dd');

  Future<void> fetchLedger() async {
    isLoading.value    = true;
    errorMessage.value = '';
    final locId = LocationService.instance.locId;
    final locParam = locId != null ? '?location_id=$locId' : '';
    final res = await ApiClient.get('/vendor-ledger$locParam');
    isLoading.value = false;
    if (res.ok) {
      vendors.value = (res.data['vendors'] as List)
          .map((e) => VendorSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      errorMessage.value = res.message ?? 'Failed to load vendor ledger.';
    }
  }

  Future<void> fetchDetail(int vendorId) async {
    isLoadingDetail.value = true;
    errorMessage.value    = '';
    final locId = LocationService.instance.locId;
    final locParam = locId != null ? '&location_id=$locId' : '';
    final res = await ApiClient.get('/vendor-ledger-detail?vendor_id=$vendorId$locParam');
    isLoadingDetail.value = false;
    if (res.ok) {
      detailVendorName.value = res.data['vendor_name'] ?? '';
      detailPurchases.value  = double.parse(res.data['total_purchases'].toString());
      detailPayments.value   = double.parse(res.data['total_payments'].toString());
      detailBalance.value    = double.parse(res.data['balance_due'].toString());
      transactions.value     = (res.data['transactions'] as List)
          .map((e) => LedgerTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      errorMessage.value = res.message ?? 'Failed to load vendor details.';
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
