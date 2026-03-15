// lib/pages/invoice_list_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/invoice_controller.dart';
import '../core/document_pdf.dart';
import 'invoice_create_page.dart';
import 'shared_widgets.dart';

const _kIndigo = Color(0xFF3949AB);

class InvoiceListPage extends StatefulWidget {
  const InvoiceListPage({super.key});
  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  late final InvoiceController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<InvoiceController>(force: true);
    ctrl = Get.put(InvoiceController());
  }

  @override
  void dispose() {
    Get.delete<InvoiceController>(force: true);
    super.dispose();
  }

  void _openCreate() async {
    final result = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => InvoiceCreatePage(ctrl: ctrl)));
    if (result == true) ctrl.fetchInvoices();
  }

  Future<void> _confirmDelete(Invoice inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Invoice'),
        content: Text('Delete INV-${inv.invoiceNumber}?\nChallans will revert to pending.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kRed, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await ctrl.deleteInvoice(inv.id);
      if (ok) {
        Get.snackbar('Deleted', 'INV-${inv.invoiceNumber} deleted. Challans reverted to pending.',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(12));
        ctrl.fetchInvoices();
      }
    }
  }

  Future<void> _togglePaid(Invoice inv) async {
    final ok = await ctrl.togglePaid(inv.id);
    if (ok) {
      final newStatus = inv.isPaid ? 'Unpaid' : 'Paid';
      Get.snackbar('Updated', 'INV-${inv.invoiceNumber} marked $newStatus.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(12));
      ctrl.fetchInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    final inrFmt  = NumberFormat('#,##,##0.00', 'en_IN');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Invoices',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.fetchInvoices,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Invoice'),
      ),
      body: Column(children: [
        ReportLocationDropdown(
          selected: ctrl.reportLocId,
          onChanged: (_) => ctrl.fetchInvoices(),
        ),
        // Status filter
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Obx(() => SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all',    label: Text('All')),
              ButtonSegment(value: 'unpaid', label: Text('Unpaid')),
              ButtonSegment(value: 'paid',   label: Text('Paid')),
            ],
            selected: {ctrl.statusFilter.value},
            onSelectionChanged: (s) {
              ctrl.statusFilter.value = s.first;
              ctrl.fetchInvoices();
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 13)),
            ),
          )),
        ),
        // List
        Expanded(child: Obx(() {
          if (ctrl.isLoading.value) return const LoadingCenter();
          if (ctrl.errorMessage.value.isNotEmpty) {
            return EmptyState(
              icon: Icons.error_outline,
              message: ctrl.errorMessage.value,
              buttonLabel: 'Retry',
              onButton: ctrl.fetchInvoices,
            );
          }
          if (ctrl.invoices.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_outlined,
              message: 'No invoices found.',
            );
          }
          return RefreshIndicator(
            onRefresh: ctrl.fetchInvoices,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              itemCount: ctrl.invoices.length,
              itemBuilder: (_, i) {
                final inv = ctrl.invoices[i];
                final dateStr = _tryFmt(inv.invoiceDate, dateFmt);
                final totalStr = inrFmt.format(inv.total);
                final challanNums = inv.challans
                    .map((c) => 'DC-${c.challanNumber}').join(', ');

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row
                        Row(children: [
                          Text('INV-${inv.invoiceNumber}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(width: 8),
                          _PaymentBadge(status: inv.paymentStatus),
                          const Spacer(),
                          Text(dateStr,
                              style: TextStyle(fontSize: 12,
                                  color: Colors.grey.shade600)),
                        ]),
                        const SizedBox(height: 6),
                        Text(inv.partyName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        // Challans
                        Row(children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Expanded(child: Text(challanNums,
                              style: TextStyle(fontSize: 11,
                                  color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis)),
                        ]),
                        const SizedBox(height: 4),
                        // Lines summary
                        if (inv.lines.isNotEmpty) ...[
                          ...inv.lines.map((l) => Padding(
                            padding: const EdgeInsets.only(left: 18, top: 2),
                            child: Text(
                              '${l.productName}: ${l.totalQty.toInt()} ${l.productUnit} × \u20B9${l.avgRate.toStringAsFixed(2)} = \u20B9${inrFmt.format(l.totalAmount)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                          )),
                          const SizedBox(height: 4),
                        ],
                        // Total + actions
                        Row(children: [
                          Text('\u20B9$totalStr',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15,
                                  color: _kIndigo)),
                          const Spacer(),
                          // PDF button
                          InkWell(
                            onTap: () => DocumentPdf.showInvoicePdf(inv),
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.picture_as_pdf_outlined,
                                    size: 14, color: _kIndigo),
                                SizedBox(width: 4),
                                Text('PDF', style: TextStyle(fontSize: 12, color: _kIndigo)),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Toggle paid
                          InkWell(
                            onTap: () => _togglePaid(inv),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(inv.isPaid ? Icons.undo : Icons.check_circle_outline,
                                    size: 14, color: inv.isPaid ? Colors.orange : kGreen),
                                const SizedBox(width: 4),
                                Text(inv.isPaid ? 'Mark Unpaid' : 'Mark Paid',
                                    style: TextStyle(fontSize: 12,
                                        color: inv.isPaid ? Colors.orange : kGreen)),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Delete
                          InkWell(
                            onTap: () => _confirmDelete(inv),
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.delete_outline, size: 14, color: kRed),
                                SizedBox(width: 4),
                                Text('Delete', style: TextStyle(fontSize: 12, color: kRed)),
                              ]),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        })),
      ]),
    );
  }

  String _tryFmt(String d, DateFormat fmt) {
    try { return fmt.format(DateTime.parse(d)); } catch (_) { return d; }
  }
}

class _PaymentBadge extends StatelessWidget {
  final String status;
  const _PaymentBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isPaid = status == 'paid';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (isPaid ? kGreen : kRed).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isPaid ? kGreen : kRed,
        ),
      ),
    );
  }
}
