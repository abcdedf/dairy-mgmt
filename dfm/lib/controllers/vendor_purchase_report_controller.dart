// lib/controllers/vendor_purchase_report_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class VendorPurchaseRow {
  final String date;
  final String? locationName;
  final String vendor;
  final String product;
  final int    quantityKg;
  final double fat;
  final double rate;
  final double amount;

  const VendorPurchaseRow({
    required this.date,
    this.locationName,
    required this.vendor,
    required this.product,
    required this.quantityKg,
    required this.fat,
    required this.rate,
    required this.amount,
  });

  factory VendorPurchaseRow.fromJson(Map<String, dynamic> j) =>
      VendorPurchaseRow(
        date:         j['entry_date'] ?? '',
        locationName: j['location_name']?.toString(),
        vendor:       j['vendor']     ?? '',
        product:      j['product']    ?? '',
        quantityKg:   int.tryParse(j['quantity_kg'].toString())  ?? 0,
        fat:          double.tryParse(j['fat'].toString())        ?? 0,
        rate:         double.tryParse(j['rate'].toString())       ?? 0,
        amount:       double.tryParse(j['amount'].toString())     ?? 0,
      );
}

class VendorPurchaseReportController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final rows         = <VendorPurchaseRow>[].obs;
  final totalQty     = 0.obs;
  final totalAmount  = 0.0.obs;
  final reportLocId  = RxnInt();

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
    fetchReport();
    ever(LocationService.instance.selected, (_) {
      reportLocId.value = null;
      fetchReport();
    });
  }

  Future<void> fetchReport() async {
    isLoading.value    = true;
    errorMessage.value = '';
    final locId = _effectiveLocId();
    final locParam = locId != null ? '?location_id=$locId' : '';
    final res = await ApiClient.get('/vendor-purchase-report$locParam');
    isLoading.value = false;
    if (!res.ok) { errorMessage.value = res.message ?? 'Error fetching report.'; return; }
    rows.value = (res.data['rows'] as List)
        .map((e) => VendorPurchaseRow.fromJson(e as Map<String, dynamic>))
        .toList();
    totalQty.value    = int.tryParse(res.data['total_qty'].toString())    ?? 0;
    totalAmount.value = double.tryParse(res.data['total_amount'].toString()) ?? 0;
  }
}
