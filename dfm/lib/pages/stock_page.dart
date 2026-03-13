// lib/pages/stock_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/stock_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  late final StockController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<StockController>(force: true);
    ctrl = Get.put(StockController());
  }

  @override
  void dispose() {
    Get.delete<StockController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportStockCsv(ctrl),
            tooltip: 'Export CSV',
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
            onButton: ctrl.fetchStock,
          );
        }
        if (ctrl.stockDays.isEmpty) {
          return EmptyState(
            icon: Icons.inventory_2_outlined,
            message: 'No stock data found.',
            buttonLabel: 'Refresh',
            onButton: ctrl.fetchStock,
          );
        }
        return Column(children: [
          _Legend(),
          Expanded(child: _StockGrid(ctrl: ctrl)),
        ]);
      })),
    );
  }
}

void _exportStockCsv(StockController c) {
  if (c.stockDays.isEmpty) return;
  final headers = ['Date', ...c.products.map((p) => p.name)];
  final rows = c.stockDays.map((d) => [
    d.date,
    ...c.products.map((p) => '${d.stocks[p.id] ?? 0}'),
  ]).toList();
  exportCsv(fileName: 'stock_report.csv', headers: headers, rows: rows);
}

// ── Legend ────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(children: [
      Container(
        width: 12, height: 12,
        decoration: BoxDecoration(
          color: kRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: kRed),
        ),
      ),
      const SizedBox(width: 6),
      Flexible(child: Text('Negative = oversold vs production',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 12),
      Flexible(child: Text('Values in KG',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      Row(children: [
        Icon(Icons.touch_app_outlined, size: 13, color: Colors.grey.shade400),
        const SizedBox(width: 3),
        Text('Tap to enter production',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      ]),
    ]),
  );
}

// ── Stock grid with frozen header ────────────────────────────
//
// Layout strategy:
//   • One shared horizontal ScrollController drives BOTH the header row
//     and the body rows — they always scroll left/right in sync.
//   • The header sits OUTSIDE the vertical ScrollView so it never scrolls up.
//   • The body uses a vertical SingleChildScrollView for up/down scrolling.

class _StockGrid extends StatefulWidget {
  final StockController ctrl;
  const _StockGrid({required this.ctrl});

  @override
  State<_StockGrid> createState() => _StockGridState();
}

class _StockGridState extends State<_StockGrid> {
  // Shared controller keeps header and body in horizontal sync
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
    final days     = widget.ctrl.stockDays;
    final dateFmt  = DateFormat('dd MMM');

    const colW  = 88.0;
    const dateW = 90.0;
    const rowH  = 42.0;

    // Total grid width — used to size inner containers so both
    // header and body ScrollViews scroll the same distance.
    final gridW = dateW + colW * products.length;

    return Column(
      children: [
        // ── Frozen header ──────────────────────────────────────
        // Driven by _hScroll so it mirrors horizontal body scroll.
        Container(
          decoration: BoxDecoration(
            color: kNavy,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: gridW,
              child: Row(children: [
                _cell('Date',  dateW, rowH, isHeader: true),
                ...products.map(
                  (p) => _cell(p.name, colW, rowH, isHeader: true),
                ),
              ]),
            ),
          ),
        ),

        // ── Scrollable body ────────────────────────────────────
        // Horizontal scroll is the outer layer so its scrollbar
        // stays at the viewport bottom regardless of vertical overflow.
        // Vertical scroll is inside, constrained to the available height.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
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
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(children: [
                                _cell(
                                  dateFmt.format(DateTime.parse(day.date)),
                                  dateW, rowH,
                                  isBold: true,
                                ),
                                ...products.map((p) {
                                  final val   = day.stocks[p.id] ?? 0;
                                  final isNeg = val < 0;
                                  return _cell(
                                    val.toString(), colW, rowH,
                                    textColor: isNeg ? kRed : null,
                                    bgColor: isNeg ? kRed.withValues(alpha: 0.08) : null,
                                  );
                                }),
                              ]),
                              if (i < days.length - 1)
                                Divider(height: 1, color: Colors.grey.shade200),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cell(String text, double width, double height, {
    bool isHeader = false,
    bool isBold   = false,
    Color? textColor,
    Color? bgColor,
  }) {
    return Container(
      width: width, height: height,
      alignment: Alignment.center,
      color: bgColor ?? (isHeader ? kNavy : Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize:   isHeader ? 12 : 13,
          fontWeight: (isHeader || isBold)
              ? FontWeight.w700
              : FontWeight.normal,
          color: isHeader
              ? Colors.white
              : (textColor ?? const Color(0xFF2C3E50)),
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

