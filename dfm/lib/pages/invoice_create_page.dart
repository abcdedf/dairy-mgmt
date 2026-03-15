// lib/pages/invoice_create_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/invoice_controller.dart';
import '../controllers/challan_controller.dart';
import 'shared_widgets.dart';

const _kIndigo = Color(0xFF3949AB);

class InvoiceCreatePage extends StatefulWidget {
  final InvoiceController ctrl;
  const InvoiceCreatePage({super.key, required this.ctrl});

  @override
  State<InvoiceCreatePage> createState() => _InvoiceCreatePageState();
}

class _InvoiceCreatePageState extends State<InvoiceCreatePage> {
  final _dateFmt    = DateFormat('yyyy-MM-dd');
  final _displayFmt = DateFormat('dd MMM yyyy');
  final _inrFmt     = NumberFormat('#,##,##0.00', 'en_IN');

  late DateTime _date;
  int? _selectedCustomerId;
  final _notesCtrl = TextEditingController();

  List<Challan> _pendingChallans = [];
  final Set<int> _selectedIds = {};
  bool _loadingChallans = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _onCustomerChanged(int? customerId) async {
    setState(() {
      _selectedCustomerId = customerId;
      _pendingChallans = [];
      _selectedIds.clear();
    });
    if (customerId == null) return;

    setState(() => _loadingChallans = true);
    final challans = await widget.ctrl.fetchPendingChallans(customerId);
    setState(() {
      _pendingChallans = challans;
      _loadingChallans = false;
      // Auto-select all
      _selectedIds.addAll(challans.map((c) => c.id));
    });
  }

  double get _selectedTotal => _pendingChallans
      .where((c) => _selectedIds.contains(c.id))
      .fold(0.0, (s, c) => s + c.total);

  Future<void> _generate() async {
    if (_selectedCustomerId == null) {
      Get.snackbar('Error', 'Select a customer.',
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12));
      return;
    }
    if (_selectedIds.isEmpty) {
      Get.snackbar('Error', 'Select at least one challan.',
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12));
      return;
    }

    final ok = await widget.ctrl.createInvoice(
      partyId:     _selectedCustomerId!,
      invoiceDate: _dateFmt.format(_date),
      challanIds:  _selectedIds.toList(),
      notes:       _notesCtrl.text.trim(),
    );
    if (ok && mounted) {
      Get.snackbar('Invoice Created',
          'Invoice generated from ${_selectedIds.length} challan(s).',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(12));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challanDateFmt = DateFormat('dd MMM');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(titleWithLocation('Create Invoice'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
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
                // ── Date ──
                DCard(child: InkWell(
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
                      labelText: 'Invoice Date',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(_displayFmt.format(_date)),
                  ),
                )),
                const SizedBox(height: 12),

                // ── Customer ──
                DCard(child: DropdownButtonFormField<int>(
                  initialValue: _selectedCustomerId,
                  decoration: const InputDecoration(
                    labelText: 'Customer',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline, size: 18),
                  ),
                  isExpanded: true,
                  items: widget.ctrl.customers.map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: _onCustomerChanged,
                )),
                const SizedBox(height: 16),

                // ── Pending Challans ──
                if (_selectedCustomerId != null) ...[
                  Row(children: [
                    const Icon(Icons.receipt_long_outlined, size: 18, color: _kIndigo),
                    const SizedBox(width: 6),
                    const Text('Pending Challans',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const Spacer(),
                    if (_pendingChallans.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedIds.length == _pendingChallans.length) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds.addAll(_pendingChallans.map((c) => c.id));
                            }
                          });
                        },
                        child: Text(
                          _selectedIds.length == _pendingChallans.length
                              ? 'Deselect All' : 'Select All',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 4),

                  if (_loadingChallans)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_pendingChallans.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Center(child: Text(
                          'No pending challans for this customer.',
                          style: TextStyle(color: Colors.grey.shade500))),
                    )
                  else ...[
                    ...List.generate(_pendingChallans.length, (i) {
                      final ch = _pendingChallans[i];
                      final isSelected = _selectedIds.contains(ch.id);
                      final dateStr = _tryFmt(ch.challanDate, challanDateFmt);
                      final linesSummary = ch.lines
                          .map((l) => '${l.productName} ${l.qty.toInt()}')
                          .join(', ');

                      return Card(
                        elevation: isSelected ? 2 : 0,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? _kIndigo : Colors.grey.shade300,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() {
                            if (isSelected) {
                              _selectedIds.remove(ch.id);
                            } else {
                              _selectedIds.add(ch.id);
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selectedIds.add(ch.id);
                                  } else {
                                    _selectedIds.remove(ch.id);
                                  }
                                }),
                                activeColor: _kIndigo,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text('DC-${ch.challanNumber}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                    const SizedBox(width: 8),
                                    Text(dateStr,
                                        style: TextStyle(fontSize: 11,
                                            color: Colors.grey.shade600)),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(linesSummary,
                                      style: TextStyle(fontSize: 11,
                                          color: Colors.grey.shade600),
                                      overflow: TextOverflow.ellipsis),
                                ],
                              )),
                              Text('\u20B9${_inrFmt.format(ch.total)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 13)),
                            ]),
                          ),
                        ),
                      );
                    }),

                    // Selected total
                    if (_selectedIds.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _kIndigo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Text('${_selectedIds.length} challan(s) selected',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const Spacer(),
                          Text('\u20B9${_inrFmt.format(_selectedTotal)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16,
                                  color: _kIndigo)),
                        ]),
                      ),
                    ],
                  ],

                  const SizedBox(height: 16),

                  // ── Notes ──
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

                  const SizedBox(height: 16),

                  // ── Generate ──
                  Obx(() => SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: widget.ctrl.isSaving.value || _selectedIds.isEmpty
                          ? null : _generate,
                      icon: widget.ctrl.isSaving.value
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.receipt),
                      label: const Text('Generate Invoice',
                          style: TextStyle(fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kIndigo,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  )),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _tryFmt(String d, DateFormat fmt) {
    try { return fmt.format(DateTime.parse(d)); } catch (_) { return d; }
  }
}
