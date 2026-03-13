// lib/pages/sales_report_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/sales_report_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

// ════════════════════════════════════════════════════
// DAILY SALES SUMMARY (existing pivot view)
// ════════════════════════════════════════════════════

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
        title: const Text('Daily Product Sales Report',
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
      body: SelectionArea(child: Column(children: [
        // Product dropdown
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Obx(() => DropdownButtonFormField<int>(
            initialValue: ctrl.selectedProductId.value,
            decoration: const InputDecoration(
              labelText: 'Product',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              const DropdownMenuItem(value: 0, child: Text('All Products')),
              ...ctrl.colOrder.map((pid) =>
                  DropdownMenuItem(value: pid, child: Text(ctrl.prodNames[pid] ?? '?'))),
            ],
            onChanged: (v) {
              if (v != null) ctrl.selectedProductId.value = v;
            },
          )),
        ),
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
      ])),
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
    final colOrder = ctrl.visibleCols;
    final names    = ctrl.prodNames;
    final rows     = ctrl.rows;
    final dateFmt  = DateFormat('dd MMM');
    final inrFmt   = NumberFormat('#,##,##0', 'en_IN');

    const dateW  = 72.0;
    const colW   = 90.0;
    const totalW = 90.0;
    final gridW  = dateW + colW * colOrder.length + totalW;

    return Column(children: [
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
              _hdr('Total \u20B9', totalW),
            ]),
          ),
        ),
      ),
      Expanded(
        child: SyncedHorizontalBody(
          hScroll: _hScroll,
          gridWidth: gridW,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      child: Text('\u20B9',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600)),
                    ),
                  ])),
                  const SizedBox(width: totalW),
                ]),
                Divider(height: 1, color: Colors.grey.shade300),
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
                          ...colOrder.map((pid) {
                            final cell = row.products[pid];
                            return SizedBox(
                              height: 44,
                              child: Row(children: [
                                SizedBox(
                                  width: colW / 2,
                                  child: Text(
                                    cell != null
                                        ? '${cell.qtyKg}'
                                        : '\u2014',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cell != null
                                            ? const Color(0xFF2C3E50)
                                            : Colors.grey.shade400),
                                  ),
                                ),
                                SizedBox(
                                  width: colW / 2,
                                  child: Text(
                                    cell != null
                                        ? inrFmt.format(
                                            cell.totalValue)
                                        : '\u2014',
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
                          SizedBox(
                            width: totalW, height: 44,
                            child: Center(
                              child: Text(
                                '\u20B9${inrFmt.format(row.rowTotal)}',
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

// ════════════════════════════════════════════════════
// SALES LEDGER — flat transaction list with customer dropdown
// ════════════════════════════════════════════════════

class SalesLedgerPage extends StatefulWidget {
  const SalesLedgerPage({super.key});
  @override
  State<SalesLedgerPage> createState() => _SalesLedgerPageState();
}

class _SalesLedgerPageState extends State<SalesLedgerPage> {
  late final SalesLedgerController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<SalesLedgerController>(force: true);
    ctrl = Get.put(SalesLedgerController());
  }

  @override
  void dispose() {
    Get.delete<SalesLedgerController>(force: true);
    super.dispose();
  }

  void _exportCsv() {
    if (ctrl.rows.isEmpty) return;
    const headers = ['Date', 'Customer', 'Product', 'Qty', 'Rate', 'Total'];
    final csvRows = ctrl.rows.map((r) => [
      r.date,
      r.customerName,
      r.productName,
      r.quantity.toStringAsFixed(2),
      r.rate.toStringAsFixed(2),
      r.total.toStringAsFixed(2),
    ]).toList();
    exportCsv(fileName: 'sales_ledger.csv', headers: headers, rows: csvRows);
  }

  @override
  Widget build(BuildContext context) {
    final inrFmt  = NumberFormat('#,##,##0.00', 'en_IN');
    final dateFmt = DateFormat('dd MMM');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        title: const Text('Daily Customer Sales Report',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: _exportCsv,
            tooltip: 'Export CSV',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.fetchReport,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SelectionArea(child: Column(children: [
        // Customer dropdown
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Obx(() => DropdownButtonFormField<int>(
            initialValue: ctrl.selectedCustomerId.value,
            decoration: const InputDecoration(
              labelText: 'Customer',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              const DropdownMenuItem(value: 0, child: Text('All Customers')),
              ...ctrl.customers.map((c) =>
                  DropdownMenuItem(value: c.id, child: Text(c.name))),
            ],
            onChanged: (v) {
              if (v != null) {
                ctrl.selectedCustomerId.value = v;
                ctrl.fetchReport();
              }
            },
          )),
        ),
        // Grand total
        Obx(() {
          if (ctrl.rows.isEmpty) return const SizedBox.shrink();
          final grandTotal = ctrl.rows.fold<double>(0, (s, r) => s + r.total);
          return Container(
            width: double.infinity,
            color: Colors.grey.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Text('${ctrl.rows.length} transactions',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const Spacer(),
              Text('Total: \u20B9${inrFmt.format(grandTotal)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kNavy)),
            ]),
          );
        }),
        // Transaction table
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
              message: 'No sales found.',
            );
          }
          return _SalesTable(rows: ctrl.rows, dateFmt: dateFmt, inrFmt: inrFmt);
        })),
      ])),
    );
  }
}

class _SalesTable extends StatefulWidget {
  final List<SalesLedgerRow> rows;
  final DateFormat dateFmt;
  final NumberFormat inrFmt;
  const _SalesTable({required this.rows, required this.dateFmt, required this.inrFmt});

  @override
  State<_SalesTable> createState() => _SalesTableState();
}

class _SalesTableState extends State<_SalesTable> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final dfmt = widget.dateFmt;
    final ifmt = widget.inrFmt;

    const dateW = 68.0;
    const custW = 110.0;
    const prodW = 80.0;
    const rateW = 80.0;
    const qtyW  = 60.0;
    const totW  = 90.0;
    const gridW = dateW + custW + prodW + rateW + qtyW + totW;

    Widget hdr(String t, double w) => SizedBox(
      width: w, height: 40,
      child: Center(child: Text(t,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
    );

    Widget cell(String text, double w, {Color? color, bool bold = false, TextAlign align = TextAlign.center}) => SizedBox(
      width: w, height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.center,
          child: Text(text,
              style: TextStyle(fontSize: 12, color: color ?? const Color(0xFF2C3E50),
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );

    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF6A1B9A),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(width: gridW, child: Row(children: [
            hdr('Date', dateW),
            hdr('Customer', custW),
            hdr('Product', prodW),
            hdr('Rate', rateW),
            hdr('Qty', qtyW),
            hdr('Total', totW),
          ])),
        ),
      ),
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
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    color: isEven ? Colors.white : const Color(0xFFF8F9FA),
                    child: Row(children: [
                      cell(dfmt.format(DateTime.parse(r.date)), dateW, bold: true),
                      cell(r.customerName, custW, align: TextAlign.left),
                      cell(r.productName, prodW),
                      cell(ifmt.format(r.rate), rateW),
                      cell('${r.quantity.toInt()}', qtyW),
                      cell('\u20B9${ifmt.format(r.total)}', totW, bold: true, color: kNavy),
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
