// lib/pages/customer_edit_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/customer_controller.dart';
import '../models/models.dart';
import 'shared_widgets.dart';

class CustomerEditPage extends StatefulWidget {
  final CustomerController ctrl;
  final Customer? existing;
  const CustomerEditPage({super.key, required this.ctrl, this.existing});

  @override
  State<CustomerEditPage> createState() => _CustomerEditPageState();
}

class _AddressEntry {
  int? id;
  String addressType;
  final TextEditingController labelCtrl;
  final TextEditingController textCtrl;
  bool isDefault;

  _AddressEntry({
    this.id,
    required this.addressType,
    String label = '',
    String text = '',
    this.isDefault = false,
  })  : labelCtrl = TextEditingController(text: label),
        textCtrl = TextEditingController(text: text);

  void dispose() {
    labelCtrl.dispose();
    textCtrl.dispose();
  }

  PartyAddress toModel() => PartyAddress(
    id: id ?? 0,
    addressType: addressType,
    label: labelCtrl.text.trim(),
    addressText: textCtrl.text.trim(),
    isDefault: isDefault,
  );
}

class _CustomerEditPageState extends State<CustomerEditPage> {
  late final TextEditingController _nameCtrl;
  final _selectedPids = <int>{};
  final _selectedLids = <int>{};

  // Billing address
  final _billingCtrl = TextEditingController();

  // Shipping addresses
  final _shippingEntries = <_AddressEntry>[];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    if (e != null) {
      _selectedPids.addAll(e.productIds);
      _selectedLids.addAll(e.locationIds);
      _billingCtrl.text = e.billingAddress?.addressText ?? '';
      for (final a in e.shippingAddresses) {
        _shippingEntries.add(_AddressEntry(
          id: a.id,
          addressType: 'shipping',
          label: a.label,
          text: a.addressText,
          isDefault: a.isDefault,
        ));
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _billingCtrl.dispose();
    for (final e in _shippingEntries) {
      e.dispose();
    }
    super.dispose();
  }

  List<PartyAddress> _buildAddresses() {
    final list = <PartyAddress>[];
    final billingText = _billingCtrl.text.trim();
    if (billingText.isNotEmpty) {
      list.add(PartyAddress(
        id: widget.existing?.billingAddress?.id ?? 0,
        addressType: 'billing',
        addressText: billingText,
      ));
    }
    for (final entry in _shippingEntries) {
      if (entry.textCtrl.text.trim().isNotEmpty) {
        list.add(entry.toModel());
      }
    }
    return list;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      Get.snackbar('Error', 'Name is required.',
          snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(12));
      return;
    }
    if (_selectedPids.isEmpty) {
      Get.snackbar('Error', 'Select at least one product.',
          snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(12));
      return;
    }

    final addresses = _buildAddresses();
    bool ok;
    if (_isEdit) {
      ok = await widget.ctrl.updateCustomer(
        widget.existing!.id, name,
        _selectedPids.toList(), _selectedLids.toList(),
        addresses: addresses,
      );
    } else {
      ok = await widget.ctrl.saveCustomer(
        name, _selectedPids.toList(), _selectedLids.toList(),
        addresses: addresses,
      );
    }
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _toggleActive() async {
    final e = widget.existing!;
    final ok = await widget.ctrl.updateCustomer(
      e.id, e.name, e.productIds.toList(), e.locationIds.toList(),
      isActive: !e.isActive,
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  void _addShippingAddress() {
    setState(() {
      _shippingEntries.add(_AddressEntry(addressType: 'shipping'));
    });
  }

  void _removeShippingAddress(int index) {
    setState(() {
      _shippingEntries[index].dispose();
      _shippingEntries.removeAt(index);
    });
  }

  void _setDefaultShipping(int index) {
    setState(() {
      for (int i = 0; i < _shippingEntries.length; i++) {
        _shippingEntries[i].isDefault = (i == index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sellable = widget.ctrl.sellableProducts;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Customer' : 'Add Customer',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        actions: [
          if (_isEdit)
            TextButton(
              onPressed: _toggleActive,
              child: Text(
                widget.existing!.isActive ? 'Deactivate' : 'Activate',
                style: TextStyle(
                  color: widget.existing!.isActive ? Colors.red.shade200 : Colors.green.shade200,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Name ──
                DCard(child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline, size: 18),
                  ),
                  textCapitalization: TextCapitalization.words,
                )),
                const SizedBox(height: 12),

                // ── Products ──
                DCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Products', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: sellable.map((p) {
                      final selected = _selectedPids.contains(p.id);
                      return FilterChip(
                        label: Text(p.name, style: TextStyle(fontSize: 12, color: selected ? Colors.white : kNavy)),
                        selected: selected,
                        selectedColor: kNavy,
                        checkmarkColor: Colors.white,
                        backgroundColor: kNavy.withValues(alpha: 0.08),
                        onSelected: (val) => setState(() {
                          if (val) { _selectedPids.add(p.id); } else { _selectedPids.remove(p.id); }
                        }),
                      );
                    }).toList()),
                  ],
                )),
                const SizedBox(height: 12),

                // ── Locations ──
                DCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Locations', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: widget.ctrl.locations.map((l) {
                      final selected = _selectedLids.contains(l.id);
                      return FilterChip(
                        label: Text(l.name, style: TextStyle(fontSize: 12, color: selected ? Colors.white : kGreen)),
                        selected: selected,
                        selectedColor: kGreen,
                        checkmarkColor: Colors.white,
                        backgroundColor: kGreen.withValues(alpha: 0.08),
                        onSelected: (val) => setState(() {
                          if (val) { _selectedLids.add(l.id); } else { _selectedLids.remove(l.id); }
                        }),
                      );
                    }).toList()),
                  ],
                )),
                const SizedBox(height: 12),

                // ── Billing Address ──
                DCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Billing Address', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _billingCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Enter billing address (optional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.receipt_outlined, size: 18),
                      ),
                      maxLines: 3,
                      minLines: 2,
                    ),
                  ],
                )),
                const SizedBox(height: 12),

                // ── Shipping Addresses ──
                DCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('Shipping Addresses', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addShippingAddress,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: kNavy,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ]),
                    if (_shippingEntries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('No shipping addresses added.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ),
                    ...List.generate(_shippingEntries.length, (i) {
                      final entry = _shippingEntries[i];
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: entry.isDefault ? kNavy : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: TextFormField(
                                controller: entry.labelCtrl,
                                decoration: const InputDecoration(
                                  hintText: 'Label (e.g. Warehouse A)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                style: const TextStyle(fontSize: 13),
                              )),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _setDefaultShipping(i),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: entry.isDefault ? kNavy : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Default',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: entry.isDefault ? Colors.white : Colors.grey.shade600,
                                      )),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _removeShippingAddress(i),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.delete_outline, size: 18, color: kRed),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: entry.textCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Shipping address',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              maxLines: 2,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                )),
                const SizedBox(height: 20),

                // ── Save ──
                Obx(() => SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: widget.ctrl.isSaving.value ? null : _save,
                    icon: widget.ctrl.isSaving.value
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(widget.ctrl.isSaving.value ? 'Saving...' : 'Save Customer',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kNavy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade400,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                )),

                // ── Error ──
                Obx(() {
                  if (widget.ctrl.errorMessage.value.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FeedbackBanner(widget.ctrl.errorMessage.value, isError: true),
                  );
                }),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
