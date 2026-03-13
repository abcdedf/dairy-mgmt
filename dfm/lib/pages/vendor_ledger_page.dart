// lib/pages/vendor_ledger_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/vendor_ledger_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

const _kTeal = Color(0xFF00897B);

class VendorLedgerPage extends StatefulWidget {
  const VendorLedgerPage({super.key});
  @override
  State<VendorLedgerPage> createState() => _VendorLedgerPageState();
}

class _VendorLedgerPageState extends State<VendorLedgerPage> {
  late final VendorLedgerController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<VendorLedgerController>(force: true);
    ctrl = Get.put(VendorLedgerController());
  }

  @override
  void dispose() {
    Get.delete<VendorLedgerController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inrFmt = NumberFormat('#,##,##0.00', 'en_IN');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Ledger'),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportLedgerCsv(ctrl),
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: SelectionArea(child: Obx(() {
        if (ctrl.isLoading.value) return const LoadingCenter();
        if (ctrl.errorMessage.value.isNotEmpty) {
          return EmptyState(
            icon: Icons.error_outline,
            message: ctrl.errorMessage.value,
            buttonLabel: 'Retry',
            onButton: ctrl.fetchLedger,
          );
        }
        if (ctrl.vendors.isEmpty) {
          return const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            message: 'No vendor activity found.',
          );
        }
        return RefreshIndicator(
          onRefresh: ctrl.fetchLedger,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: ctrl.vendors.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final v = ctrl.vendors[i];
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => _VendorDetailPage(vendorId: v.vendorId),
                  )),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(v.vendorName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15))),
                          Icon(Icons.chevron_right,
                              color: Colors.grey.shade400),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          _SummaryChip('Purchases',
                              inrFmt.format(v.totalPurchases),
                              const Color(0xFF1A73E8)),
                          const SizedBox(width: 8),
                          _SummaryChip('Paid',
                              inrFmt.format(v.totalPayments),
                              kGreen),
                          const SizedBox(width: 8),
                          _SummaryChip('Due',
                              inrFmt.format(v.balanceDue),
                              v.balanceDue > 0 ? kRed : kGreen),
                        ]),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      })),
    );
  }
}

void _exportLedgerCsv(VendorLedgerController c) {
  if (c.vendors.isEmpty) return;
  const headers = ['Vendor', 'Total Purchases', 'Total Payments', 'Balance Due'];
  final rows = c.vendors.map((v) => [
    v.vendorName,
    v.totalPurchases.toStringAsFixed(2),
    v.totalPayments.toStringAsFixed(2),
    v.balanceDue.toStringAsFixed(2),
  ]).toList();
  exportCsv(fileName: 'vendor_ledger.csv', headers: headers, rows: rows);
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _SummaryChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────
// DETAIL PAGE — now with vendor dropdown + flat table
// ────────────────────────────────────────────────────

class _VendorDetailPage extends StatelessWidget {
  final int vendorId;
  const _VendorDetailPage({required this.vendorId});

  @override
  Widget build(BuildContext context) {
    final ctrl   = Get.find<VendorLedgerController>();
    final inrFmt = NumberFormat('#,##,##0.00', 'en_IN');
    ctrl.fetchDetail(vendorId);

    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(ctrl.detailVendorName.value.isNotEmpty
            ? ctrl.detailVendorName.value : 'Vendor Detail')),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportDetailCsv(ctrl, inrFmt),
            tooltip: 'Export CSV',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPaymentSheet(context, ctrl),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Record Payment'),
      ),
      body: SelectionArea(child: Obx(() {
        if (ctrl.isLoadingDetail.value) return const LoadingCenter();
        if (ctrl.errorMessage.value.isNotEmpty) {
          return EmptyState(
            icon: Icons.error_outline,
            message: ctrl.errorMessage.value,
            buttonLabel: 'Retry',
            onButton: () => ctrl.fetchDetail(ctrl.selectedVendorId.value),
          );
        }
        return Column(children: [
          // ── Vendor dropdown ──
          if (ctrl.vendorList.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Obx(() => DropdownButtonFormField<int>(
                initialValue: ctrl.selectedVendorId.value,
                decoration: const InputDecoration(
                  labelText: 'Vendor',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('All Vendors')),
                  ...ctrl.vendorList.map((v) =>
                      DropdownMenuItem(value: v.id, child: Text(v.name))),
                ],
                onChanged: (v) {
                  if (v != null) ctrl.fetchDetail(v);
                },
              )),
            ),
          // ── Summary header ──
          Container(
            width: double.infinity,
            color: Colors.grey.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              _SummaryChip('Purchases',
                  inrFmt.format(ctrl.detailPurchases.value),
                  const Color(0xFF1A73E8)),
              const SizedBox(width: 8),
              _SummaryChip('Paid',
                  inrFmt.format(ctrl.detailPayments.value),
                  kGreen),
              const SizedBox(width: 8),
              _SummaryChip('Due',
                  inrFmt.format(ctrl.detailBalance.value),
                  ctrl.detailBalance.value > 0 ? kRed : kGreen),
            ]),
          ),
          // ── Flat transaction table ──
          Expanded(child: _TransactionTable(ctrl: ctrl, inrFmt: inrFmt)),
        ]);
      })),
    );
  }

  void _showPaymentSheet(BuildContext context, VendorLedgerController ctrl) {
    final amountCtrl = TextEditingController();
    final noteCtrl   = TextEditingController();
    final method     = 'Cash'.obs;
    final date       = DateTime.now().obs;
    final methods    = ['Cash', 'Bank Transfer', 'UPI', 'Cheque'];
    final dateFmt    = DateFormat('dd MMM yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Record Payment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (INR)',
                border: OutlineInputBorder(),
                prefixText: '\u20B9 ',
              ),
            ),
            const SizedBox(height: 12),
            Obx(() => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today, size: 20),
              title: Text(dateFmt.format(date.value)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: date.value,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) date.value = picked;
              },
            )),
            Obx(() => DropdownButtonFormField<String>(
              initialValue: method.value,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(),
              ),
              items: methods.map((m) => DropdownMenuItem(
                  value: m, child: Text(m))).toList(),
              onChanged: (v) { if (v != null) method.value = v; },
            )),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
              maxLength: 255,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Obx(() => ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: ctrl.isSaving.value ? null : () async {
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) {
                    ctrl.errorMessage.value = 'Enter a valid amount.';
                    return;
                  }
                  // Use the currently selected vendor for payment
                  final payVendorId = ctrl.selectedVendorId.value;
                  if (payVendorId == 0) {
                    ctrl.errorMessage.value = 'Select a specific vendor for payment.';
                    return;
                  }
                  final ok = await ctrl.savePayment(
                    vendorId: payVendorId,
                    date: date.value,
                    amount: amount,
                    method: method.value,
                    note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  );
                  if (ok) {
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    Get.snackbar('Payment Recorded',
                        'Payment of \u20B9${amountCtrl.text} saved.',
                        snackPosition: SnackPosition.BOTTOM,
                        duration: const Duration(seconds: 2),
                        margin: const EdgeInsets.all(12));
                    ctrl.fetchDetail(ctrl.selectedVendorId.value);
                    ctrl.fetchLedger();
                  }
                },
                child: ctrl.isSaving.value
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Payment', style: TextStyle(fontSize: 15)),
              )),
            ),
          ],
        ),
      ),
    );
  }

  void _exportDetailCsv(VendorLedgerController c, NumberFormat fmt) {
    if (c.transactions.isEmpty) return;
    final showVendor = c.selectedVendorId.value == 0;
    final headers = [
      'Date',
      'Type',
      if (showVendor) 'Vendor',
      'Product',
      'Qty',
      'Rate',
      'Amount',
      'Method',
      'Note',
    ];
    final csvRows = c.transactions.map((tx) => [
      tx.date,
      tx.type,
      if (showVendor) tx.vendorName ?? '',
      tx.product ?? '',
      tx.quantity?.toStringAsFixed(2) ?? '',
      tx.rate?.toStringAsFixed(2) ?? '',
      tx.amount.toStringAsFixed(2),
      tx.method ?? '',
      tx.note ?? '',
    ]).toList();
    exportCsv(fileName: 'vendor_ledger_detail.csv', headers: headers, rows: csvRows);
  }
}

// ── Flat transaction table ──────────────────────────────────

class _TransactionTable extends StatelessWidget {
  final VendorLedgerController ctrl;
  final NumberFormat inrFmt;
  const _TransactionTable({required this.ctrl, required this.inrFmt});

  @override
  Widget build(BuildContext context) {
    final txs = ctrl.transactions;
    if (txs.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'No transactions found.',
      );
    }
    final showVendor = ctrl.selectedVendorId.value == 0;
    final dateFmt = DateFormat('dd MMM');

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: txs.length,
      itemBuilder: (_, i) {
        final tx = txs[i];
        final isPurchase = tx.type == 'purchase';
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          color: isPurchase ? Colors.white : const Color(0xFFF1F8E9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              // Icon
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isPurchase
                      ? const Color(0xFF1A73E8).withValues(alpha: 0.12)
                      : kGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isPurchase ? Icons.shopping_cart_outlined : Icons.payments_outlined,
                  color: isPurchase ? const Color(0xFF1A73E8) : kGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              // Details
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isPurchase)
                    Text(
                      '${showVendor && tx.vendorName != null ? '${tx.vendorName} — ' : ''}'
                      '${tx.product ?? ''} — ${tx.quantity?.toInt() ?? 0} KG @ ${inrFmt.format(tx.rate ?? 0)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    )
                  else
                    Text(
                      '${showVendor && tx.vendorName != null ? '${tx.vendorName} — ' : ''}'
                      'Payment — ${tx.method ?? ''}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '${dateFmt.format(DateTime.parse(tx.date))}'
                    '${tx.locationName != null ? '  •  ${tx.locationName}' : ''}'
                    '${tx.userName != null ? '  •  ${tx.userName}' : ''}'
                    '${tx.note != null && tx.note!.isNotEmpty ? '  •  ${tx.note}' : ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              )),
              // Amount
              Text(
                '${isPurchase ? '' : '- '}${inrFmt.format(tx.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isPurchase ? const Color(0xFF1A73E8) : kGreen,
                  fontSize: 13,
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
