// lib/pages/cash_stock_report_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/cash_stock_report_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class CashStockReportPage extends StatefulWidget {
  const CashStockReportPage({super.key});
  @override
  State<CashStockReportPage> createState() => _CashStockReportPageState();
}

class _CashStockReportPageState extends State<CashStockReportPage> {
  late final CashStockReportController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<CashStockReportController>(force: true);
    ctrl = Get.put(CashStockReportController());
  }

  @override
  void dispose() {
    Get.delete<CashStockReportController>(force: true);
    super.dispose();
  }

  void _exportCsv() {
    if (ctrl.rows.isEmpty) return;
    const headers = [
      'Date', 'Beg Cash', 'Sales', 'Purchases', 'Payments', 'End Cash',
      'Skim Milk', 'Curd', 'Cream', 'Ghee', 'Butter', 'FF Milk', 'SMP+Cul+Pro',
      'Total Stock', 'Cash+Stock',
    ];
    final csvRows = ctrl.rows.map((r) => [
      r.date,
      r.beginningCash.toStringAsFixed(2),
      r.sales.toStringAsFixed(2),
      r.purchases.toStringAsFixed(2),
      r.payments.toStringAsFixed(2),
      r.endCash.toStringAsFixed(2),
      r.skimMilk.toStringAsFixed(2),
      r.curd.toStringAsFixed(2),
      r.cream.toStringAsFixed(2),
      r.ghee.toStringAsFixed(2),
      r.butter.toStringAsFixed(2),
      r.ffMilk.toStringAsFixed(2),
      r.smpCulPro.toStringAsFixed(2),
      r.totalStock.toStringAsFixed(2),
      r.cashPlusStock.toStringAsFixed(2),
    ]).toList();
    exportCsv(fileName: 'cash_stock_report.csv', headers: headers, rows: csvRows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        title: const Text('Cash + Stock Report',
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
        ReportLocationDropdown(
          selected: ctrl.reportLocId,
          onChanged: (_) => ctrl.fetchReport(),
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
              icon: Icons.analytics_outlined,
              message: 'No data available.',
            );
          }
          return _CashStockGrid(rows: ctrl.rows);
        })),
      ])),
    );
  }
}

// ── Grid ──────────────────────────────────────────────────────

class _CashStockGrid extends StatefulWidget {
  final List<CashStockRow> rows;
  const _CashStockGrid({required this.rows});

  @override
  State<_CashStockGrid> createState() => _CashStockGridState();
}

class _CashStockGridState extends State<_CashStockGrid> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows   = widget.rows;
    final dfmt   = DateFormat('dd MMM');
    final ifmt   = NumberFormat('#,##,##0', 'en_IN');

    const dateW  = 64.0;
    const numW   = 86.0;
    const totalW = 96.0;
    // Date + 5 cash cols + 7 stock cols + total stock + cash+stock = 14 data cols
    final gridW  = dateW + numW * 5 + numW * 7 + totalW * 2;

    Widget hdr(String t, double w, {Color? bg}) => Container(
      width: w, height: 44,
      color: bg,
      child: Center(child: Text(t,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10),
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    );

    Widget cell(String text, double w, {Color? color, bool bold = false}) => SizedBox(
      width: w, height: 44,
      child: Center(child: Text(text,
          textAlign: TextAlign.center,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: color ?? const Color(0xFF2C3E50),
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
    );

    String fmt(double v) => '${v < 0 ? '-' : ''}${ifmt.format(v.abs())}';

    const cashBg  = Color(0xFF0D47A1);
    const stockBg = Color(0xFF1B5E20);
    const totalBg = Color(0xFF4A148C);

    return Column(children: [
      // Frozen header
      Container(
        decoration: BoxDecoration(
          color: cashBg,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(width: gridW, child: Row(children: [
            hdr('Date', dateW),
            hdr('Beg Cash', numW, bg: cashBg),
            hdr('Sales', numW, bg: cashBg),
            hdr('Purchases', numW, bg: cashBg),
            hdr('Payments', numW, bg: cashBg),
            hdr('End Cash', numW, bg: cashBg),
            hdr('Skim\nMilk', numW, bg: stockBg),
            hdr('Curd', numW, bg: stockBg),
            hdr('Cream', numW, bg: stockBg),
            hdr('Ghee', numW, bg: stockBg),
            hdr('Butter', numW, bg: stockBg),
            hdr('FF Milk', numW, bg: stockBg),
            hdr('SMP+\nCul+Pro', numW, bg: stockBg),
            hdr('Total\nStock', totalW, bg: totalBg),
            hdr('Cash+\nStock', totalW, bg: totalBg),
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
                final bg = isEven ? Colors.white : const Color(0xFFF8F9FA);
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    color: bg,
                    child: Row(children: [
                      cell(dfmt.format(DateTime.parse(r.date)), dateW, bold: true),
                      cell(fmt(r.beginningCash), numW),
                      cell(fmt(r.sales), numW, color: kGreen),
                      cell(fmt(r.purchases), numW, color: const Color(0xFFE65100)),
                      cell(fmt(r.payments), numW, color: kRed),
                      cell(fmt(r.endCash), numW, bold: true, color: kNavy),
                      cell(fmt(r.skimMilk), numW),
                      cell(fmt(r.curd), numW),
                      cell(fmt(r.cream), numW),
                      cell(fmt(r.ghee), numW),
                      cell(fmt(r.butter), numW),
                      cell(fmt(r.ffMilk), numW),
                      cell(fmt(r.smpCulPro), numW),
                      cell(fmt(r.totalStock), totalW, bold: true, color: const Color(0xFF1B5E20)),
                      cell(fmt(r.cashPlusStock), totalW, bold: true,
                          color: r.cashPlusStock >= 0 ? const Color(0xFF4A148C) : kRed),
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
