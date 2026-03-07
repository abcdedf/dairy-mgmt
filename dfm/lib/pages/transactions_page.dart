// lib/pages/transactions_page.dart
//
// Two pages: SalesTransactionsPage and ProductionTransactionsPage.
// Both show transactions for last N days (configured on backend).
// Each row shows date, type/product, quantities, and the user's first name.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/transactions_controller.dart';
import 'shared_widgets.dart';

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
    final inrFmt  = NumberFormat('#,##,##0.00', 'en_IN');

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
      body: Obx(() {
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

        // Group by date for section headers
        final grouped = <String, List<SaleTx>>{};
        for (final r in ctrl.rows) {
          grouped.putIfAbsent(r.date, () => []).add(r);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: grouped.length,
          itemBuilder: (_, i) {
            final date = grouped.keys.elementAt(i);
            final txs  = grouped[date]!;
            final dayTotal = txs.fold(0.0, (s, t) => s + t.total);
            final parsed = DateTime.tryParse(date);
            final label  = parsed != null
                ? DateFormat('dd MMM yyyy (EEEE)').format(parsed)
                : date;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Date section header ────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: kNavy)),
                    ),
                    Text('₹${inrFmt.format(dayTotal)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: kNavy)),
                  ]),
                ),
                // ── Cards for each transaction ─────────
                ...txs.map((tx) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(children: [
                      // Left: product + customer
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tx.productName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(tx.customerName,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            // Rate + entered by
                            Row(children: [
                              _Chip('${tx.quantityKg} KG'),
                              const SizedBox(width: 6),
                              _Chip('₹${tx.rate.toStringAsFixed(2)}/KG'),
                              const SizedBox(width: 6),
                              _Chip(tx.userName,
                                  icon: Icons.person_outline, dim: true),
                            ]),
                          ],
                        ),
                      ),
                      // Right: total
                      Text('₹${inrFmt.format(tx.total)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: kGreen)),
                    ]),
                  ),
                )),
                const SizedBox(height: 4),
              ],
            );
          },
        );
      }),
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
      body: Obx(() {
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

        // Group by date
        final grouped = <String, List<ProdTx>>{};
        for (final r in ctrl.rows) {
          grouped.putIfAbsent(r.date, () => []).add(r);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: grouped.length,
          itemBuilder: (_, i) {
            final date = grouped.keys.elementAt(i);
            final txs  = grouped[date]!;
            final parsed = DateTime.tryParse(date);
            final label  = parsed != null
                ? DateFormat('dd MMM yyyy (EEEE)').format(parsed)
                : date;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Date section header ────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: kNavy)),
                ),
                // ── Cards ─────────────────────────────
                ...txs.map((tx) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Type badge + user
                        Row(children: [
                          _TypeBadge(tx.type),
                          const Spacer(),
                          _Chip(tx.userName,
                              icon: Icons.person_outline, dim: true),
                        ]),
                        const SizedBox(height: 10),
                        // All fields as labelled rows
                        ..._prodFields(tx),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: 4),
              ],
            );
          },
        );
      }),
    );
  }
}


// ── Build labelled field rows for a production transaction ────

List<Widget> _prodFields(ProdTx tx) {
  num n(String k) => num.tryParse(tx.raw[k]?.toString() ?? '') ?? 0;
  String s(String k) => tx.raw[k]?.toString() ?? '';

  // Always add — even if zero (caller decides what to include)
  final rows = <_FieldRow>[];

  switch (tx.type) {
    case 'FF Milk Purchase':
      if (s('vendor_name').isNotEmpty) {
        rows.add(_FieldRow('Vendor',  s('vendor_name')));
      }
      rows.add(_FieldRow('FF Milk',   '${n('input_ff_milk_kg').toInt()} KG'));
      rows.add(_FieldRow('SNF',       '${n('input_snf')}'));
      rows.add(_FieldRow('Fat',       '${n('input_fat')}'));
      rows.add(_FieldRow('Rate',      '₹${n('input_rate').toStringAsFixed(2)}/KG'));

    case 'FF Milk Processing':
      rows.add(_FieldRow('FF Milk Used',  '${n('input_ff_milk_used_kg').toInt()} KG'));
      rows.add(_FieldRow('Skim Milk',     '${n('output_skim_milk_kg').toInt()} KG'));
      rows.add(_FieldRow('Skim SNF',      '${n('output_skim_snf')}'));
      rows.add(_FieldRow('Cream Out',     '${n('output_cream_kg').toInt()} KG'));
      rows.add(_FieldRow('Cream Fat',     '${n('output_cream_fat')}'));

    case 'Cream Purchase':
      if (s('vendor_name').isNotEmpty) {
        rows.add(_FieldRow('Vendor',  s('vendor_name')));
      }
      rows.add(_FieldRow('Cream',     '${n('input_cream_kg').toInt()} KG'));
      rows.add(_FieldRow('Fat',       '${n('input_fat')}'));
      rows.add(_FieldRow('Rate',      '₹${n('input_rate').toStringAsFixed(2)}/KG'));

    case 'Cream Processing':
      rows.add(_FieldRow('Cream Used',  '${n('input_cream_used_kg').toInt()} KG'));
      rows.add(_FieldRow('Butter Out',  '${n('output_butter_kg').toInt()} KG'));
      rows.add(_FieldRow('Butter Fat',  '${n('output_butter_fat')}'));
      rows.add(_FieldRow('Ghee Out',    '${n('output_ghee_kg').toInt()} KG'));

    case 'Butter Purchase':
      if (s('vendor_name').isNotEmpty) {
        rows.add(_FieldRow('Vendor',  s('vendor_name')));
      }
      rows.add(_FieldRow('Butter',    '${n('input_butter_kg').toInt()} KG'));
      rows.add(_FieldRow('Fat',       '${n('input_fat')}'));
      rows.add(_FieldRow('Rate',      '₹${n('input_rate').toStringAsFixed(2)}/KG'));

    case 'Butter Processing':
      rows.add(_FieldRow('Butter Used', '${n('input_butter_used_kg').toInt()} KG'));
      rows.add(_FieldRow('Ghee Out',    '${n('output_ghee_kg').toInt()} KG'));

    case 'Dahi Production':
      rows.add(_FieldRow('Skim Milk',    '${n('input_skim_milk_kg').toInt()} KG'));
      rows.add(_FieldRow('SMP Bags',     '${n('input_smp_bags').toInt()} pkts'));
      rows.add(_FieldRow('Protein',      '${n('input_protein_kg').toInt()} KG'));
      rows.add(_FieldRow('Culture',      '${n('input_culture_kg').toInt()} KG'));
      rows.add(_FieldRow('Containers',   '${n('input_container_count').toInt()} pcs'));
      rows.add(_FieldRow('Dahi Out',     '${n('output_container_count').toInt()} pcs'));
    case 'Ingredient Purchase':
      final unit = tx.raw['product_id']?.toString() == '7' ? 'Bags' : 'KG';
      rows.add(_FieldRow(tx.raw['product_name']?.toString() ?? 'Item',
                         '${n('quantity')} $unit'));
      if (n('rate') > 0) rows.add(_FieldRow('Rate', '₹${n('rate')}/$unit'));
  }

  // Two columns side-by-side
  final widgets = <Widget>[];
  for (var i = 0; i < rows.length; i += 2) {
    widgets.add(Row(children: [
      Expanded(child: rows[i]),
      if (i + 1 < rows.length) Expanded(child: rows[i + 1])
      else const Expanded(child: SizedBox()),
    ]));
    widgets.add(const SizedBox(height: 6));
  }

  return widgets;
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  const _FieldRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3)),
      Text(value,
          style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Shared small widgets ──────────────────────────────────────

class _Chip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool dim;
  const _Chip(this.text, {this.icon, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final color = dim ? Colors.grey.shade500 : kNavy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color)),
      ]),
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
    if (t.contains('Dahi'))       return const Color(0xFF00838F);
    if (t.contains('Ingredient')) return const Color(0xFF558B2F);
    return kNavy;
  }

  @override
  Widget build(BuildContext context) {
    final col = _color(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: col.withValues(alpha: 0.3)),
      ),
      child: Text(type,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: col)),
    );
  }
}
