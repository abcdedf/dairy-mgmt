// lib/pages/transactions_page.dart
//
// Two pages: SalesTransactionsPage and ProductionTransactionsPage.
// Each transaction is a single row. On narrow screens (mobile) fields wrap.
// On wide screens (web) rows don't wrap and scroll horizontally.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/transactions_controller.dart';
import 'shared_widgets.dart';

const double _kWrapBreakpoint = 600;

// ════════════════════════════════════════════════════════════
// SALES TRANSACTIONS PAGE
// ════════════════════════════════════════════════════════════

class SalesTransactionsPage extends StatefulWidget {
  const SalesTransactionsPage({super.key});
  @override
  State<SalesTransactionsPage> createState() =>
      _SalesTransactionsPageState();
}

class _SalesTransactionsPageState extends State<SalesTransactionsPage> {
  late final SalesTransactionsController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<SalesTransactionsController>(force: true);
    ctrl = Get.put(SalesTransactionsController());
  }

  @override
  void dispose() {
    Get.delete<SalesTransactionsController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inrFmt = NumberFormat('#,##,##0.00', 'en_IN');
    final dateFmt = DateFormat('dd MMM');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        title: Obx(() => Text(
          'Sales — last ${ctrl.days.value} days',
          style: const TextStyle(fontWeight: FontWeight.w600),
        )),
        actions: [
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
              icon: Icons.receipt_long_outlined,
              message: 'No sales transactions found.',
            );
          }

          return LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth >= _kWrapBreakpoint;

            // Column definitions: label, flex, builder
            Widget headerRow() => Container(
            color: kNavy,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: const [
              SizedBox(width: 70, child: Text('Date', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
              Expanded(flex: 2, child: Text('Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
              Expanded(flex: 3, child: Text('Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
              Expanded(flex: 3, child: Text('Customer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
              SizedBox(width: 60, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
              SizedBox(width: 70, child: Text('Rate', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
              SizedBox(width: 80, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
              SizedBox(width: 60, child: Text('User', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
            ]),
          );

          Widget dataRow(SaleTx tx, bool even) {
            final parsed = DateTime.tryParse(tx.date);
            final dateStr = parsed != null ? dateFmt.format(parsed) : tx.date;

            if (isWide) {
              return Container(
                color: even ? Colors.white : const Color(0xFFF8F9FA),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  SizedBox(width: 70, child: Text(dateStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  Expanded(flex: 2, child: Text(tx.locationName, style: const TextStyle(fontSize: 12))),
                  Expanded(flex: 3, child: Text(tx.productName, style: const TextStyle(fontSize: 12))),
                  Expanded(flex: 3, child: Text(tx.customerName, style: const TextStyle(fontSize: 12))),
                  SizedBox(width: 60, child: Text('${tx.quantityKg}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                  SizedBox(width: 70, child: Text('₹${tx.rate.toStringAsFixed(2)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                  SizedBox(width: 80, child: Text('₹${inrFmt.format(tx.total)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kGreen))),
                  SizedBox(width: 60, child: Text(tx.userName, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                ]),
              );
            }

            // Mobile: wrap layout
            return Container(
              color: even ? Colors.white : const Color(0xFFF8F9FA),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _Tag(dateStr, bold: true),
                  if (tx.locationName.isNotEmpty) _Tag(tx.locationName, dim: true),
                  _Tag(tx.productName, bold: true),
                  _Tag(tx.customerName),
                  _Tag('${tx.quantityKg} KG'),
                  _Tag('₹${tx.rate.toStringAsFixed(2)}/KG'),
                  _Tag('₹${inrFmt.format(tx.total)}', color: kGreen, bold: true),
                  _Tag(tx.userName, dim: true),
                ],
              ),
            );
          }

          return Column(children: [
            if (isWide) headerRow(),
            Expanded(child: ListView.separated(
              itemCount: ctrl.rows.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, i) => dataRow(ctrl.rows[i], i.isEven),
            )),
          ]);
        });
      })),
      ])),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PRODUCTION TRANSACTIONS PAGE
// ════════════════════════════════════════════════════════════

class ProductionTransactionsPage extends StatefulWidget {
  const ProductionTransactionsPage({super.key});
  @override
  State<ProductionTransactionsPage> createState() =>
      _ProductionTransactionsPageState();
}

class _ProductionTransactionsPageState
    extends State<ProductionTransactionsPage> {
  late final ProductionTransactionsController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<ProductionTransactionsController>(force: true);
    ctrl = Get.put(ProductionTransactionsController());
  }

  @override
  void dispose() {
    Get.delete<ProductionTransactionsController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        title: Obx(() => Text(
          'Production — last ${ctrl.days.value} days',
          style: const TextStyle(fontWeight: FontWeight.w600),
        )),
        actions: [
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
              icon: Icons.factory_outlined,
              message: 'No production transactions found.',
            );
          }

          return LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth >= _kWrapBreakpoint;

            Widget headerRow() => Container(
              color: kNavy,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: const [
                SizedBox(width: 70, child: Text('Date', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                Expanded(flex: 2, child: Text('Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                Expanded(flex: 2, child: Text('Type', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                Expanded(flex: 5, child: Text('Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                SizedBox(width: 60, child: Text('User', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
              ]),
            );

            Widget dataRow(ProdTx tx, bool even) {
              final parsed = DateTime.tryParse(tx.date);
              final dateStr = parsed != null ? dateFmt.format(parsed) : tx.date;
              final details = _prodDetailTags(tx);
              debugPrint('[ProdTxRow] id=${tx.id} type=${tx.type} tags=${details.length} isWide=$isWide summary=${tx.summary}');

              if (isWide) {
                return Container(
                  color: even ? Colors.white : const Color(0xFFF8F9FA),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 70, child: Text(dateStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    Expanded(flex: 2, child: Text(tx.locationName, style: const TextStyle(fontSize: 12))),
                    Expanded(flex: 2, child: _TypeBadge(tx.type)),
                    Expanded(flex: 5, child: details.isNotEmpty
                      ? Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: details,
                        )
                      : Text(tx.summary, style: const TextStyle(fontSize: 12)),
                    ),
                    SizedBox(width: 60, child: Text(tx.userName, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                  ]),
                );
              }

              // Mobile: wrap layout
              return Container(
                color: even ? Colors.white : const Color(0xFFF8F9FA),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Tag(dateStr, bold: true),
                    if (tx.locationName.isNotEmpty) _Tag(tx.locationName, dim: true),
                    _TypeBadge(tx.type),
                    if (details.isNotEmpty) ...details
                    else _Tag(tx.summary),
                    _Tag(tx.userName, dim: true),
                  ],
                ),
              );
            }

            return Column(children: [
              if (isWide) headerRow(),
              Expanded(child: ListView.separated(
                itemCount: ctrl.rows.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (_, i) => dataRow(ctrl.rows[i], i.isEven),
              )),
            ]);
          });
        })),
      ])),
    );
  }
}

// ── Production detail tags ────────────────────────────────────

List<Widget> _prodDetailTags(ProdTx tx) {
  debugPrint('[ProdDetailTags] type=${tx.type} id=${tx.id} rawKeys=${tx.raw.keys.toList()}');
  num n(String k) => num.tryParse(tx.raw[k]?.toString() ?? '') ?? 0;
  String s(String k) => tx.raw[k]?.toString() ?? '';
  final tags = <Widget>[];

  switch (tx.type) {
    case 'FF Milk Purchase':
      if (s('vendor_name').isNotEmpty) tags.add(_Tag(s('vendor_name')));
      tags.add(_Tag('${n('input_ff_milk_kg').toInt()} KG'));
      tags.add(_Tag('SNF ${n('input_snf')}'));
      tags.add(_Tag('Fat ${n('input_fat')}'));
      tags.add(_Tag('₹${n('input_rate').toStringAsFixed(2)}/KG'));

    case 'FF Milk Processing':
      tags.add(_Tag('Used ${n('input_ff_milk_used_kg').toInt()} KG'));
      tags.add(_Tag('Skim ${n('output_skim_milk_kg').toInt()} KG'));
      tags.add(_Tag('SNF ${n('output_skim_snf')}'));
      tags.add(_Tag('Cream ${n('output_cream_kg').toInt()} KG'));
      tags.add(_Tag('Fat ${n('output_cream_fat')}'));

    case 'Cream Purchase':
      if (s('vendor_name').isNotEmpty) tags.add(_Tag(s('vendor_name')));
      tags.add(_Tag('${n('input_cream_kg').toInt()} KG'));
      tags.add(_Tag('Fat ${n('input_fat')}'));
      tags.add(_Tag('₹${n('input_rate').toStringAsFixed(2)}/KG'));

    case 'Cream Processing':
      tags.add(_Tag('Cream ${n('input_cream_used_kg').toInt()} KG'));
      tags.add(_Tag('Butter ${n('output_butter_kg').toInt()} KG'));
      tags.add(_Tag('Fat ${n('output_butter_fat')}'));
      tags.add(_Tag('Ghee ${n('output_ghee_kg').toInt()} KG'));

    case 'Butter Purchase':
      if (s('vendor_name').isNotEmpty) tags.add(_Tag(s('vendor_name')));
      tags.add(_Tag('${n('input_butter_kg').toInt()} KG'));
      tags.add(_Tag('Fat ${n('input_fat')}'));
      tags.add(_Tag('₹${n('input_rate').toStringAsFixed(2)}/KG'));

    case 'Butter Processing':
      tags.add(_Tag('Butter ${n('input_butter_used_kg').toInt()} KG'));
      tags.add(_Tag('Ghee ${n('output_ghee_kg').toInt()} KG'));

    case 'Dahi Production':
      tags.add(_Tag('Skim ${n('input_skim_milk_kg').toInt()} KG'));
      tags.add(_Tag('SMP ${n('input_smp_bags').toInt()} bags'));
      tags.add(_Tag('Protein ${n('input_protein_kg').toInt()} KG'));
      tags.add(_Tag('Culture ${n('input_culture_kg').toInt()} KG'));
      tags.add(_Tag('Out ${n('output_container_count').toInt()} pcs'));

    case 'Ingredient Purchase':
      final unit = tx.raw['product_id']?.toString() == '7' ? 'Bags' : 'KG';
      tags.add(_Tag('${s('product_name')} ${n('quantity')} $unit'));
      if (n('rate') > 0) tags.add(_Tag('₹${n('rate')}/$unit'));

    case 'Pouch Production':
      debugPrint('[ProdDetailTags] Pouch: notes type=${tx.raw['notes']?.runtimeType} lines type=${tx.raw['lines']?.runtimeType}');
      debugPrint('[ProdDetailTags] Pouch: notes=${tx.raw['notes']}');
      // V4: read cream from lines array
      final pLines = tx.raw['lines'] as List?;
      if (pLines != null) {
        for (final l in pLines) {
          final pid = int.tryParse(l['product_id']?.toString() ?? '') ?? 0;
          final qty = double.tryParse(l['qty']?.toString() ?? '') ?? 0;
          final fat = l['fat'] != null ? double.tryParse(l['fat'].toString()) : null;
          if (pid == 3 && qty > 0) {
            tags.add(_Tag('Cream ${qty % 1 == 0 ? qty.toInt() : qty} KG'));
            if (fat != null) tags.add(_Tag('Fat $fat'));
          }
        }
      }
      // Pouch line details from notes
      final pNotes = tx.raw['notes'];
      if (pNotes is Map) {
        final pouchLines = (pNotes['pouch_lines'] as List?) ?? [];
        for (final pl in pouchLines) {
          final name = pl['name']?.toString() ?? 'Pouch';
          final crates = pl['crate_count'] ?? 0;
          tags.add(_Tag('$name: $crates crates', bold: true));
        }
      }

    case 'Curd Production':
      tags.add(_Tag('Cream ${n('output_cream_kg').toInt()} KG'));
      tags.add(_Tag('Fat ${n('output_cream_fat')}'));
      tags.add(_Tag('Curd ${n('output_curd_matka').toInt()} Matka'));

    case 'Madhusudan Sale':
      tags.add(_Tag('₹${n('sale_rate').toStringAsFixed(2)}/KG'));
  }

  // Add milk usage if present
  final milkUsage = tx.raw['milk_usage'];
  if (milkUsage is List && milkUsage.isNotEmpty) {
    for (final mu in milkUsage) {
      final vn = mu['vendor_name']?.toString() ?? '';
      final kg = num.tryParse(mu['ff_milk_kg']?.toString() ?? '')?.toInt() ?? 0;
      if (vn.isNotEmpty && kg > 0) tags.add(_Tag('$vn $kg KG'));
    }
  }

  return tags;
}

// ── Shared widgets ────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String text;
  final bool bold;
  final bool dim;
  final Color? color;
  const _Tag(this.text, {this.bold = false, this.dim = false, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? (dim ? Colors.grey.shade500 : const Color(0xFF2C3E50));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: c)),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);

  static Color _color(String t) {
    if (t.contains('Purchase')) return const Color(0xFF1565C0);
    if (t.contains('FF Milk'))  return const Color(0xFF2E7D32);
    if (t.contains('Cream'))    return const Color(0xFF6A1B9A);
    if (t.contains('Butter'))   return const Color(0xFFE65100);
    if (t.contains('Pouch'))      return const Color(0xFF5D4037);
    if (t.contains('Dahi'))       return const Color(0xFF00838F);
    if (t.contains('Curd'))       return const Color(0xFF00838F);
    if (t.contains('Madhusudan')) return const Color(0xFFD84315);
    if (t.contains('Ingredient')) return const Color(0xFF558B2F);
    return kNavy;
  }

  @override
  Widget build(BuildContext context) {
    final col = _color(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: col.withValues(alpha: 0.3)),
      ),
      child: Text(type,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: col)),
    );
  }
}
