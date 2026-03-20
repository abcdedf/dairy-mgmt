// lib/pages/challan_form_page.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/challan_controller.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';
import '../models/models.dart';
import 'shared_widgets.dart';

const _kTeal = Color(0xFF00695C);

class ChallanFormPage extends StatefulWidget {
  final ChallanController ctrl;
  final Challan? existing;
  final int? initialLocId;
  const ChallanFormPage({super.key, required this.ctrl, this.existing, this.initialLocId});

  @override
  State<ChallanFormPage> createState() => _ChallanFormPageState();
}

class _ChallanFormPageState extends State<ChallanFormPage> {
  final _dateFmt = DateFormat('yyyy-MM-dd');
  final _displayFmt = DateFormat('dd MMM yyyy');

  late DateTime _date;
  int? _selectedLocId;
  int? _selectedCustomerId;
  final _addressCtrl = TextEditingController();
  final _notesCtrl   = TextEditingController();
  final _lines       = <_LineItem>[];

  // Address auto-fill state
  String _billingSnapshot = '';
  List<PartyAddress> _shippingAddresses = [];
  int? _selectedShippingAddrId;
  bool _loadingAddresses = false;

  bool get _isEdit => widget.existing != null;

  /// Whether the currently selected customer has Pouch Milk (product 12) assigned.
  bool get _selectedCustomerHasPouch {
    if (_selectedCustomerId == null) return false;
    final cust = widget.ctrl.customers
        .firstWhereOrNull((c) => c.id == _selectedCustomerId);
    return cust?.hasPouch ?? false;
  }

  @override
  void initState() {
    super.initState();
    // Initialize location: edit → from challan, new → from list selection or homescreen
    final locs = LocationService.instance.locations;
    final candidateLocId = widget.initialLocId ?? LocationService.instance.locId;
    _selectedLocId = locs.any((l) => l.id == candidateLocId) ? candidateLocId : (locs.isNotEmpty ? locs.first.id : null);
    debugPrint('[ChallanForm] initState: initialLocId=${widget.initialLocId}, homeLocId=${LocationService.instance.locId}, resolved=$_selectedLocId, locs=${locs.map((l) => '${l.id}:${l.name}').join(', ')}');
    if (_isEdit) {
      final ch = widget.existing!;
      _date = DateTime.parse(ch.challanDate);
      _selectedLocId = locs.any((l) => l.id == ch.locationId) ? ch.locationId : _selectedLocId;
      _selectedCustomerId = ch.partyId;
      _addressCtrl.text = ch.deliveryAddress ?? '';
      _notesCtrl.text   = ch.notes ?? '';
      for (final l in ch.lines) {
        if (l.isPouch) {
          _lines.add(_LineItem(
            isPouch: true,
            pouchProductId: l.pouchProductId,
            qtyCtrl: TextEditingController(text: l.qty.toInt().toString()),
            rateCtrl: TextEditingController(text: l.rate.toStringAsFixed(2)),
          ));
        } else {
          _lines.add(_LineItem(
            productId: l.productId,
            qtyCtrl: TextEditingController(text: l.qty.toInt().toString()),
            rateCtrl: TextEditingController(text: l.rate.toStringAsFixed(2)),
          ));
        }
      }
    } else {
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    for (final l in _lines) {
      l.qtyCtrl.dispose();
      l.rateCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchCustomerAddresses(int partyId) async {
    setState(() {
      _loadingAddresses = true;
      _shippingAddresses = [];
      _selectedShippingAddrId = null;
    });
    try {
      final res = await ApiClient.get('/customers?all=1');
      if (res.ok) {
        final customers = (res.data as List)
            .map((e) => Customer.fromJson(e as Map<String, dynamic>))
            .toList();
        final cust = customers.firstWhereOrNull((c) => c.id == partyId);
        if (cust != null) {
          final billing = cust.billingAddress;
          final shipping = cust.shippingAddresses;
          final defaultShip = cust.defaultShippingAddress;
          debugPrint('[ChallanForm] Customer $partyId: billing=${billing?.addressText}, shipping=${shipping.length} addresses');
          setState(() {
            _billingSnapshot = billing?.addressText ?? '';
            _shippingAddresses = shipping;
            // Auto-select default shipping address
            if (defaultShip != null) {
              _selectedShippingAddrId = defaultShip.id;
              _addressCtrl.text = defaultShip.addressText;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[ChallanForm] Error fetching addresses: $e');
    }
    if (mounted) setState(() => _loadingAddresses = false);
  }

  void _addPouchLine() {
    // Find pouch products not already added
    final usedIds = _lines
        .where((l) => l.isPouch && l.pouchProductId != null)
        .map((l) => l.pouchProductId!)
        .toSet();
    final available = widget.ctrl.pouchProducts
        .where((p) => !usedIds.contains(p.id))
        .toList();
    if (available.isEmpty) {
      Get.snackbar('Info', 'All pouch products already added.',
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12));
      return;
    }
    // Show bottom sheet picker
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Select Pouch Product',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Flexible(child: ListView(
              shrinkWrap: true,
              children: available.map((pp) => ListTile(
                leading: const Icon(Icons.local_drink_outlined, color: _kTeal),
                title: Text(pp.name),
                subtitle: Text('${pp.pouchesPerCrate} pcs/crate  |  ₹${pp.crateRate.toStringAsFixed(2)}/crate',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                onTap: () {
                  Navigator.pop(context);
                  // Use customer-specific rate if available, else global
                  final rate = _selectedCustomerId != null
                      ? widget.ctrl.rateForCustomerPouch(_selectedCustomerId!, pp.id)
                      : pp.crateRate;
                  debugPrint('[ChallanForm] Pouch ${pp.name}: customer=$_selectedCustomerId rate=$rate (global=${pp.crateRate})');
                  setState(() {
                    _lines.add(_LineItem(
                      isPouch: true,
                      pouchProductId: pp.id,
                      qtyCtrl: TextEditingController(),
                      rateCtrl: TextEditingController(
                          text: rate > 0 ? rate.toStringAsFixed(2) : ''),
                    ));
                  });
                },
              )).toList(),
            )),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  void _addProductLine() {
    setState(() {
      _lines.add(_LineItem(
        qtyCtrl: TextEditingController(),
        rateCtrl: TextEditingController(),
      ));
    });
  }

  void _removeLine(int i) {
    _lines[i].qtyCtrl.dispose();
    _lines[i].rateCtrl.dispose();
    setState(() => _lines.removeAt(i));
  }

  double _lineAmount(_LineItem l) {
    final qty  = double.tryParse(l.qtyCtrl.text) ?? 0;
    final rate = double.tryParse(l.rateCtrl.text) ?? 0;
    return qty * rate;
  }

  double get _grandTotal =>
      _lines.fold(0.0, (s, l) => s + _lineAmount(l));

  Future<void> _save() async {
    if (_selectedLocId == null) {
      Get.snackbar('Error', 'Select a location.',
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12));
      return;
    }
    if (_selectedCustomerId == null) {
      Get.snackbar('Error', 'Select a customer.',
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12));
      return;
    }
    final validLines = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final qty = double.tryParse(l.qtyCtrl.text) ?? 0;
      if (qty <= 0) continue;
      final rate = double.tryParse(l.rateCtrl.text) ?? 0;
      if (l.isPouch && l.pouchProductId != null) {
        validLines.add({
          'pouch_product_id': l.pouchProductId!,
          'qty': qty,
          'rate': rate,
        });
      } else if (!l.isPouch && l.productId != null) {
        validLines.add({
          'product_id': l.productId!,
          'qty': qty,
          'rate': rate,
        });
      }
    }
    if (validLines.isEmpty) {
      Get.snackbar('Error', 'Add at least one line item.',
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12));
      return;
    }

    final deliveryAddr = _addressCtrl.text.trim();
    final ok = await widget.ctrl.saveChallan(
      locationId:              _selectedLocId!,
      partyId:                 _selectedCustomerId!,
      challanDate:             _dateFmt.format(_date),
      deliveryAddress:         deliveryAddr,
      billingAddressSnapshot:  _billingSnapshot,
      shippingAddressSnapshot: deliveryAddr,
      notes:                   _notesCtrl.text.trim(),
      lines:                   validLines,
    );
    if (ok && mounted) {
      Get.snackbar('Saved', 'Challan created successfully.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(12));
      Navigator.pop(context, true);
    }
  }

  /// Resolve pouch product name by id
  String _pouchName(int id) {
    final pp = widget.ctrl.pouchProducts.firstWhereOrNull((p) => p.id == id);
    if (pp == null) return 'Pouch #$id';
    return '${pp.name} (${pp.pouchesPerCrate}/crate)';
  }

  @override
  Widget build(BuildContext context) {
    final inrFmt = NumberFormat('#,##,##0.00', 'en_IN');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_isEdit
            ? 'DC-${widget.existing!.challanNumber}'
            : 'New Challan',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;

        // ── Left panel: header fields ──
        Widget headerPanel() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date + Location
            Row(children: [
              Expanded(child: DCard(child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(_displayFmt.format(_date)),
                ),
              ))),
              const SizedBox(width: 12),
              Expanded(child: DCard(child: DropdownButtonFormField<int>(
                value: _selectedLocId,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                ),
                isExpanded: true,
                items: LocationService.instance.locations.map((l) =>
                    DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
                onChanged: (v) => setState(() => _selectedLocId = v),
              ))),
            ]),
            const SizedBox(height: 12),

            // Customer
            DCard(child: DropdownButtonFormField<int>(
              initialValue: _selectedCustomerId,
              decoration: InputDecoration(
                labelText: 'Customer',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_outline, size: 18),
                suffixIcon: _loadingAddresses
                    ? const SizedBox(width: 16, height: 16,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ))
                    : null,
              ),
              isExpanded: true,
              items: widget.ctrl.customers.map((c) =>
                  DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) {
                setState(() => _selectedCustomerId = v);
                if (v != null) {
                  _fetchCustomerAddresses(v);
                  // Update pouch line rates for new customer
                  for (final line in _lines) {
                    if (line.isPouch && line.pouchProductId != null) {
                      final rate = widget.ctrl.rateForCustomerPouch(v, line.pouchProductId!);
                      if (rate > 0) line.rateCtrl.text = rate.toStringAsFixed(2);
                    }
                  }
                }
              },
            )),
            const SizedBox(height: 12),

            // Delivery Address
            if (_shippingAddresses.isNotEmpty) ...[
              DCard(child: DropdownButtonFormField<int>(
                value: _selectedShippingAddrId,
                decoration: const InputDecoration(
                  labelText: 'Select Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                ),
                isExpanded: true,
                items: _shippingAddresses.map((a) => DropdownMenuItem(
                  value: a.id,
                  child: Text(
                    a.label.isNotEmpty ? a.label : a.addressText,
                    overflow: TextOverflow.ellipsis,
                  ),
                )).toList(),
                onChanged: (v) {
                  final addr = _shippingAddresses.firstWhereOrNull((a) => a.id == v);
                  setState(() {
                    _selectedShippingAddrId = v;
                    if (addr != null) _addressCtrl.text = addr.addressText;
                  });
                },
              )),
              const SizedBox(height: 8),
            ],
            DCard(child: TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Delivery Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined, size: 18),
              ),
              maxLines: 2,
            )),
            const SizedBox(height: 12),

            // Notes
            DCard(child: TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes_outlined, size: 18),
              ),
              maxLines: 2,
              maxLength: 500,
            )),
          ],
        );

        // ── Right panel: line items + total + save ──
        Widget lineItemsPanel() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Line Items header with buttons
            Row(children: [
              const Icon(Icons.list_alt, size: 18, color: _kTeal),
              const SizedBox(width: 6),
              const Text('Line Items',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              if (_selectedCustomerHasPouch)
                TextButton.icon(
                  onPressed: _addPouchLine,
                  icon: const Icon(Icons.local_drink_outlined, size: 16),
                  label: const Text('Pouch', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              if (_selectedCustomerHasPouch) const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _addProductLine,
                icon: const Icon(Icons.inventory_2_outlined, size: 16),
                label: const Text('Product', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: _kTeal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ]),
            const SizedBox(height: 4),

            if (_lines.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Center(child: Text('No items added yet.',
                    style: TextStyle(color: Colors.grey.shade500))),
              ),

            ...List.generate(_lines.length, (i) {
              final line = _lines[i];
              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          line.isPouch
                              ? Icons.local_drink_outlined
                              : Icons.inventory_2_outlined,
                          size: 16, color: _kTeal,
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: line.isPouch
                            ? Text(_pouchName(line.pouchProductId!),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13))
                            : DropdownButtonFormField<int>(
                                initialValue: line.productId,
                                decoration: const InputDecoration(
                                  labelText: 'Product',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                ),
                                isExpanded: true,
                                items: widget.ctrl.products.map((p) =>
                                    DropdownMenuItem(value: p.id,
                                        child: Text(p.name,
                                            style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: (v) =>
                                    setState(() => line.productId = v),
                              ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: kRed),
                          onPressed: () => _removeLine(i),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextFormField(
                          controller: line.qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: line.isPouch ? 'Crates' : 'Qty',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          onChanged: (_) => setState(() {}),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(
                          controller: line.rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: line.isPouch ? 'Crate Rate' : 'Rate',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            prefixText: '\u20B9 ',
                          ),
                          readOnly: false,
                          onChanged: (_) => setState(() {}),
                        )),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: Text(
                            '\u20B9${inrFmt.format(_lineAmount(line))}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              );
            }),

            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Grand total
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _kTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Text('Grand Total',
                      style: TextStyle(fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const Spacer(),
                  Text('\u20B9${inrFmt.format(_grandTotal)}',
                      style: const TextStyle(fontWeight: FontWeight.w700,
                          fontSize: 16, color: _kTeal)),
                ]),
              ),
            ],

            const SizedBox(height: 16),

            // ── Save ──
            Obx(() => SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: widget.ctrl.isSaving.value ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: widget.ctrl.isSaving.value
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? 'Update Challan' : 'Save Challan',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            )),

            const SizedBox(height: 40),
          ],
        );

        // ── Responsive layout ──
        debugPrint('[ChallanForm] build: isWide=$isWide width=${constraints.maxWidth}');
        if (isWide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: headerPanel(),
                )),
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: lineItemsPanel(),
                )),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                headerPanel(),
                const SizedBox(height: 12),
                lineItemsPanel(),
              ],
            ),
          );
        }
      }),
    );
  }
}

class _LineItem {
  final bool isPouch;
  int? productId;
  int? pouchProductId;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;

  _LineItem({
    this.isPouch = false,
    this.productId,
    this.pouchProductId,
    required this.qtyCtrl,
    required this.rateCtrl,
  });
}
