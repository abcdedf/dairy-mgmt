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
              DCard(child: Obx(() {
                final flows = ctrl.flowDefs;
                if (flows.isEmpty) {
                  return DropdownButtonFormField<DataEntry>(
                    initialValue: ctrl.selectedEntry.value,
                    isExpanded: true,
                    decoration: fieldDec('Data',
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
                  decoration: fieldDec('Data',
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
              })),

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

              const SizedBox(height: 16),

              // ── Saved entries for this date + flow ───────────
              _SavedEntries(ctrl: ctrl),

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
    return FocusTraversalGroup(
      child: DCard(
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
          _VendorMilkPicker(ctrl: ctrl),
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

      case DataEntry.pouchProduction:
        return [
          _StockBadge(stock: ctrl.stockFfMilk, label: 'FF Milk in stock'),
          const SizedBox(height: 10),
          _VendorMilkPicker(ctrl: ctrl),
          const SizedBox(height: 12),
          Row2(
            IntField(ctrl.pouchCreamOutCtrl, 'Cream Out', 'KG'),
            SnfFatField(ctrl.pouchCreamFatCtrl, 'Cream Fat'),
          ),
          const SizedBox(height: 12),
          _PouchLinePicker(ctrl: ctrl),
        ];

      case DataEntry.curdProduction:
        return [
          _StockBadge(stock: ctrl.stockFfMilk, label: 'FF Milk in stock'),
          const SizedBox(height: 10),
          _VendorMilkPicker(ctrl: ctrl),
          const SizedBox(height: 12),
          Row2(
            IntField(ctrl.curdCreamOutCtrl, 'Cream Out', 'KG'),
            SnfFatField(ctrl.curdCreamFatCtrl, 'Cream Fat'),
          ),
          const SizedBox(height: 12),
          _StockBadge(stock: ctrl.stockCurd, label: 'Curd in stock', unit: 'Matka'),
          const SizedBox(height: 10),
          IntField(ctrl.curdOutCtrl, 'Curd Out', 'Matka'),
        ];

      case DataEntry.madhusudanSale:
        return [
          _StockBadge(stock: ctrl.stockFfMilk, label: 'FF Milk in stock'),
          const SizedBox(height: 10),
          _VendorMilkPicker(ctrl: ctrl),
          const SizedBox(height: 12),
          RateField(ctrl.madhusudanRateCtrl, 'Madhusudan Rate'),
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
                Text('${entries.length} saved entr${entries.length == 1 ? 'y' : 'ies'} today',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: kNavy)),
              ]),
            ),
            ...List.generate(entries.length, (i) {
              final tx = entries[i];
              return Container(
                decoration: BoxDecoration(
                  border: i < entries.length - 1
                      ? Border(bottom: BorderSide(color: Colors.grey.shade200))
                      : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.summary,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('${tx.userName}  •  ${_fmtTime(tx.createdAt)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    });
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
