// lib/pages/stock_flow_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/stock_flow_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class StockFlowPage extends StatefulWidget {
  const StockFlowPage({super.key});
  @override
  State<StockFlowPage> createState() => _StockFlowPageState();
}

class _StockFlowPageState extends State<StockFlowPage> {
  late final StockFlowController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<StockFlowController>(force: true);
    ctrl = Get.put(StockFlowController());
  }

  @override
  void dispose() {
    Get.delete<StockFlowController>(force: true);
    super.dispose();
  }

  void _exportCsv() {
    if (ctrl.days.isEmpty) return;
    final headers = <String>['Date'];
    for (final p in ctrl.products) {
      headers.addAll(['${p.name} In', '${p.name} Out', '${p.name} Bal']);
    }
    final rows = ctrl.days.map((d) {
      final cells = <String>[d.date];
      for (final p in ctrl.products) {
        final f = d.flows[p.id];
        cells.add('${f?.inQty ?? 0}');
        cells.add('${f?.outQty ?? 0}');
        cells.add('${f?.current ?? 0}');
      }
      return cells;
    }).toList();
    exportCsv(fileName: 'stock_flow.csv', headers: headers, rows: rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Stock Flow',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: _exportCsv,
            tooltip: 'Export CSV',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.fetchStock,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SelectionArea(child: Column(children: [
        ReportLocationDropdown(
          selected: ctrl.reportLocId,
          onChanged: (_) => ctrl.fetchStock(),
        ),
        _Legend(),
        Expanded(child: Obx(() {
          if (ctrl.isLoading.value) return const LoadingCenter();
          if (ctrl.errorMessage.value.isNotEmpty) {
            return EmptyState(
              icon: Icons.error_outline,
              message: ctrl.errorMessage.value,
              buttonLabel: 'Retry',
              onButton: ctrl.fetchStock,
            );
          }
          if (ctrl.days.isEmpty) {
            return const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'No stock flow data found.',
            );
          }
          return _StockFlowGrid(ctrl: ctrl);
        })),
      ])),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Row(children: [
      _legendDot(kGreen, 'In'),
      const SizedBox(width: 12),
      _legendDot(kRed, 'Out'),
      const SizedBox(width: 12),
      _legendDot(kNavy, 'Balance'),
      const Spacer(),
      Text('Values in KG',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
    ]),
  );

  Widget _legendDot(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: c, width: 1))),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ],
  );
}

// ── Grid with frozen header ──────────────────────────────────

class _StockFlowGrid extends StatefulWidget {
  final StockFlowController ctrl;
  const _StockFlowGrid({required this.ctrl});

  @override
  State<_StockFlowGrid> createState() => _StockFlowGridState();
}

class _StockFlowGridState extends State<_StockFlowGrid> {
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.ctrl.products;
    final days     = widget.ctrl.days;
    final dateFmt  = DateFormat('dd MMM');

    const dateW    = 64.0;
    const subColW  = 52.0;  // width for each In/Out/Bal sub-column
    const prodColW = subColW * 3; // total width per product group
    const rowH     = 42.0;
    const headerH  = 54.0;  // taller for two-line header

    final gridW = dateW + prodColW * products.length;

    return Column(children: [
      // ── Frozen header ──
      Container(
        decoration: BoxDecoration(
          color: kNavy,
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: gridW,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Top row: Date + product names spanning 3 columns each
              Row(children: [
                _headerCell('Date', dateW, headerH * 0.5),
                ...products.map((p) =>
                    _headerCell(p.name, prodColW, headerH * 0.5)),
              ]),
              // Sub row: In / Out / Bal under each product
              Row(children: [
                const SizedBox(width: dateW, height: headerH * 0.5),
                ...products.expand((_) => [
                  _subHeader('In',  subColW, kGreen),
                  _subHeader('Out', subColW, kRed),
                  _subHeader('Bal', subColW, Colors.white),
                ]),
              ]),
            ]),
          ),
        ),
      ),

      // ── Scrollable body ──
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          return SyncedHorizontalBody(
            hScroll: _hScroll,
            gridWidth: gridW,
            child: SizedBox(
              height: constraints.maxHeight,
              child: Scrollbar(
                thumbVisibility: true,
                controller: _vScroll,
                child: SingleChildScrollView(
                  controller: _vScroll,
                  scrollDirection: Axis.vertical,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(days.length, (i) {
                      final day = days[i];
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          _dateCell(dateFmt.format(DateTime.parse(day.date)), dateW, rowH),
                          ...products.expand((p) {
                            final f = day.flows[p.id];
                            final inV  = f?.inQty ?? 0;
                            final outV = f?.outQty ?? 0;
                            final cur  = f?.current ?? 0;
                            return [
                              _dataCell(inV > 0 ? '$inV' : '', subColW, rowH,
                                  color: kGreen),
                              _dataCell(outV > 0 ? '$outV' : '', subColW, rowH,
                                  color: kRed),
                              _dataCell('$cur', subColW, rowH,
                                  bold: true,
                                  color: cur < 0 ? kRed : const Color(0xFF2C3E50),
                                  bgColor: cur < 0 ? kRed.withValues(alpha: 0.08) : null),
                            ];
                          }),
                        ]),
                        if (i < days.length - 1)
                          Divider(height: 1, color: Colors.grey.shade200),
                      ]);
                    }),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    ]);
  }

  Widget _headerCell(String text, double w, double h) => Container(
    width: w, height: h,
    alignment: Alignment.center,
    color: kNavy,
    child: Text(text, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
            fontSize: 11),
        maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  Widget _subHeader(String text, double w, Color textColor) => Container(
    width: w, height: 27,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: kNavy.withValues(alpha: 0.85),
      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
    ),
    child: Text(text, style: TextStyle(color: textColor, fontSize: 10,
        fontWeight: FontWeight.w600)),
  );

  Widget _dateCell(String text, double w, double h) => Container(
    width: w, height: h,
    alignment: Alignment.center,
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(text, style: const TextStyle(fontSize: 11,
        fontWeight: FontWeight.w700, color: Color(0xFF2C3E50))),
  );

  Widget _dataCell(String text, double w, double h, {
    Color? color, Color? bgColor, bool bold = false,
  }) => Container(
    width: w, height: h,
    alignment: Alignment.center,
    color: bgColor ?? Colors.white,
    child: Text(text, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11,
            color: color ?? const Color(0xFF2C3E50),
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
  );
}
