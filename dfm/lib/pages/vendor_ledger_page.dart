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
      body: Obx(() {
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
      }),
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
// DETAIL PAGE
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPaymentSheet(context, ctrl),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Record Payment'),
      ),
      body: Obx(() {
        if (ctrl.isLoadingDetail.value) return const LoadingCenter();
        if (ctrl.errorMessage.value.isNotEmpty) {
          return EmptyState(
            icon: Icons.error_outline,
            message: ctrl.errorMessage.value,
            buttonLabel: 'Retry',
            onButton: () => ctrl.fetchDetail(vendorId),
          );
        }
        return Column(children: [
          // Summary header
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
          // Transaction list
          Expanded(
            child: ctrl.transactions.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'No transactions found.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: ctrl.transactions.length,
                    itemBuilder: (context, i) {
                      final tx = ctrl.transactions[i];
                      if (tx.type == 'payment') return _PaymentTile(tx, inrFmt);
                      return _PurchaseTile(tx, inrFmt);
                    },
                  ),
          ),
        ]);
      }),
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
            // Amount
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
            // Date picker
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
            // Method dropdown
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
            // Note
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
              maxLength: 255,
            ),
            const SizedBox(height: 12),
            // Save button
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
                  final ok = await ctrl.savePayment(
                    vendorId: vendorId,
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
                    ctrl.fetchDetail(vendorId);
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
}

class _PurchaseTile extends StatelessWidget {
  final LedgerTransaction tx;
  final NumberFormat fmt;
  const _PurchaseTile(this.tx, this.fmt);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.shopping_cart_outlined,
              color: Color(0xFF1A73E8), size: 20),
        ),
        title: Text('${tx.product ?? ''} — ${tx.quantity?.toInt() ?? 0} KG @ ${fmt.format(tx.rate ?? 0)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('${tx.date}  •  ${tx.locationName ?? ''}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        trailing: Text(fmt.format(tx.amount),
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A73E8), fontSize: 13)),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final LedgerTransaction tx;
  final NumberFormat fmt;
  const _PaymentTile(this.tx, this.fmt);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: const Color(0xFFF1F8E9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: kGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.payments_outlined, color: kGreen, size: 20),
        ),
        title: Text('Payment — ${tx.method ?? ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${tx.date}  •  ${tx.userName ?? ''}'
            '${tx.note != null && tx.note!.isNotEmpty ? '  •  ${tx.note}' : ''}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        trailing: Text('- ${fmt.format(tx.amount)}',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: kGreen, fontSize: 13)),
      ),
    );
  }
}
