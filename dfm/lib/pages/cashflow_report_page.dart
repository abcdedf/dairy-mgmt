// lib/pages/cashflow_report_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/cashflow_report_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class CashflowReportPage extends StatefulWidget {
  const CashflowReportPage({super.key});
  @override
  State<CashflowReportPage> createState() => _CashflowReportPageState();
}

class _CashflowReportPageState extends State<CashflowReportPage> {
  late final CashflowReportController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<CashflowReportController>(force: true);
    ctrl = Get.put(CashflowReportController());
  }

  @override
  void dispose() {
    Get.delete<CashflowReportController>(force: true);
    super.dispose();
  }

  void _exportCsv() {
    if (ctrl.rows.isEmpty) return;
    const headers = ['Date', 'Beginning Cash', 'Sales', 'Purchases', 'Payments', 'End Cash'];
    final csvRows = ctrl.rows.map((r) => [
      r.date,
      r.beginningCash.toStringAsFixed(2),
      r.sales.toStringAsFixed(2),
      r.purchases.toStringAsFixed(2),
      r.payments.toStringAsFixed(2),
      r.endCash.toStringAsFixed(2),
    ]).toList();
    exportCsv(fileName: 'cashflow_report.csv', headers: headers, rows: csvRows);
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM');
    final inrFmt  = NumberFormat('#,##,##0', 'en_IN');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        title: const Text('Cash Flow Report',
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
      body: SelectionArea(child: Obx(() {
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
            icon: Icons.account_balance_outlined,
            message: 'No cash flow data.',
          );
        }
        return _CashflowGrid(rows: ctrl.rows, dateFmt: dateFmt, inrFmt: inrFmt);
      })),
    );
  }
}

class _CashflowGrid extends StatefulWidget {
  final List<CashflowDay> rows;
  final DateFormat dateFmt;
  final NumberFormat inrFmt;
  const _CashflowGrid({required this.rows, required this.dateFmt, required this.inrFmt});

  @override
  State<_CashflowGrid> createState() => _CashflowGridState();
}

class _CashflowGridState extends State<_CashflowGrid> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows   = widget.rows;
    final dfmt   = widget.dateFmt;
    final ifmt   = widget.inrFmt;

    const dateW   = 72.0;
    const colW    = 100.0;
    const gridW   = dateW + colW * 5; // beg, sales, purchases, payments, end

    Widget hdr(String t, double w) => SizedBox(
      width: w, height: 40,
      child: Center(child: Text(t,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    );

    Widget cell(String text, double w, {Color? color, bool bold = false}) => SizedBox(
      width: w, height: 44,
      child: Center(child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: color ?? const Color(0xFF2C3E50),
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
    );

    String fmt(double v) => '${v < 0 ? '-' : ''}${ifmt.format(v.abs())}';

    return Column(children: [
      // Frozen header
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D47A1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(width: gridW, child: Row(children: [
            hdr('Date', dateW),
            hdr('Begin\nCash', colW),
            hdr('Sales', colW),
            hdr('Purchases', colW),
            hdr('Payments', colW),
            hdr('End\nCash', colW),
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
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    color: isEven ? Colors.white : const Color(0xFFF8F9FA),
                    child: Row(children: [
                      cell(dfmt.format(DateTime.parse(r.date)), dateW, bold: true),
                      cell(fmt(r.beginningCash), colW, color: r.beginningCash < 0 ? kRed : null),
                      cell(fmt(r.sales), colW, color: r.sales > 0 ? kGreen : null),
                      cell(fmt(r.purchases), colW, color: r.purchases > 0 ? const Color(0xFFE65100) : null),
                      cell(fmt(r.payments), colW, color: r.payments > 0 ? kNavy : null),
                      cell(fmt(r.endCash), colW, bold: true, color: r.endCash < 0 ? kRed : kGreen),
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
