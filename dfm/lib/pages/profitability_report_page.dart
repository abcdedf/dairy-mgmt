// lib/pages/profitability_report_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/profitability_report_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class ProfitabilityReportPage extends StatefulWidget {
  const ProfitabilityReportPage({super.key});
  @override
  State<ProfitabilityReportPage> createState() => _ProfitabilityReportPageState();
}

class _ProfitabilityReportPageState extends State<ProfitabilityReportPage> {
  late final ProfitabilityReportController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<ProfitabilityReportController>(force: true);
    ctrl = Get.put(ProfitabilityReportController());
  }

  @override
  void dispose() {
    Get.delete<ProfitabilityReportController>(force: true);
    super.dispose();
  }

  void _exportCsv() {
    if (ctrl.rows.isEmpty) return;
    const headers = ['Date', 'Location', 'Flow', 'Inputs', 'Outputs', 'Cost', 'Value', 'Profit', 'Profit %'];
    final csvRows = ctrl.rows.map((r) => [
      r.date,
      r.locationName ?? '',
      r.flowLabel,
      r.inputs,
      r.outputs,
      r.cost.toStringAsFixed(2),
      r.value.toStringAsFixed(2),
      r.profit.toStringAsFixed(2),
      r.profitPct.toStringAsFixed(1),
    ]).toList();
    exportCsv(fileName: 'profitability_report.csv', headers: headers, rows: csvRows);
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
        title: const Text('Profitability Report',
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
        // Location dropdown
        ReportLocationDropdown(
          selected: ctrl.reportLocId,
          onChanged: (_) => ctrl.fetchReport(),
        ),
        // Flow dropdown
        Obx(() {
          if (ctrl.flows.isEmpty) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              initialValue: ctrl.selectedFlow.value,
              decoration: const InputDecoration(
                labelText: 'Flow',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('All Flows')),
                ...ctrl.flows.map((f) =>
                    DropdownMenuItem(value: f.key, child: Text(f.label))),
              ],
              onChanged: (v) {
                ctrl.selectedFlow.value = v ?? '';
                ctrl.fetchReport();
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
              onButton: ctrl.fetchReport,
            );
          }
          if (ctrl.rows.isEmpty) {
            return const EmptyState(
              icon: Icons.analytics_outlined,
              message: 'No profitability data.',
            );
          }
          return _ProfitGrid(rows: ctrl.rows, dateFmt: dateFmt, inrFmt: inrFmt);
        })),
      ])),
    );
  }
}

class _ProfitGrid extends StatefulWidget {
  final List<ProfitRow> rows;
  final DateFormat dateFmt;
  final NumberFormat inrFmt;
  const _ProfitGrid({required this.rows, required this.dateFmt, required this.inrFmt});

  @override
  State<_ProfitGrid> createState() => _ProfitGridState();
}

class _ProfitGridState extends State<_ProfitGrid> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows    = widget.rows;
    final dfmt    = widget.dateFmt;
    final ifmt    = widget.inrFmt;
    final showLoc = rows.any((r) => r.locationName != null && r.locationName!.isNotEmpty);

    const dateW   = 64.0;
    const locW    = 80.0;
    const flowW   = 120.0;
    const descW   = 140.0;
    const numW    = 90.0;
    const pctW    = 60.0;
    final gridW   = dateW + (showLoc ? locW : 0) + flowW + descW * 2 + numW * 3 + pctW;

    Widget hdr(String t, double w) => SizedBox(
      width: w, height: 40,
      child: Center(child: Text(t,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    );

    Widget cell(String text, double w, {Color? color, bool bold = false, int maxLines = 2}) => SizedBox(
      width: w, height: 52,
      child: Center(child: Text(text,
          textAlign: TextAlign.center,
          maxLines: maxLines, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color ?? const Color(0xFF2C3E50),
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
            if (showLoc) hdr('Location', locW),
            hdr('Flow', flowW),
            hdr('Inputs', descW),
            hdr('Outputs', descW),
            hdr('Cost', numW),
            hdr('Value', numW),
            hdr('Profit', numW),
            hdr('%', pctW),
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
                final profitColor = r.profit > 0 ? kGreen : (r.profit < 0 ? kRed : null);
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    color: isEven ? Colors.white : const Color(0xFFF8F9FA),
                    child: Row(children: [
                      cell(dfmt.format(DateTime.parse(r.date)), dateW, bold: true),
                      if (showLoc) cell(r.locationName ?? '', locW),
                      cell(r.flowLabel, flowW),
                      cell(r.inputs, descW),
                      cell(r.outputs, descW),
                      cell(fmt(r.cost), numW, color: const Color(0xFFE65100)),
                      cell(fmt(r.value), numW, color: kNavy),
                      cell(fmt(r.profit), numW, bold: true, color: profitColor),
                      cell('${r.profitPct.toStringAsFixed(1)}%', pctW, bold: true, color: profitColor),
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
