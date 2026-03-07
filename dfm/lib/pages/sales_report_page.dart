// lib/pages/sales_report_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/sales_report_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class DailySalesReportPage extends StatefulWidget {
  const DailySalesReportPage({super.key});
  @override
  State<DailySalesReportPage> createState() => _DailySalesReportPageState();
}

class _DailySalesReportPageState extends State<DailySalesReportPage> {
  late final SalesReportController ctrl;

  @override
  void initState() {
    super.initState();
    // Always create a fresh instance — delete any stale one first
    Get.delete<SalesReportController>(force: true);
    ctrl = Get.put(SalesReportController());
  }

  @override
  void dispose() {
    Get.delete<SalesReportController>(force: true);
    super.dispose();
  }

  void _exportCsv(SalesReportController c) {
    if (c.rows.isEmpty) return;
    final headers = [
      'Date',
      ...c.colOrder.map((pid) => '${c.prodNames[pid] ?? "?"} KG'),
      ...c.colOrder.map((pid) => '${c.prodNames[pid] ?? "?"} Value'),
      'Total',
    ];
    final csvRows = c.rows.map((r) => [
      r.date,
      ...c.colOrder.map((pid) => '${r.products[pid]?.qtyKg ?? 0}'),
      ...c.colOrder.map((pid) => (r.products[pid]?.totalValue ?? 0).toStringAsFixed(2)),
      r.rowTotal.toStringAsFixed(2),
    ]).toList();
    exportCsv(fileName: 'sales_report.csv', headers: headers, rows: csvRows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        title: const Text('Daily Sales Summary',
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
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(children: [
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
              icon: Icons.receipt_long_outlined,
              message: 'No sales in the last 30 days.',
            );
          }
          return _ReportGrid(ctrl: ctrl);
        })),
      ]),
    );
  }
}

// ── Report grid with frozen header ────────────────────────────

class _ReportGrid extends StatefulWidget {
  final SalesReportController ctrl;
  const _ReportGrid({required this.ctrl});
  @override
  State<_ReportGrid> createState() => _ReportGridState();
}

class _ReportGridState extends State<_ReportGrid> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl     = widget.ctrl;
    final colOrder = ctrl.colOrder;
    final names    = ctrl.prodNames;
    final rows     = ctrl.rows;
    final dateFmt  = DateFormat('dd MMM');
    final inrFmt   = NumberFormat('#,##,##0', 'en_IN');

    const dateW  = 72.0;
    const colW   = 90.0;  // qty + value stacked
    const totalW = 90.0;
    final gridW  = dateW + colW * colOrder.length + totalW;

    return Column(children: [
      // ── Frozen header ──────────────────────────────
      Container(
        decoration: BoxDecoration(
          color: kNavy,
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4, offset: const Offset(0, 2),
          )],
        ),
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: gridW,
            child: Row(children: [
              _hdr('Date', dateW),
              ...colOrder.map((pid) =>
                  _hdr(names[pid] ?? '?', colW)),
              _hdr('Total ₹', totalW),
            ]),
          ),
        ),
      ),
      // ── Body (with sub-header inside) ─────────────
      Expanded(
        child: SyncedHorizontalBody(
          hScroll: _hScroll,
          gridWidth: gridW,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sub-header: KG / ₹ labels (scrolls with body)
                Row(children: [
                  const SizedBox(width: dateW),
                  ...colOrder.map((_) => Row(children: [
                    SizedBox(
                      width: colW / 2,
                      child: Text('KG',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(
                      width: colW / 2,
                      child: Text('₹',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600)),
                    ),
                  ])),
                  const SizedBox(width: totalW),
                ]),
                Divider(height: 1, color: Colors.grey.shade300),
                // Data rows
                ...List.generate(rows.length, (i) {
                  final row = rows[i];
                  final isEven = i.isEven;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        color: isEven ? Colors.white
                            : const Color(0xFFF8F9FA),
                        child: Row(children: [
                          // Date cell
                          SizedBox(
                            width: dateW, height: 44,
                            child: Center(
                              child: Text(
                                dateFmt.format(
                                    DateTime.parse(row.date)),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          // Product cells
                          ...colOrder.map((pid) {
                            final cell = row.products[pid];
                            return SizedBox(
                              height: 44,
                              child: Row(children: [
                                // KG
                                SizedBox(
                                  width: colW / 2,
                                  child: Text(
                                    cell != null
                                        ? '${cell.qtyKg}'
                                        : '—',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cell != null
                                            ? const Color(0xFF2C3E50)
                                            : Colors.grey.shade400),
                                  ),
                                ),
                                // ₹ value
                                SizedBox(
                                  width: colW / 2,
                                  child: Text(
                                    cell != null
                                        ? inrFmt.format(
                                            cell.totalValue)
                                        : '—',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cell != null
                                            ? kGreen
                                            : Colors.grey.shade400),
                                  ),
                                ),
                              ]),
                            );
                          }),
                          // Row total
                          SizedBox(
                            width: totalW, height: 44,
                            child: Center(
                              child: Text(
                                '₹${inrFmt.format(row.rowTotal)}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kNavy),
                              ),
                            ),
                          ),
                        ]),
                      ),
                      if (i < rows.length - 1)
                        Divider(
                            height: 1,
                            color: Colors.grey.shade200),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    ]);
  }



  Widget _hdr(String t, double w) => SizedBox(
    width: w, height: 40,
    child: Center(
      child: Text(t,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
    ),
  );
}
