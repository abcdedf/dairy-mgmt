// lib/pages/stock_valuation_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/stock_valuation_controller.dart';
import '../core/csv_export.dart';
import 'shared_widgets.dart';

class StockValuationPage extends StatelessWidget {
  const StockValuationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl   = Get.put(StockValuationController());
    final inrFmt = NumberFormat('#,##,##0.00', 'en_IN');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Valuation'),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportValuationCsv(ctrl),
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: Obx(() {
        if (ctrl.isLoading.value) return const LoadingCenter();
        if (ctrl.errorMessage.value.isNotEmpty) {
          return EmptyState(
            icon: Icons.error_outline,
            message: ctrl.errorMessage.value,
            buttonLabel: 'Retry',
            onButton: ctrl.fetchValuation,
          );
        }
        return Column(children: [
          // ── Action bar: edit rates + refresh ────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(children: [
              const Spacer(),
              Obx(() => TextButton.icon(
                icon: Icon(
                  ctrl.showRateEditor.value
                      ? Icons.close : Icons.edit_outlined,
                  size: 18, color: kNavy),
                label: Obx(() => Text(
                  ctrl.showRateEditor.value
                      ? 'Close' : 'Edit Rates',
                  style: const TextStyle(
                      color: kNavy, fontSize: 13))),
                onPressed: () =>
                    ctrl.showRateEditor.value = !ctrl.showRateEditor.value,
              )),
              IconButton(
                icon: const Icon(Icons.refresh, color: kNavy),
                onPressed: ctrl.fetchValuation,
                tooltip: 'Refresh',
              ),
            ]),
          ),
          Obx(() => ctrl.showRateEditor.value
              ? _RateEditorPanel(ctrl: ctrl)
              : const SizedBox.shrink()),
          Obx(() {
            if (ctrl.successMessage.value.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                child: FeedbackBanner(
                    ctrl.successMessage.value, isError: false),
              );
            }
            return const SizedBox.shrink();
          }),
          Expanded(
            child: ctrl.stockDays.isEmpty
                ? const EmptyState(
                    icon: Icons.bar_chart_outlined,
                    message: 'No valuation data found.')
                : _ValuationGrid(ctrl: ctrl, inrFmt: inrFmt),
          ),
        ]);
      }),
    );
  }
}

void _exportValuationCsv(StockValuationController c) {
  if (c.stockDays.isEmpty) return;
  final headers = [
    'Date',
    ...c.products.expand((p) => ['${p.name} KG', '${p.name} Value']),
    'Total Value',
  ];
  final rows = c.stockDays.map((d) => [
    d.date,
    ...c.products.expand((p) => [
      '${d.stocks[p.id] ?? 0}',
      (d.values[p.id] ?? 0.0).toStringAsFixed(2),
    ]),
    d.totalValue.toStringAsFixed(2),
  ]).toList();
  exportCsv(fileName: 'stock_valuation.csv', headers: headers, rows: rows);
}

// ── Rate editor panel ─────────────────────────────────────────

class _RateEditorPanel extends StatelessWidget {
  final StockValuationController ctrl;
  const _RateEditorPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: DCard(
      child: Form(
        key: ctrl.ratesFormKey,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const SectionLabel('Estimated Rates (₹ per KG)',
              color: kNavy),
          const SizedBox(height: 12),
          ...ctrl.estimatedRates.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                flex: 2,
                child: Text(r.productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500)),
              ),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: ctrl.rateCtrlMap[r.productId],
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'))
                  ],
                  decoration: fieldDec('Rate', suffix: '₹/KG'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ]),
          )),
          const SizedBox(height: 4),
          Obx(() => ElevatedButton.icon(
            onPressed:
                ctrl.isSavingRates.value ? null : ctrl.saveRates,
            icon: ctrl.isSavingRates.value
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(ctrl.isSavingRates.value
                ? 'Saving…' : 'Save Rates'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kNavy,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          )),
        ]),
      ),
    ),
  );
}

// ── Valuation grid with frozen header ────────────────────────
//
// Same pattern as stock_page: one shared _hScroll drives the frozen
// header; _bodyHScroll drives the rows; listeners keep them in sync.

class _ValuationGrid extends StatefulWidget {
  final StockValuationController ctrl;
  final NumberFormat inrFmt;
  const _ValuationGrid({required this.ctrl, required this.inrFmt});

  @override
  State<_ValuationGrid> createState() => _ValuationGridState();
}

class _ValuationGridState extends State<_ValuationGrid> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.ctrl.products;
    final days     = widget.ctrl.stockDays;
    final dateFmt  = DateFormat('dd MMM');
    const dateW    = 80.0;
    const colW     = 100.0;
    const totW     = 110.0;
    const rowH     = 46.0;
    final gridW    = dateW + colW * products.length + totW;

    return Column(children: [
      // ── Frozen header ────────────────────────────────────
      Container(
        decoration: BoxDecoration(
          color: kNavy,
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )],
        ),
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: gridW,
            child: Row(children: [
              _hdr('Date', dateW, rowH),
              ...products.map((p) => _hdr(p.name, colW, rowH)),
              _hdr('Total ₹', totW, rowH),
            ]),
          ),
        ),
      ),

      // ── Scrollable body ───────────────────────────────────
      Expanded(
        child: SyncedHorizontalBody(
          hScroll: _hScroll,
          gridWidth: gridW,
          child: SingleChildScrollView(
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
                        dateW, rowH, bold: true,
                      ),
                      ...products.map((p) {
                        final qty = day.stocks[p.id] ?? 0;
                        final val = day.values[p.id] ?? 0.0;
                        final neg = qty < 0;
                        return Container(
                          width: colW, height: rowH,
                          alignment: Alignment.center,
                          color: neg
                              ? kRed.withValues(alpha: 0.07) : null,
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text('$qty KG',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: neg
                                          ? kRed
                                          : Colors.grey.shade600)),
                              Text(
                                '₹${widget.inrFmt.format(val)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: neg
                                        ? kRed
                                        : const Color(0xFF1E8449)),
                              ),
                            ],
                          ),
                        );
                      }),
                      _cell(
                        '₹${widget.inrFmt.format(day.totalValue)}',
                        totW, rowH,
                        bold: true, color: kNavy,
                      ),
                    ]),
                    if (i < days.length - 1)
                      Divider(
                          height: 1,
                          color: Colors.grey.shade200),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _hdr(String t, double w, double h) => Container(
    width: w, height: h,
    alignment: Alignment.center,
    color: kNavy,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(t,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis),
  );

  Widget _cell(String t, double w, double h,
      {bool bold = false, Color? color}) =>
      Container(
        width: w, height: h,
        alignment: Alignment.center,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.normal,
                color: color ?? const Color(0xFF2C3E50)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      );
}
