// lib/pages/production_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/production_controller.dart';
import 'shared_widgets.dart';

class ProductionPage extends StatelessWidget {
  const ProductionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(ProductionController());
    // No nested Scaffold — this page lives inside the main Scaffold already.
    // A second AppBar steals height on small phones and causes overflow.
    return ColoredBox(
      color: const Color(0xFFF5F7FA),
      child: _ProductionBody(ctrl: ctrl),
    );
  }
}

// ── Body extracted as its own widget ──

class _ProductionBody extends StatelessWidget {
  final ProductionController ctrl;
  const _ProductionBody({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isVendorLoading.value) return const LoadingCenter();
      return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Date ────────────────────────────────────────
              DCard(child: Obx(() => InkWell(
                onTap: () => ctrl.pickDate(context),
                child: InputDecorator(
                  decoration: fieldDec('Date',
                      prefixIcon: Icons.calendar_today_outlined),
                  child: Text(
                    DateFormat('dd MMM yyyy').format(ctrl.entryDate.value),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ))),

              const SizedBox(height: 12),

              // ── Data type dropdown ───────────────────────────
              DCard(child: Obx(() => DropdownButtonFormField<DataEntry>(
                initialValue: ctrl.selectedEntry.value,
                isExpanded: true,
                decoration: fieldDec('Data',
                    prefixIcon: Icons.edit_note_outlined),
                items: DataEntry.values.map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                )).toList(),
                onChanged: (v) {
                  if (v != null) ctrl.selectedEntry.value = v;
                },
              ))),

              const SizedBox(height: 16),

              // ── Active form ──────────────────────────────────
              Obx(() {
                final entry = ctrl.selectedEntry.value;
                return _EntryForm(ctrl: ctrl, entry: entry);
              }),

              const SizedBox(height: 16),

              // ── Feedback ─────────────────────────────────────
              Obx(() {
                if (ctrl.errorMessage.value.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FeedbackBanner(
                        ctrl.errorMessage.value, isError: true),
                  );
                }
                return const SizedBox.shrink();
              }),

              // ── Save button ──────────────────────────────────
              Obx(() => ElevatedButton.icon(
                onPressed: ctrl.isLoading.value ? null : ctrl.save,
                icon: ctrl.isLoading.value
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(
                  ctrl.isLoading.value ? 'Saving…' : 'Save',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor: kNavy.withValues(alpha: 0.5),
                ),
              )),

              const SizedBox(height: 32),
            ],
          ),
        );
      });
  }
}

// ── Entry form ────────────────────────────────────────────────

class _EntryForm extends StatelessWidget {
  final ProductionController ctrl;
  final DataEntry entry;
  const _EntryForm({required this.ctrl, required this.entry});

  @override
  Widget build(BuildContext context) {
    return DCard(
      child: Form(
        key: ctrl.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(entry.icon, size: 18, color: kNavy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: kNavy),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            ..._fields(),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields() {
    switch (entry) {

      case DataEntry.ffMilkPurchase:
        return [
          Obx(() => DropdownButtonFormField<int>(
            initialValue: ctrl.selectedVendorId.value,
            decoration: fieldDec('Vendor', prefixIcon: Icons.storefront_outlined),
            items: ctrl.vendors.map((v) => DropdownMenuItem(
                value: v.id, child: Text(v.name))).toList(),
            onChanged: (id) => ctrl.selectedVendorId.value = id,
          )),
          const SizedBox(height: 12),
          Row2(
            IntField(ctrl.ffMilkCtrl, 'FF Milk', 'KG'),
            RateField(ctrl.rateCtrl, 'Rate'),
          ),
          const SizedBox(height: 12),
          Row2(
            SnfFatField(ctrl.inSnfCtrl, 'SNF'),
            SnfFatField(ctrl.inFatCtrl, 'Fat'),
          ),
        ];

      case DataEntry.creamPurchase:
        return [
          Obx(() => DropdownButtonFormField<int>(
            initialValue: ctrl.selectedVendorId.value,
            decoration: fieldDec('Vendor', prefixIcon: Icons.storefront_outlined),
            items: ctrl.vendors.map((v) => DropdownMenuItem(
                value: v.id, child: Text(v.name))).toList(),
            onChanged: (id) => ctrl.selectedVendorId.value = id,
          )),
          const SizedBox(height: 12),
          IntField(ctrl.creamInCtrl, 'Cream', 'KG'),
          const SizedBox(height: 12),
          Row2(
            SnfFatField(ctrl.creamInFatCtrl, 'Fat'),
            RateField(ctrl.creamInRateCtrl, 'Rate'),
          ),
        ];

      case DataEntry.butterPurchase:
        return [
          _StockBadge(stock: ctrl.stockButter, label: 'Butter in stock'),
          const SizedBox(height: 10),
          Obx(() => DropdownButtonFormField<int>(
            initialValue: ctrl.selectedVendorId.value,
            decoration: fieldDec('Vendor', prefixIcon: Icons.storefront_outlined),
            items: ctrl.vendors.map((v) => DropdownMenuItem(
                value: v.id, child: Text(v.name))).toList(),
            onChanged: (id) => ctrl.selectedVendorId.value = id,
          )),
          const SizedBox(height: 12),
          IntField(ctrl.butterInCtrl, 'Butter', 'KG'),
          const SizedBox(height: 12),
          Row2(
            SnfFatField(ctrl.butterInFatCtrl, 'Fat'),
            RateField(ctrl.butterInRateCtrl, 'Rate'),
          ),
        ];

      case DataEntry.ffMilkProcessing:
        return [
          _StockBadge(stock: ctrl.stockFfMilk, label: 'FF Milk in stock'),
          const SizedBox(height: 10),
          IntField(ctrl.ffMilkUsedCtrl, 'FF Milk Used', 'KG'),
          const SizedBox(height: 4),
          Text('From stock — reduces FF Milk balance.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          Row2(
            IntField(ctrl.skimMilkCtrl, 'Skim Milk', 'KG'),
            SnfFatField(ctrl.outSkimSnfCtrl, 'SNF'),
          ),
          const SizedBox(height: 12),
          Row2(
            IntField(ctrl.creamOutCtrl, 'Cream', 'KG'),
            SnfFatField(ctrl.creamFatCtrl, 'Fat'),
          ),
        ];

      case DataEntry.creamProcessing:
        return [
          _StockBadge(stock: ctrl.stockCream, label: 'Cream in stock'),
          const SizedBox(height: 10),
          IntField(ctrl.creamUsedCtrl, 'Cream Used', 'KG'),
          const SizedBox(height: 4),
          Text('From stock — reduces Cream balance.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          Row2(
            IntField(ctrl.butterOutCtrl, 'Butter', 'KG'),
            SnfFatField(ctrl.butterFatCtrl, 'Fat'),
          ),
          const SizedBox(height: 12),
          IntField(ctrl.gheeOutCtrl, 'Ghee', 'KG'),
          const SizedBox(height: 12),
          _StockBadge(stock: ctrl.stockButter, label: 'Butter in stock'),
        ];

      case DataEntry.smpPurchase:
        return [
          // FIX 1 & 2: _StockBadge now accepts optional unit param
          _StockBadge(stock: ctrl.stockSmp,     label: 'SMP in stock',     unit: 'Bags'),
          const SizedBox(height: 6),
          _StockBadge(stock: ctrl.stockProtein, label: 'Protein in stock'),
          const SizedBox(height: 6),
          _StockBadge(stock: ctrl.stockCulture, label: 'Culture in stock'),
          const SizedBox(height: 10),
          Text('Enter at least one non-zero value.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          Row2(
            IntField(ctrl.smpCtrl,      'SMP',  'Bags', optional: true),
            RateField(ctrl.smpRateCtrl, 'SMP Rate', optional: true),
          ),
          const SizedBox(height: 12),
          Row2(
            DecimalKgField(ctrl.proteinCtrl,     'Protein', optional: true),
            RateField(ctrl.proteinRateCtrl, 'Protein Rate', optional: true),
          ),
          const SizedBox(height: 12),
          Row2(
            DecimalKgField(ctrl.cultureCtrl,     'Culture', optional: true),
            RateField(ctrl.cultureRateCtrl, 'Culture Rate', optional: true),
          ),
        ];

      case DataEntry.butterProcessing:
        return [
          _StockBadge(stock: ctrl.stockButter, label: 'Butter in stock'),
          const SizedBox(height: 10),
          IntField(ctrl.butterUsedCtrl, 'Butter Used', 'KG'),
          const SizedBox(height: 4),
          Text('From stock — reduces Butter balance.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          IntField(ctrl.gheeOut3Ctrl, 'Ghee', 'KG'),
        ];

      case DataEntry.dahiProcessing:
        return [
          _StockBadge(stock: ctrl.stockSkimMilk, label: 'Skim Milk in stock'),
          const SizedBox(height: 6),
          // FIX 1 & 2: unit param now accepted
          _StockBadge(stock: ctrl.stockSmp,     label: 'SMP in stock',     unit: 'Bags'),
          const SizedBox(height: 6),
          _StockBadge(stock: ctrl.stockProtein, label: 'Protein in stock'),
          const SizedBox(height: 6),
          _StockBadge(stock: ctrl.stockCulture, label: 'Culture in stock'),
          const SizedBox(height: 10),
          // ── Inputs ──────────────────────────────────
          IntField(ctrl.dahiSkimMilkCtrl, 'Skim Milk Used', 'KG'),
          const SizedBox(height: 4),
          Text('From stock — reduces Skim Milk balance.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          Row2(
            IntField(ctrl.dahiSmpCtrl, 'SMP', 'Pkts'),
            // FIX 3: was RateField — protein is a decimal KG amount, not a rate
            DecimalKgField(ctrl.dahiProteinCtrl, 'Protein'),
          ),
          const SizedBox(height: 12),
          // FIX 4: was RateField — culture is a decimal KG amount, not a rate
          DecimalKgField(ctrl.dahiCultureCtrl, 'Culture'),
          const SizedBox(height: 16),
          // ── Containers ──────────────────────────────
          Text('Containers',
              style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Row2(
            IntField(ctrl.dahiContainerCtrl, 'Container', 'pcs'),
            // Seal is read-only — auto-mirrored from container count
            AbsorbPointer(
              child: IntField(ctrl.dahiSealCtrl, 'Seal (auto)', 'pcs'),
            ),
          ),
          const SizedBox(height: 4),
          Text('Seal count is automatically set equal to container count.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          // ── Output ──────────────────────────────────
          _StockBadge(stock: ctrl.stockDahi, label: 'Dahi in stock'),
          const SizedBox(height: 10),
          IntField(ctrl.dahiOutCtrl, 'Dahi Out', 'pcs'),
        ];
    }
  }
}

// ── Read-only stock balance badge shown in processing forms ──────────────
// FIX 1: added optional [unit] param (default 'KG') so SMP can show 'Bags'

class _StockBadge extends StatelessWidget {
  final RxnInt stock;
  final String label;
  final String unit;                                    // FIX: was missing
  const _StockBadge({
    required this.stock,
    required this.label,
    this.unit = 'KG',                                   // FIX: default KG
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final qty = stock.value;
      if (qty == null) return const SizedBox.shrink();
      final isNeg = qty < 0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isNeg
              ? kRed.withValues(alpha: 0.08)
              : const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isNeg ? kRed.withValues(alpha: 0.4) : kGreen.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(
            isNeg ? Icons.warning_amber_outlined : Icons.inventory_2_outlined,
            size: 16,
            color: isNeg ? kRed : kGreen,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: isNeg ? kRed : kGreen,
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Text('$qty $unit',                            // FIX: was hardcoded 'KG'
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isNeg ? kRed : kGreen)),
        ]),
      );
    });
  }
}
