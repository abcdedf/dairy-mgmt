// lib/controllers/invoice_controller.dart

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';
import 'challan_controller.dart';

// ── Models ────────────────────────────────────────────────

class InvoiceChallanRef {
  final int id;
  final int challanNumber;
  final String challanDate;
  const InvoiceChallanRef({required this.id, required this.challanNumber, required this.challanDate});
  factory InvoiceChallanRef.fromJson(Map<String, dynamic> j) => InvoiceChallanRef(
    id:            int.parse(j['id'].toString()),
    challanNumber: int.parse(j['challan_number'].toString()),
    challanDate:   j['challan_date']?.toString() ?? '',
  );
}

class InvoiceLine {
  final int productId;
  final String productName;
  final String productUnit;
  final double totalQty;
  final double avgRate;
  final double totalAmount;
  const InvoiceLine({required this.productId, required this.productName,
      required this.productUnit, required this.totalQty,
      required this.avgRate, required this.totalAmount});
  factory InvoiceLine.fromJson(Map<String, dynamic> j) => InvoiceLine(
    productId:   int.parse(j['product_id'].toString()),
    productName: j['product_name']?.toString() ?? '',
    productUnit: j['product_unit']?.toString() ?? '',
    totalQty:    double.tryParse(j['total_qty']?.toString() ?? '') ?? 0,
    avgRate:     double.tryParse(j['avg_rate']?.toString() ?? '') ?? 0,
    totalAmount: double.tryParse(j['total_amount']?.toString() ?? '') ?? 0,
  );
}

class Invoice {
  final int id;
  final int locationId;
  final int partyId;
  final String partyName;
  final int invoiceNumber;
  final String invoiceDate;
  final double subtotal;
  final double tax;
  final double total;
  final String paymentStatus;
  final String? notes;
  final String? billingAddressSnapshot;
  final String? shippingAddressSnapshot;
  final List<InvoiceChallanRef> challans;
  final List<InvoiceLine> lines;
  final String createdAt;

  const Invoice({
    required this.id, required this.locationId, required this.partyId,
    this.partyName = '', required this.invoiceNumber, required this.invoiceDate,
    required this.subtotal, required this.tax, required this.total,
    required this.paymentStatus, this.notes,
    this.billingAddressSnapshot, this.shippingAddressSnapshot,
    required this.challans, required this.lines, this.createdAt = '',
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
    id:            int.parse(j['id'].toString()),
    locationId:    int.parse(j['location_id'].toString()),
    partyId:       int.parse(j['party_id'].toString()),
    partyName:     j['party_name']?.toString() ?? '',
    invoiceNumber: int.parse(j['invoice_number'].toString()),
    invoiceDate:   j['invoice_date']?.toString() ?? '',
    subtotal:      double.tryParse(j['subtotal']?.toString() ?? '') ?? 0,
    tax:           double.tryParse(j['tax']?.toString() ?? '') ?? 0,
    total:         double.tryParse(j['total']?.toString() ?? '') ?? 0,
    paymentStatus: j['payment_status']?.toString() ?? 'unpaid',
    notes:         j['notes']?.toString(),
    billingAddressSnapshot:  j['billing_address_snapshot']?.toString(),
    shippingAddressSnapshot: j['shipping_address_snapshot']?.toString(),
    challans: (j['challans'] as List? ?? [])
        .map((e) => InvoiceChallanRef.fromJson(e as Map<String, dynamic>)).toList(),
    lines: (j['lines'] as List? ?? [])
        .map((e) => InvoiceLine.fromJson(e as Map<String, dynamic>)).toList(),
    createdAt: j['created_at']?.toString() ?? '',
  );

  bool get isPaid => paymentStatus == 'paid';
}

// ── Controller ────────────────────────────────────────────

class InvoiceController extends GetxController {
  final isLoading      = false.obs;
  final isSaving       = false.obs;
  final errorMessage   = ''.obs;
  final invoices       = <Invoice>[].obs;
  final customers      = <ChallanCustomer>[].obs;
  final statusFilter   = 'all'.obs;
  final reportLocId    = RxnInt();

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
    fetchInvoices();
    ever(LocationService.instance.selected, (_) {
      reportLocId.value = null;
      fetchInvoices();
    });
  }

  Future<void> fetchInvoices() async {
    final locId = _effectiveLocId();
    if (locId == null) return;
    isLoading.value    = true;
    errorMessage.value = '';
    try {
      final status = statusFilter.value;
      final res = await ApiClient.get(
          '/v4/invoices?location_id=$locId&payment_status=$status');
      isLoading.value = false;
      if (res.ok) {
        invoices.value = (res.data['invoices'] as List)
            .map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList();
        if (res.data['customers'] != null) {
          customers.value = (res.data['customers'] as List)
              .map((e) => ChallanCustomer.fromJson(e as Map<String, dynamic>)).toList();
        }
      } else {
        errorMessage.value = res.message ?? 'Failed to load invoices.';
      }
    } catch (e, st) {
      isLoading.value = false;
      errorMessage.value = 'Unexpected error loading invoices.';
      if (kDebugMode) debugPrint('[InvoiceController] fetch error: $e\n$st');
    }
  }

  /// Fetch pending challans for a specific customer at this location.
  Future<List<Challan>> fetchPendingChallans(int partyId) async {
    final locId = _effectiveLocId();
    if (locId == null) return [];
    final res = await ApiClient.get(
        '/v4/challans?location_id=$locId&status=pending');
    if (!res.ok) return [];
    return (res.data['challans'] as List)
        .map((e) => Challan.fromJson(e as Map<String, dynamic>))
        .where((ch) => ch.partyId == partyId)
        .toList();
  }

  Future<bool> createInvoice({
    required int partyId,
    required String invoiceDate,
    required List<int> challanIds,
    String notes = '',
  }) async {
    final locId = _effectiveLocId();
    if (locId == null) return false;
    isSaving.value     = true;
    errorMessage.value = '';
    try {
      final res = await ApiClient.post('/v4/invoice', {
        'location_id':  locId,
        'party_id':     partyId,
        'invoice_date': invoiceDate,
        'challan_ids':  challanIds,
        'notes':        notes,
      });
      isSaving.value = false;
      if (res.ok) return true;
      errorMessage.value = res.message ?? 'Failed to create invoice.';
      return false;
    } catch (e, st) {
      isSaving.value = false;
      errorMessage.value = 'Unexpected error creating invoice.';
      if (kDebugMode) debugPrint('[InvoiceController] create error: $e\n$st');
      return false;
    }
  }

  Future<bool> deleteInvoice(int id) async {
    errorMessage.value = '';
    try {
      final res = await ApiClient.delete('/v4/invoice/$id');
      if (res.ok) return true;
      errorMessage.value = res.message ?? 'Failed to delete invoice.';
      return false;
    } catch (e, st) {
      errorMessage.value = 'Unexpected error deleting invoice.';
      if (kDebugMode) debugPrint('[InvoiceController] delete error: $e\n$st');
      return false;
    }
  }

  Future<bool> togglePaid(int id) async {
    errorMessage.value = '';
    try {
      final res = await ApiClient.post('/v4/invoice/$id/pay', {});
      if (res.ok) return true;
      errorMessage.value = res.message ?? 'Failed to update payment status.';
      return false;
    } catch (e, st) {
      errorMessage.value = 'Unexpected error updating payment.';
      if (kDebugMode) debugPrint('[InvoiceController] togglePaid error: $e\n$st');
      return false;
    }
  }
}
