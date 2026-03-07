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
            _EntryForm(ctrl: ctrl),
            const Divider(height: 1, thickness: 1),
            Expanded(child: _EntriesList(ctrl: ctrl)),
          ]),
        );
      },
    );
  }
}

// ── Entry form at the top ─────────────────────────────────────

class _EntryForm extends StatelessWidget {
  final SalesController ctrl;
  const _EntryForm({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Form(
        key: ctrl.formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

            const SizedBox(height: 10),

            // ── Customer ─────────────────────────────────
            Obx(() => DropdownButtonFormField<int>(
              initialValue: ctrl.selectedCustomerId.value,
              decoration: fieldDec('Customer',
                  prefixIcon: Icons.person_outline),
              items: ctrl.customers.map((cu) => DropdownMenuItem(
                  value: cu.id, child: Text(cu.name))).toList(),
              onChanged: (id) => ctrl.selectedCustomerId.value = id,
              validator: (v) => v == null ? 'Select a customer' : null,
            )),

            const SizedBox(height: 10),

            // ── Product + Qty + Rate row ──────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Product dropdown
              Expanded(flex: 5, child: Obx(() => DropdownButtonFormField<int>(
                initialValue: ctrl.selectedProdId.value,
                decoration: fieldDec('Item'),
                items: ctrl.products.map((p) => DropdownMenuItem(
                    value: p.id, child: Text(p.name))).toList(),
                onChanged: (id) => ctrl.selectedProdId.value = id,
                validator: (v) => v == null ? 'Select item' : null,
                isExpanded: true,
              ))),
              const SizedBox(width: 6),
              // Qty — flex 4 gives enough room for 5 digits
              Expanded(flex: 4, child: IntField(
                  ctrl.qtyCtrl, 'Qty', 'KG', maxDigits: 5)),
              const SizedBox(width: 6),
              // Rate
              Expanded(flex: 4, child: RateField(
                  ctrl.rateCtrl, 'Rate')),
            ]),

            const SizedBox(height: 12),

            // ── Feedback ─────────────────────────────────
            Obx(() {
              if (ctrl.errorMessage.value.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FeedbackBanner(
                      ctrl.errorMessage.value, isError: true),
                );
              }
              if (ctrl.successMessage.value.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FeedbackBanner(
                      ctrl.successMessage.value, isError: false),
                );
              }
              return const SizedBox.shrink();
            }),

            // ── Save button ───────────────────────────────
            Obx(() => ElevatedButton.icon(
              onPressed: ctrl.isSaving.value ? null : ctrl.save,
              icon: ctrl.isSaving.value
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.add_circle_outline),
              label: Text(
                ctrl.isSaving.value ? 'Saving…' : 'Add Sale',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                disabledBackgroundColor: kNavy.withValues(alpha: 0.5),
              ),
            )),
          ],
        ),
        ),
      ),
    );
  }
}

// ── Entries list + day total ──────────────────────────────────

class _EntriesList extends StatelessWidget {
  final SalesController ctrl;
  const _EntriesList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final entries = ctrl.entries;
      if (ctrl.isLoading.value) return const LoadingCenter();
      if (entries.isEmpty) {
        return const EmptyState(
          icon: Icons.receipt_long_outlined,
          message: 'No sales yet for this date.\nAdd one above.',
        );
      }
      return Column(children: [
        // ── Column header ────────────────────────────
        Container(
          color: kNavy.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('Product / Vendor',
                style: TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 12, color: kNavy))),
            Expanded(flex: 2, child: Text('Qty',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 12, color: kNavy))),
            Expanded(flex: 2, child: Text('Rate',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 12, color: kNavy))),
            Expanded(flex: 2, child: Text('Total',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 12, color: kNavy))),
            SizedBox(width: 40),
          ]),
        ),
        // ── Rows ─────────────────────────────────────
        Expanded(child: ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (_, i) => _EntryRow(
              ctrl: ctrl, entry: entries[i]),
        )),
        // ── Day total ─────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
                top: BorderSide(
                    color: Colors.grey.shade300, width: 1.5)),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6, offset: const Offset(0, -2),
            )],
          ),
          child: Row(children: [
            const Expanded(flex: 3, child: Text('Day Total',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15))),
            Expanded(flex: 2, child: Obx(() => Text(
              '${ctrl.dayQty} KG',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14, color: Colors.grey.shade700),
            ))),
            const Expanded(flex: 2, child: SizedBox.shrink()),
            Expanded(flex: 2, child: Obx(() => Text(
              '₹${ctrl.dayTotal.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16, color: kNavy),
            ))),
            const SizedBox(width: 40),
          ]),
        ),
      ]);
    });
  }
}

class _EntryRow extends StatelessWidget {
  final SalesController ctrl;
  final SaleEntry entry;
  const _EntryRow({required this.ctrl, required this.entry});

  @override
  Widget build(BuildContext context) {
    final inrFmt = NumberFormat('#,##,##0.00', 'en_IN');
    final deletable = ctrl.canDelete(entry.id);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(flex: 3, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.productName,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text(entry.customerName,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600)),
          ],
        )),
        Expanded(flex: 2, child: Text(
          '${entry.quantityKg} KG',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        )),
        Expanded(flex: 2, child: Text(
          '₹${entry.rate.toStringAsFixed(2)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        )),
        Expanded(flex: 2, child: Text(
          '₹${inrFmt.format(entry.total)}',
          textAlign: TextAlign.right,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: kGreen),
        )),
        SizedBox(
          width: 40,
          child: deletable
              ? IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.redAccent),
                  onPressed: () => ctrl.deleteEntry(entry.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }
}
