// lib/pages/production_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/production_controller.dart';
import '../controllers/transactions_controller.dart';
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
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Date + Data type on one row ──────────────────
              DCard(child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date picker
                  Expanded(
                    flex: 2,
                    child: Obx(() => InkWell(
                      onTap: () => ctrl.pickDate(context),
                      child: InputDecorator(
                        decoration: fieldDec('Date',
                            prefixIcon: Icons.calendar_today_outlined),
                        child: Text(
                          DateFormat('dd MMM yyyy').format(ctrl.entryDate.value),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    )),
                  ),
                  const SizedBox(width: 12),
                  // Data type dropdown
                  Expanded(
                    flex: 3,
                    child: Obx(() {
                      final flows = ctrl.flowDefs;
                      if (flows.isEmpty) {
                        return DropdownButtonFormField<DataEntry>(
                          initialValue: ctrl.selectedEntry.value,
                          isExpanded: true,
                          decoration: fieldDec('Activity',
                              prefixIcon: Icons.edit_note_outlined),
                          items: DataEntry.values.map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(e.label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          )).toList(),
                          onChanged: (v) {
                            if (v != null) ctrl.selectedEntry.value = v;
                          },
                        );
                      }
                      return DropdownButtonFormField<DataEntry>(
                        initialValue: ctrl.selectedEntry.value,
                        isExpanded: true,
                        decoration: fieldDec('Activity',
                            prefixIcon: Icons.edit_note_outlined),
                        items: flows.map((f) => DropdownMenuItem(
                          value: f.entry,
                          child: Text(f.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        )).toList(),
                        onChanged: (v) {
                          if (v != null) ctrl.selectedEntry.value = v;
                        },
                      );
                    }),
                  ),
                ],
              )),

              const SizedBox(height: 10),

              // ── Active form ──────────────────────────────────
              Obx(() {
                final entry = ctrl.selectedEntry.value;
                return _EntryForm(ctrl: ctrl, entry: entry);
              }),

              const SizedBox(height: 10),

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

              const SizedBox(height: 16),

              // ── Saved entries for this date + flow ───────────
              _SavedEntries(ctrl: ctrl),

              const SizedBox(height: 32),
            ],
          ),
        ),
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
    return FocusTraversalGroup(
      child: DCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Form(
          key: ctrl.formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._fields(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    switch (entry) {

      case DataEntry.ffMilkPurchase:
        return [
          _CompactStockLine(items: [
            _StockItem('FF Milk', ctrl.stockFfMilk, 'KG'),
          ]),
          const SizedBox(height: 8),
          Obx(() => DropdownButtonFormField<int>(
            initialValue: ctrl.selectedVendorId.value,
            decoration: fieldDec('Vendor', prefixIcon: Icons.storefront_outlined),
            items: ctrl.vendors.map((v) => DropdownMenuItem(
                value: v.id, child: Text(v.name))).toList(),
            onChanged: (id) => ctrl.selectedVendorId.value = id,
          )),
          const SizedBox(height: 8),
          _Row4(
            IntField(ctrl.ffMilkCtrl, 'FF Milk', 'KG'),
            SnfFatField(ctrl.inFatCtrl, 'Fat'),
            SnfFatField(ctrl.inSnfCtrl, 'SNF'),
            RateField(ctrl.rateCtrl, 'Rate'),
          ),
        ];

      case DataEntry.creamPurchase:
        return [
          _CompactStockLine(items: [
            _StockItem('Cream', ctrl.stockCream, 'KG'),
          ]),
          const SizedBox(height: 8),
          Obx(() => DropdownButtonFormField<int>(
            initialValue: ctrl.selectedVendorId.value,
            decoration: fieldDec('Vendor', prefixIcon: Icons.storefront_outlined),
            items: ctrl.vendors.map((v) => DropdownMenuItem(
                value: v.id, child: Text(v.name))).toList(),
            onChanged: (id) => ctrl.selectedVendorId.value = id,
          )),
          const SizedBox(height: 8),
          _Row3(
            IntField(ctrl.creamInCtrl, 'Cream', 'KG'),
            SnfFatField(ctrl.creamInFatCtrl, 'Fat'),
            RateField(ctrl.creamInRateCtrl, 'Rate'),
          ),
        ];

      case DataEntry.butterPurchase:
        return [
          _StockBadge(stock: ctrl.stockButter, label: 'Butter in stock'),
          const SizedBox(height: 8),
          Obx(() => DropdownButtonFormField<int>(
            initialValue: ctrl.selectedVendorId.value,
            decoration: fieldDec('Vendor', prefixIcon: Icons.storefront_outlined),
            items: ctrl.vendors.map((v) => DropdownMenuItem(
                value: v.id, child: Text(v.name))).toList(),
            onChanged: (id) => ctrl.selectedVendorId.value = id,
          )),
          const SizedBox(height: 8),
          _Row3(
            IntField(ctrl.butterInCtrl, 'Butter', 'KG'),
            SnfFatField(ctrl.butterInFatCtrl, 'Fat'),
            RateField(ctrl.butterInRateCtrl, 'Rate'),
          ),
        ];

      case DataEntry.ffMilkProcessing:
        return [
          _CompactStockLine(items: [
            _StockItem('FF Milk', ctrl.stockFfMilk, 'KG'),
          ]),
          const SizedBox(height: 4),
          _CompactStockLine(label: 'Output Stock', items: [
            _StockItem('Skim Milk', ctrl.stockSkimMilk, 'KG'),
            _StockItem('Cream', ctrl.stockCream, 'KG'),
            _StockItem('Ghee', ctrl.stockGhee, 'KG'),
          ]),
          const SizedBox(height: 8),
          _VendorMilkPicker(ctrl: ctrl),
          const SizedBox(height: 8),
          _Row4(
            IntField(ctrl.skimMilkCtrl, 'Skim Milk', 'KG'),
            SnfFatField(ctrl.outSkimSnfCtrl, 'SNF'),
            DecimalKgField(ctrl.creamOutCtrl, 'Cream'),
            SnfFatField(ctrl.creamFatCtrl, 'Fat'),
          ),
        ];

      case DataEntry.creamProcessing:
        return [
          _CompactStockLine(items: [
            _StockItem('Cream', ctrl.stockCream, 'KG'),
          ]),
          const SizedBox(height: 4),
          _CompactStockLine(label: 'Output Stock', items: [
            _StockItem('Butter', ctrl.stockButter, 'KG'),
            _StockItem('Ghee', ctrl.stockGhee, 'KG'),
          ]),
          const SizedBox(height: 8),
          Row2(
            IntField(ctrl.creamUsedCtrl, 'Cream Used', 'KG'),
            IntField(ctrl.gheeOutCtrl, 'Ghee', 'KG'),
          ),
          const SizedBox(height: 8),
          Row2(
            IntField(ctrl.butterOutCtrl, 'Butter', 'KG'),
            SnfFatField(ctrl.butterFatCtrl, 'Fat'),
          ),
        ];

      case DataEntry.smpPurchase:
        return [
          _CompactStockLine(items: [
            _StockItem('SMP', ctrl.stockSmp, 'Bags'),
            _StockItem('Protein', ctrl.stockProtein, 'KG'),
            _StockItem('Culture', ctrl.stockCulture, 'KG'),
            _StockItem('Matka', ctrl.stockMatka, 'pcs'),
          ]),
          const SizedBox(height: 8),
          Row2(
            IntField(ctrl.smpCtrl,      'SMP',  'Bags', optional: true),
            RateField(ctrl.smpRateCtrl, 'SMP Rate', optional: true),
          ),
          const SizedBox(height: 8),
          Row2(
            DecimalKgField(ctrl.proteinCtrl,     'Protein', optional: true),
            RateField(ctrl.proteinRateCtrl, 'Protein Rate', optional: true),
          ),
          const SizedBox(height: 8),
          Row2(
            DecimalKgField(ctrl.cultureCtrl,     'Culture', optional: true),
            RateField(ctrl.cultureRateCtrl, 'Culture Rate', optional: true),
          ),
          const SizedBox(height: 8),
          Row2(
            IntField(ctrl.matkaCtrl,     'Matka', 'pcs', optional: true),
            RateField(ctrl.matkaRateCtrl, 'Matka Rate', optional: true),
          ),
        ];

      case DataEntry.butterProcessing:
        return [
          _CompactStockLine(items: [
            _StockItem('Butter', ctrl.stockButter, 'KG'),
          ]),
          const SizedBox(height: 4),
          _CompactStockLine(label: 'Output Stock', items: [
            _StockItem('Ghee', ctrl.stockGhee, 'KG'),
          ]),
          const SizedBox(height: 8),
          Row2(
            IntField(ctrl.butterUsedCtrl, 'Butter Used', 'KG'),
            IntField(ctrl.gheeOut3Ctrl, 'Ghee', 'KG'),
          ),
        ];

      case DataEntry.pouchProduction:
        return [
          _CompactStockLine(items: [
            _StockItem('FF Milk', ctrl.stockFfMilk, 'KG'),
          ]),
          const SizedBox(height: 4),
          _CompactStockLine(label: 'Output Stock', items: [
            _StockItem('Cream', ctrl.stockCream, 'KG'),
          ]),
          const SizedBox(height: 8),
          _VendorMilkPicker(ctrl: ctrl),
          const SizedBox(height: 8),
          Row2(
            DecimalKgField(ctrl.pouchCreamOutCtrl, 'Cream Out'),
            SnfFatField(ctrl.pouchCreamFatCtrl, 'Cream Fat'),
          ),
          const SizedBox(height: 8),
          _PouchLinePicker(ctrl: ctrl),
        ];

      case DataEntry.curdProduction:
        return [
          _CompactStockLine(items: [
            _StockItem('FF Milk', ctrl.stockFfMilk, 'KG'),
            _StockItem('SMP', ctrl.stockSmp, 'Bags'),
            _StockItem('Protein', ctrl.stockProtein, 'KG'),
            _StockItem('Culture', ctrl.stockCulture, 'KG'),
            _StockItem('Matka', ctrl.stockMatka, 'pcs'),
          ]),
          const SizedBox(height: 4),
          _CompactStockLine(label: 'Output Stock', items: [
            _StockItem('Cream', ctrl.stockCream, 'KG'),
            _StockItem('Curd', ctrl.stockCurd, 'pcs'),
          ]),
          const SizedBox(height: 8),
          _VendorMilkPicker(ctrl: ctrl),
          const SizedBox(height: 8),
          _Row3(
            IntField(ctrl.curdSmpCtrl, 'SMP', 'Bags', optional: true),
            DecimalKgField(ctrl.curdProteinCtrl, 'Protein', optional: true),
            DecimalKgField(ctrl.curdCultureCtrl, 'Culture', optional: true),
          ),
          const SizedBox(height: 8),
          _Row3(
            DecimalKgField(ctrl.curdCreamOutCtrl, 'Cream Out'),
            SnfFatField(ctrl.curdCreamFatCtrl, 'Cream Fat'),
            IntField(ctrl.curdOutCtrl, 'Curd Out', 'Matka'),
          ),
        ];

      case DataEntry.madhusudanSale:
        return [
          _CompactStockLine(items: [
            _StockItem('FF Milk', ctrl.stockFfMilk, 'KG'),
          ]),
          const SizedBox(height: 8),
          _VendorMilkPicker(ctrl: ctrl),
          const SizedBox(height: 8),
          RateField(ctrl.madhusudanRateCtrl, 'Madhusudan Rate'),
        ];

    }
  }
}

// ── Saved production entries for current date + flow type ─────────────────

class _SavedEntries extends StatelessWidget {
  final ProductionController ctrl;
  const _SavedEntries({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoadingEntries.value) {
        return const Padding(
          padding: EdgeInsets.all(16), child: LoadingCenter());
      }
      final entries = ctrl.savedEntries;
      if (entries.isEmpty) return const SizedBox.shrink();

      // Group entries by date (most recent first)
      final byDate = <String, List<ProdTx>>{};
      for (final tx in entries) {
        byDate.putIfAbsent(tx.date, () => []).add(tx);
      }
      final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

      return DCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kNavy.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(children: [
                const Icon(Icons.history, size: 16, color: kNavy),
                const SizedBox(width: 8),
                Text('${entries.length} entr${entries.length == 1 ? 'y' : 'ies'} — last 7 days',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: kNavy)),
              ]),
            ),
            ...sortedDates.expand((date) {
              final dayEntries = byDate[date]!;
              return List.generate(dayEntries.length, (i) {
                final tx = dayEntries[i];
                final reversal = tx.isReversal;
                return Container(
                  decoration: BoxDecoration(
                    color: reversal ? const Color(0xFFFDEDED) : null,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Row(children: [
                    if (reversal) ...[
                      const Icon(Icons.undo, size: 12, color: kRed),
                      const SizedBox(width: 3),
                    ],
                    SizedBox(width: 50, child: Text(_fmtDate(date),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600))),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      reversal ? 'REV: ${tx.summary}' : tx.summary,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                          color: reversal ? kRed : null),
                    )),
                    const SizedBox(width: 6),
                    Text('${tx.userName}  ${_fmtTime(tx.createdAt)}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ]),
                );
              });
            }),
          ],
        ),
      );
    });
  }

  String _fmtDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd MMM').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  String _fmtTime(String ts) {
    try {
      final dt = DateTime.parse(ts);
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return ts;
    }
  }
}

// ── 3-column and 4-column row helpers ─────────────────────────────────────

class _Row3 extends StatelessWidget {
  final Widget a, b, c;
  const _Row3(this.a, this.b, this.c);
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: a), const SizedBox(width: 8),
    Expanded(child: b), const SizedBox(width: 8),
    Expanded(child: c),
  ]);
}

class _Row4 extends StatelessWidget {
  final Widget a, b, c, d;
  const _Row4(this.a, this.b, this.c, this.d);
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: a), const SizedBox(width: 8),
    Expanded(child: b), const SizedBox(width: 8),
    Expanded(child: c), const SizedBox(width: 8),
    Expanded(child: d),
  ]);
}

// ── Compact inline stock summary (single line, wrapping) ─────────────────

class _StockItem {
  final String label;
  final RxnInt stock;
  final String unit;
  const _StockItem(this.label, this.stock, this.unit);
}

class _CompactStockLine extends StatelessWidget {
  final List<_StockItem> items;
  final String? label;
  const _CompactStockLine({required this.items, this.label});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final spans = <InlineSpan>[];
      spans.add(TextSpan(
        text: '${label ?? "Input Stock"}: ',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50)),
      ));
      bool first = true;
      for (final item in items) {
        final qty = item.stock.value;
        if (qty == null) continue;
        if (!first) {
          spans.add(const TextSpan(
            text: ',  ',
            style: TextStyle(fontSize: 12, color: Color(0xFF2C3E50)),
          ));
        }
        first = false;
        final isNeg = qty < 0;
        final color = isNeg ? kRed : kGreen;
        spans.add(TextSpan(
          text: '${item.label} ',
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
        ));
        spans.add(TextSpan(
          text: '$qty ${item.unit}',
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w800),
        ));
      }
      if (spans.length <= 1) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text.rich(TextSpan(children: spans), softWrap: true),
      );
    });
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

// ── Vendor Milk Picker — reusable multi-vendor milk selection ──────────────

class _VendorMilkPicker extends StatelessWidget {
  final ProductionController ctrl;
  const _VendorMilkPicker({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoadingAvail.value) return const LoadingCenter();
      if (ctrl.milkAvailability.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('No milk available from any vendor. Record FF Milk Purchases first.',
              style: TextStyle(fontSize: 13, color: kRed)),
        );
      }

      // Initialize with one row if empty
      if (ctrl.milkUsageRows.isEmpty) ctrl.addMilkUsageRow();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Milk from Vendors',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          ...List.generate(ctrl.milkUsageRows.length, (i) {
            final row = ctrl.milkUsageRows[i];
            final selectedVid = row['vendor_id'] as int?;
            // Already-selected vendor IDs (exclude current row)
            final usedIds = ctrl.milkUsageRows
                .where((r) => r != row && r['vendor_id'] != null)
                .map((r) => r['vendor_id'] as int)
                .toSet();
            final availVendors = ctrl.milkAvailability
                .where((v) => !usedIds.contains(v.vendorId) || v.vendorId == selectedVid)
                .toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedVid,
                      isExpanded: true,
                      decoration: fieldDec('Vendor', isDense: true),
                      items: availVendors.map((v) => DropdownMenuItem(
                        value: v.vendorId,
                        child: Text('${v.vendorName} (${v.availableKg} KG)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      )).toList(),
                      onChanged: (id) {
                        ctrl.milkUsageRows[i] = {
                          ...row,
                          'vendor_id': id,
                        };
                        ctrl.milkUsageRows.refresh();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: row['ctrl'] as TextEditingController,
                      decoration: fieldDec('KG', isDense: true),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final qty = int.tryParse(v);
                        if (qty == null || qty <= 0) return 'Invalid';
                        if (selectedVid != null) {
                          final avail = ctrl.milkAvailability
                              .where((a) => a.vendorId == selectedVid)
                              .firstOrNull?.availableKg ?? 0;
                          if (qty > avail) return 'Max $avail';
                        }
                        return null;
                      },
                    ),
                  ),
                  if (ctrl.milkUsageRows.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: kRed, size: 20),
                      onPressed: () => ctrl.removeMilkUsageRow(i),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                    ),
                ],
              ),
            );
          }),
          // ── Total row ──
          if (ctrl.milkUsageRows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(children: [
                const Spacer(flex: 3),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _MilkUsageTotal(rows: ctrl.milkUsageRows),
                ),
                const SizedBox(width: 32),
              ]),
            ),
          if (ctrl.milkUsageRows.length < ctrl.milkAvailability.length)
            TextButton.icon(
              onPressed: ctrl.addMilkUsageRow,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Vendor', style: TextStyle(fontSize: 13)),
            ),
        ],
      );
    });
  }
}

// ── Live total of milk usage quantities ──────────────────────────────────

class _MilkUsageTotal extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const _MilkUsageTotal({required this.rows});

  @override
  State<_MilkUsageTotal> createState() => _MilkUsageTotalState();
}

class _MilkUsageTotalState extends State<_MilkUsageTotal> {
  int _total = 0;

  void _recalc() {
    int sum = 0;
    for (final row in widget.rows) {
      final c = row['ctrl'] as TextEditingController;
      sum += int.tryParse(c.text) ?? 0;
    }
    if (sum != _total) setState(() => _total = sum);
  }

  void _attach() {
    for (final row in widget.rows) {
      (row['ctrl'] as TextEditingController).addListener(_recalc);
    }
    _recalc();
  }

  void _detach() {
    for (final row in widget.rows) {
      try { (row['ctrl'] as TextEditingController).removeListener(_recalc); } catch (_) {}
    }
  }

  @override
  void initState() { super.initState(); _attach(); }

  @override
  void didUpdateWidget(covariant _MilkUsageTotal old) {
    super.didUpdateWidget(old);
    _detach();
    _attach();
  }

  @override
  void dispose() { _detach(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: kNavy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('Total: $_total KG',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kNavy)),
    );
  }
}

// ── Pouch Line Picker — dynamic pouch type + quantity rows ────────────────

class _PouchLinePicker extends StatelessWidget {
  final ProductionController ctrl;
  const _PouchLinePicker({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.pouchTypes.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('No pouch types configured. Add them from Reports > Pouch Types.',
              style: TextStyle(fontSize: 13, color: Colors.deepOrange)),
        );
      }

      if (ctrl.pouchLineRows.isEmpty) ctrl.addPouchLineRow();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pouch Output',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          ...List.generate(ctrl.pouchLineRows.length, (i) {
            final row = ctrl.pouchLineRows[i];
            final selectedPtId = row['pouch_type_id'] as int?;
            final usedIds = ctrl.pouchLineRows
                .where((r) => r != row && r['pouch_type_id'] != null)
                .map((r) => r['pouch_type_id'] as int)
                .toSet();
            final availTypes = ctrl.pouchTypes
                .where((t) => !usedIds.contains(t.id) || t.id == selectedPtId)
                .toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedPtId,
                      isExpanded: true,
                      decoration: fieldDec('Pouch Type', isDense: true),
                      items: availTypes.map((t) => DropdownMenuItem(
                        value: t.id,
                        child: Text('${t.name} (${t.milkPerPouch}L)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      )).toList(),
                      onChanged: (id) {
                        ctrl.pouchLineRows[i] = {
                          ...row,
                          'pouch_type_id': id,
                        };
                        ctrl.pouchLineRows.refresh();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: row['ctrl'] as TextEditingController,
                      decoration: fieldDec('Crates', isDense: true),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final qty = int.tryParse(v);
                        if (qty == null || qty <= 0) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  if (ctrl.pouchLineRows.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: kRed, size: 20),
                      onPressed: () => ctrl.removePouchLineRow(i),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                    ),
                ],
              ),
            );
          }),
          if (ctrl.pouchLineRows.length < ctrl.pouchTypes.length)
            TextButton.icon(
              onPressed: ctrl.addPouchLineRow,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Pouch Type', style: TextStyle(fontSize: 13)),
            ),
        ],
      );
    });
  }
}
