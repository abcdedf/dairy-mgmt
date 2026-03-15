// lib/pages/sales_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/sales_controller.dart';
import 'shared_widgets.dart';

class SalesPage extends StatelessWidget {
  const SalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(SalesController());
    return GetBuilder<SalesController>(
      builder: (_) {
        if (ctrl.isLoading.value && ctrl.products.isEmpty) {
          return const LoadingCenter();
        }
        return ColoredBox(
          color: const Color(0xFFF5F7FA),
          child: Column(children: [
            Expanded(child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(ctrl: ctrl),
                  _EntryForm(ctrl: ctrl),
                  const Divider(height: 1, thickness: 1),
                  _SavedEntries(ctrl: ctrl),
                ],
              ),
            )),
            _DayTotalFooter(ctrl: ctrl),
          ]),
        );
      },
    );
  }
}

// ── Date + stock + feedback header ────────────────────────────

class _Header extends StatelessWidget {
  final SalesController ctrl;
  const _Header({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Date ─────────────────────────────────────
          Obx(() => InkWell(
            onTap: () => ctrl.pickDate(context),
            child: InputDecorator(
              decoration: fieldDec('Date',
                  prefixIcon: Icons.calendar_today_outlined),
              child: Text(
                DateFormat('dd MMM yyyy').format(ctrl.entryDate.value),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          )),

          const SizedBox(height: 8),

          // ── Stock badges ────────────────────────────
          Obx(() => Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _StockChip(label: 'Skim', stock: ctrl.stockSkimMilk.value),
              _StockChip(label: 'Cream', stock: ctrl.stockCream.value),
              _StockChip(label: 'Ghee', stock: ctrl.stockGhee.value),
              _StockChip(label: 'Curd', stock: ctrl.stockCurd.value, unit: 'Matka'),
            ],
          )),

          const SizedBox(height: 6),

          // ── Error feedback ───────────────────────────
          Obx(() {
            if (ctrl.errorMessage.value.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FeedbackBanner(ctrl.errorMessage.value, isError: true),
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
    );
  }
}

// ── Single entry form ─────────────────────────────────────────

class _EntryForm extends StatelessWidget {
  final SalesController ctrl;
  const _EntryForm({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Form(
        key: ctrl.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Product + Customer (product first, customer filtered) ──
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Obx(() => DropdownButtonFormField<int>(
                value: ctrl.productId.value,
                decoration: fieldDec('Product', isDense: true),
                items: ctrl.products.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: ctrl.onProductChanged,
                isExpanded: true,
              ))),
              const SizedBox(width: 6),
              Expanded(child: Obx(() => DropdownButtonFormField<int>(
                key: ValueKey('cust_${ctrl.productId.value}'),
                value: ctrl.customerId.value,
                decoration: fieldDec('Customer', isDense: true),
                items: ctrl.filteredCustomers.map((cu) => DropdownMenuItem(
                    value: cu.id,
                    child: Text(cu.name, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (id) => ctrl.customerId.value = id,
                isExpanded: true,
              ))),
            ]),
            const SizedBox(height: 6),
            // ── Qty + Rate + Save ────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Obx(() =>
                  IntField(ctrl.qtyCtrl, 'Qty', ctrl.selectedUnit, maxDigits: 5))),
              const SizedBox(width: 6),
              Expanded(child: RateField(ctrl.rateCtrl, 'Rate')),
              const SizedBox(width: 6),
              SizedBox(
                height: 48,
                child: Obx(() => ElevatedButton.icon(
                  onPressed: ctrl.isSaving.value ? null : ctrl.save,
                  icon: ctrl.isSaving.value
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(
                    ctrl.isSaving.value ? 'Saving…' : 'Save',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    disabledBackgroundColor: kGreen.withValues(alpha: 0.5),
                  ),
                )),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Saved entries list ────────────────────────────────────────

class _SavedEntries extends StatelessWidget {
  final SalesController ctrl;
  const _SavedEntries({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final entries = ctrl.filteredEntries;
      if (ctrl.isLoading.value) {
        return const Padding(
          padding: EdgeInsets.all(32), child: LoadingCenter());
      }
      if (entries.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'No sales for the last 7 days.',
          ),
        );
      }
      final inrFmt = NumberFormat('#,##,##0.00', 'en_IN');
      final dateFmt = DateFormat('dd MMM');
      return Column(children: [
        // Header
        Container(
          color: kNavy.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            const Expanded(flex: 2, child: Text('Date',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: kNavy))),
            const Expanded(flex: 3, child: Text('Customer',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: kNavy))),
            Expanded(flex: 2, child: Text('Qty (${ctrl.selectedUnit})',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: kNavy))),
            const Expanded(flex: 3, child: Text('Rate (₹)',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: kNavy))),
            const Expanded(flex: 4, child: Text('Total (₹)',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: kNavy))),
            const SizedBox(width: 36),
          ]),
        ),
        // Rows
        ...List.generate(entries.length, (i) {
          final entry = entries[i];
          final deletable = ctrl.canDelete(entry.id);
          final dateStr = entry.date.isNotEmpty
              ? dateFmt.format(DateTime.parse(entry.date))
              : '';
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: i < entries.length - 1
                  ? Border(bottom: BorderSide(color: Colors.grey.shade200))
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(flex: 2, child: Text(dateStr,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
              Expanded(flex: 3, child: Text(entry.customerName,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text('${entry.quantityKg}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13))),
              Expanded(flex: 3, child: Text(entry.rate.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13))),
              Expanded(flex: 4, child: Text(inrFmt.format(entry.total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kGreen))),
              SizedBox(width: 36, child: deletable
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      onPressed: () => ctrl.deleteEntry(entry.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 20,
                    )
                  : const SizedBox.shrink()),
            ]),
          );
        }),
      ]);
    });
  }
}

// ── Day total footer ──────────────────────────────────────────

class _DayTotalFooter extends StatelessWidget {
  final SalesController ctrl;
  const _DayTotalFooter({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.filteredEntries.isEmpty) return const SizedBox.shrink();
      final inrFmt = NumberFormat('#,##,##0.00', 'en_IN');
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1.5)),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6, offset: const Offset(0, -2),
          )],
        ),
        child: Row(children: [
          const Expanded(flex: 2, child: SizedBox.shrink()),
          const Expanded(flex: 3, child: Text('Total',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          Expanded(flex: 2, child: Text('${ctrl.dayQty}',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.grey.shade700))),
          const Expanded(flex: 3, child: SizedBox.shrink()),
          Expanded(flex: 4, child: Text(inrFmt.format(ctrl.dayTotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kNavy))),
          const SizedBox(width: 36),
        ]),
      );
    });
  }
}

// ── Stock chip ────────────────────────────────────────────────

class _StockChip extends StatelessWidget {
  final String label;
  final int? stock;
  final String unit;
  const _StockChip({required this.label, required this.stock, this.unit = 'KG'});

  @override
  Widget build(BuildContext context) {
    final val = stock;
    final isNeg = val != null && val < 0;
    final color = isNeg ? kRed : kNavy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: ${val ?? '—'} $unit',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
