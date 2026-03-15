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

  void _exportCsv() {
    if (ctrl.rows.isEmpty) return;
    const headers = ['Date', 'Location', 'Vendor', 'Purchases', 'Payments', 'Balance'];
    final csvRows = ctrl.rows.map((r) => [
      r.date,
      r.locationName,
      r.vendorName,
      r.purchases.toStringAsFixed(2),
      r.payments.toStringAsFixed(2),
      r.balance.toStringAsFixed(2),
    ]).toList();
    exportCsv(fileName: 'vendor_ledger.csv', headers: headers, rows: csvRows);
  }

  void _showPaymentSheet(BuildContext context) {
    final amountCtrl = TextEditingController();
    final noteCtrl   = TextEditingController();
    final method     = 'Cash'.obs;
    final date       = DateTime.now().obs;
    final methods    = ['Cash', 'Bank Transfer', 'UPI', 'Cheque'];
    final dateFmt    = DateFormat('dd MMM yyyy');
    final payVendorId = ctrl.selectedVendorId.value.obs;

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
            // Vendor selector
            Obx(() => DropdownButtonFormField<int>(
              value: payVendorId.value > 0 ? payVendorId.value : null,
              decoration: const InputDecoration(
                labelText: 'Vendor',
                border: OutlineInputBorder(),
              ),
              items: ctrl.vendorList.map((v) =>
                  DropdownMenuItem(value: v.id, child: Text(v.name))).toList(),
              onChanged: (v) { if (v != null) payVendorId.value = v; },
            )),
            const SizedBox(height: 12),
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
                  if (payVendorId.value == 0) {
                    ctrl.errorMessage.value = 'Select a vendor for payment.';
                    return;
                  }
                  final ok = await ctrl.savePayment(
                    partyId: payVendorId.value,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Vendor Ledger',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: _exportCsv,
            tooltip: 'Export CSV',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.fetchLedger,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPaymentSheet(context),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Payment'),
      ),
      body: SelectionArea(child: Column(children: [
        // Location dropdown
        ReportLocationDropdown(
          selected: ctrl.reportLocId,
          onChanged: (_) => ctrl.fetchLedger(),
        ),
        // Vendor dropdown
        Obx(() {
          if (ctrl.vendorList.isEmpty) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<int>(
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
                ctrl.selectedVendorId.value = v ?? 0;
                ctrl.fetchLedger();
              },
            ),
          );
        }),
        // Body
        Expanded(child: Obx(() {
          if (ctrl.isLoading.value) return const LoadingCenter();
          if (ctrl.errorMessage.value.isNotEmpty) {
            return EmptyState(
              icon: Icons.error_outline,
              message: ctrl.errorMessage.value,
              buttonLabel: 'Retry',
              onButton: ctrl.fetchLedger,
            );
          }
          if (ctrl.rows.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              message: 'No vendor activity found.',
            );
          }
          return _LedgerGrid(rows: ctrl.rows);
        })),
      ])),
    );
  }
}

// ── Grid ──────────────────────────────────────────────────────

class _LedgerGrid extends StatefulWidget {
  final List<VendorLedgerRow> rows;
  const _LedgerGrid({required this.rows});

  @override
  State<_LedgerGrid> createState() => _LedgerGridState();
}

class _LedgerGridState extends State<_LedgerGrid> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows    = widget.rows;
    final dateFmt = DateFormat('dd MMM');
    final inrFmt  = NumberFormat('#,##,##0', 'en_IN');
    final showLoc = rows.any((r) => r.locationName.isNotEmpty);

    const dateW   = 64.0;
    const locW    = 80.0;
    const vendW   = 120.0;
    const numW    = 100.0;
    final gridW   = dateW + (showLoc ? locW : 0) + vendW + numW * 3;

    Widget hdr(String t, double w) => SizedBox(
      width: w, height: 40,
      child: Center(child: Text(t,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    );

    Widget cell(String text, double w, {Color? color, bool bold = false}) => SizedBox(
      width: w, height: 48,
      child: Center(child: Text(text,
          textAlign: TextAlign.center,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color ?? const Color(0xFF2C3E50),
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
    );

    String fmt(double v) => '${v < 0 ? '-' : ''}${inrFmt.format(v.abs())}';

    return Column(children: [
      // Frozen header
      Container(
        decoration: BoxDecoration(
          color: _kTeal,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(width: gridW, child: Row(children: [
            hdr('Date', dateW),
            if (showLoc) hdr('Location', locW),
            hdr('Vendor', vendW),
            hdr('Purchases', numW),
            hdr('Payments', numW),
            hdr('Balance', numW),
          ])),
        ),
      ),
      // Body
      Expanded(
        child: SyncedHorizontalBody(
          hScroll: _hScroll,
          gridWidth: gridW,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(rows.length, (i) {
                final r = rows[i];
                final isEven = i.isEven;
                final balColor = r.balance > 0 ? kRed : (r.balance < 0 ? kGreen : null);
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    color: isEven ? Colors.white : const Color(0xFFF8F9FA),
                    child: Row(children: [
                      cell(dateFmt.format(DateTime.parse(r.date)), dateW, bold: true),
                      if (showLoc) cell(r.locationName, locW),
                      cell(r.vendorName, vendW),
                      cell(fmt(r.purchases), numW, color: const Color(0xFF1A73E8)),
                      cell(r.payments > 0 ? fmt(r.payments) : '', numW, color: kGreen),
                      cell(fmt(r.balance), numW, bold: true, color: balColor),
                    ]),
                  ),
                  if (i < rows.length - 1)
                    Divider(height: 1, color: Colors.grey.shade200),
                ]);
              }),
            ),
          ),
        ),
      ),
    ]);
  }
}
