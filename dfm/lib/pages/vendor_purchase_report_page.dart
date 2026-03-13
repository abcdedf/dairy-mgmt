// lib/pages/vendor_purchase_report_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/vendor_purchase_report_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class VendorPurchaseReportPage extends StatefulWidget {
  const VendorPurchaseReportPage({super.key});
  @override
  State<VendorPurchaseReportPage> createState() => _VendorPurchaseReportPageState();
}

class _VendorPurchaseReportPageState extends State<VendorPurchaseReportPage> {
  late final VendorPurchaseReportController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<VendorPurchaseReportController>(force: true);
    ctrl = Get.put(VendorPurchaseReportController());
  }

  @override
  void dispose() {
    Get.delete<VendorPurchaseReportController>(force: true);
    super.dispose();
  }

  void _exportCsv(VendorPurchaseReportController c) {
    if (c.rows.isEmpty) return;
    const headers = ['Date', 'Vendor', 'Product', 'Qty KG', 'Fat', 'Rate', 'Amount'];
    final csvRows = c.rows.map((r) => [
      r.date, r.vendor, r.product,
      '${r.quantityKg}', r.fat.toStringAsFixed(1),
      r.rate.toStringAsFixed(2), r.amount.toStringAsFixed(2),
    ]).toList();
    exportCsv(fileName: 'vendor_purchase_report.csv', headers: headers, rows: csvRows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        title: const Text('Vendor Purchase Report',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportCsv(ctrl),
            tooltip: 'Export CSV',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.fetchReport,
          ),
        ],
      ),
      body: SelectionArea(child: Column(children: [
        // ── Body ──────────────────────────────────────
        Expanded(child: Obx(() {
          if (ctrl.isLoading.value) return const LoadingCenter();
          if (ctrl.errorMessage.value.isNotEmpty) {
            return EmptyState(
              icon: Icons.error_outline,
              message: ctrl.errorMessage.value,
              buttonLabel: 'Retry',
              onButton: ctrl.fetchReport,
            );
          }
          if (ctrl.rows.isEmpty) {
            return const EmptyState(
              icon: Icons.local_shipping_outlined,
              message: 'No purchases in the last 30 days.',
            );
          }
          return _ReportBody(ctrl: ctrl);
        })),
      ])),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final VendorPurchaseReportController ctrl;
  const _ReportBody({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM');
    final inrFmt  = NumberFormat('#,##,##0.00', 'en_IN');

    return Column(children: [
      // ── Header ────────────────────────────────────
      Container(
        color: kNavy,
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        child: const Row(children: [
          Expanded(flex: 2, child: Text('Date',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 3, child: Text('Vendor',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 2, child: Text('Product',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 2, child: Text('Qty KG',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 2, child: Text('Rate',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 2, child: Text('Amount',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
        ]),
      ),
      // ── Rows ──────────────────────────────────────
      Expanded(child: Obx(() => ListView.separated(
        itemCount: ctrl.rows.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (_, i) {
          final row   = ctrl.rows[i];
          final even  = i.isEven;
          return Container(
            color: even ? Colors.white : const Color(0xFFF8F9FA),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 9),
            child: Row(children: [
              Expanded(flex: 2, child: Text(
                dateFmt.format(DateTime.parse(row.date)),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              )),
              Expanded(flex: 3, child: Text(
                row.vendor,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              )),
              Expanded(flex: 2, child: Text(
                row.product,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700),
              )),
              Expanded(flex: 2, child: Text(
                '${row.quantityKg}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              )),
              Expanded(flex: 2, child: Text(
                '₹${row.rate.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              )),
              Expanded(flex: 2, child: Text(
                inrFmt.format(row.amount),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: kGreen),
              )),
            ]),
          );
        },
      ))),
      // ── Totals footer ─────────────────────────────
      Obx(() => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
              top: BorderSide(
                  color: Colors.grey.shade300, width: 1.5)),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6, offset: const Offset(0, -2),
          )],
        ),
        child: Row(children: [
          const Expanded(child: Text('Total',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14))),
          Text('${ctrl.totalQty.value} KG',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13, color: kNavy)),
          const SizedBox(width: 16),
          Text('₹${NumberFormat('#,##,##0.00', 'en_IN').format(ctrl.totalAmount.value)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14, color: kNavy)),
        ]),
      )),
    ]);
  }
}
