// lib/pages/pouch_pnl_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/pouch_pnl_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class PouchPnlPage extends StatefulWidget {
  const PouchPnlPage({super.key});
  @override
  State<PouchPnlPage> createState() => _PouchPnlPageState();
}

class _PouchPnlPageState extends State<PouchPnlPage> {
  late final PouchPnlController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<PouchPnlController>(force: true);
    ctrl = Get.put(PouchPnlController());
  }

  @override
  void dispose() {
    Get.delete<PouchPnlController>(force: true);
    super.dispose();
  }

  void _exportCsv(PouchPnlController c) {
    if (c.rows.isEmpty) return;
    const headers = ['Date', 'Crates', 'Revenue', 'Cost', 'Profit'];
    final csvRows = c.rows.map((r) => [
      r.entryDate, '${r.totalCrates}',
      r.revenue.toStringAsFixed(2),
      r.cost.toStringAsFixed(2),
      r.profit.toStringAsFixed(2),
    ]).toList();
    exportCsv(fileName: 'pouch_pnl.csv', headers: headers, rows: csvRows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        title: const Text('Pouch P&L',
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
      body: Column(children: [
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
              icon: Icons.local_drink_outlined,
              message: 'No pouch production recorded yet.',
            );
          }
          return _ReportBody(ctrl: ctrl);
        })),
      ]),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final PouchPnlController ctrl;
  const _ReportBody({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM');
    final inrFmt  = NumberFormat('#,##,##0.00', 'en_IN');

    return Column(children: [
      // ── Header ────────────────────────────────────
      Container(
        color: kNavy,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: const Row(children: [
          Expanded(flex: 2, child: Text('Date',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 2, child: Text('Crates',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 2, child: Text('Revenue',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 2, child: Text('Cost',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12))),
          Expanded(flex: 2, child: Text('Profit',
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
          final row  = ctrl.rows[i];
          final even = i.isEven;
          final profitColor = row.profit >= 0 ? kGreen : kRed;
          return Container(
            color: even ? Colors.white : const Color(0xFFF8F9FA),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              Expanded(flex: 2, child: Text(
                dateFmt.format(DateTime.parse(row.entryDate)),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              )),
              Expanded(flex: 2, child: Text(
                '${row.totalCrates}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              )),
              Expanded(flex: 2, child: Text(
                inrFmt.format(row.revenue),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              )),
              Expanded(flex: 2, child: Text(
                inrFmt.format(row.cost),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              )),
              Expanded(flex: 2, child: Text(
                inrFmt.format(row.profit),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: profitColor),
              )),
            ]),
          );
        },
      ))),
      // ── Totals footer ─────────────────────────────
      Obx(() {
        final t = ctrl.totals.value;
        if (t == null) return const SizedBox.shrink();
        final profitColor = t.profit >= 0 ? kGreen : kRed;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
                top: BorderSide(color: Colors.grey.shade300, width: 1.5)),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6, offset: const Offset(0, -2),
            )],
          ),
          child: Row(children: [
            const Expanded(flex: 2, child: Text('Total',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            Expanded(flex: 2, child: Text('${t.totalCrates}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600,
                    fontSize: 13, color: kNavy))),
            Expanded(flex: 2, child: Text('₹${inrFmt.format(t.revenue)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
            Expanded(flex: 2, child: Text('₹${inrFmt.format(t.cost)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
            Expanded(flex: 2, child: Text('₹${inrFmt.format(t.profit)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800,
                    fontSize: 13, color: profitColor))),
          ]),
        );
      }),
    ]);
  }
}
