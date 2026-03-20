// lib/pages/challan_list_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/challan_controller.dart';
import '../core/document_pdf.dart';
import '../core/location_service.dart';
import 'challan_form_page.dart';
import 'shared_widgets.dart';

const _kTeal = Color(0xFF00695C);

class ChallanListPage extends StatefulWidget {
  const ChallanListPage({super.key});
  @override
  State<ChallanListPage> createState() => _ChallanListPageState();
}

class _ChallanListPageState extends State<ChallanListPage> {
  late final ChallanController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<ChallanController>(force: true);
    ctrl = Get.put(ChallanController());
  }

  @override
  void dispose() {
    Get.delete<ChallanController>(force: true);
    super.dispose();
  }

  void _openForm({Challan? existing}) async {
    // Pass effective location: from list dropdown, or homescreen if "All"
    final effectiveLocId = ctrl.reportLocId.value ?? LocationService.instance.locId;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ChallanFormPage(
        ctrl: ctrl,
        existing: existing,
        initialLocId: effectiveLocId,
      )),
    );
    if (result == true) ctrl.fetchChallans();
  }

  Future<void> _confirmDelete(Challan ch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Challan'),
        content: Text('Delete DC-${ch.challanNumber}? This cannot be undone.'),
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
      final ok = await ctrl.deleteChallan(ch.id);
      if (ok) {
        Get.snackbar('Deleted', 'DC-${ch.challanNumber} deleted.',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(12));
        ctrl.fetchChallans();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    final inrFmt  = NumberFormat('#,##,##0.00', 'en_IN');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Delivery Challans',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.fetchChallans,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Challan'),
      ),
      body: Column(children: [
        // Location dropdown
        ReportLocationDropdown(
          selected: ctrl.reportLocId,
          onChanged: (_) => ctrl.fetchChallans(),
        ),
        // Status filter
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Obx(() => SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all',      label: Text('All')),
              ButtonSegment(value: 'pending',  label: Text('Pending')),
              ButtonSegment(value: 'invoiced', label: Text('Invoiced')),
            ],
            selected: {ctrl.statusFilter.value},
            onSelectionChanged: (s) {
              ctrl.statusFilter.value = s.first;
              ctrl.fetchChallans();
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                  const TextStyle(fontSize: 13)),
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
              onButton: ctrl.fetchChallans,
            );
          }
          if (ctrl.challans.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'No challans found.',
            );
          }
          // Sort descending by date
          final sorted = List<Challan>.from(ctrl.challans)
            ..sort((a, b) => b.challanDate.compareTo(a.challanDate));
          debugPrint('[ChallanList] ${sorted.length} challans, sorted desc by date');

          return RefreshIndicator(
            onRefresh: ctrl.fetchChallans,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, i) {
                final ch = sorted[i];
                final dateStr = _tryFormatDate(ch.challanDate, dateFmt);
                final totalStr = inrFmt.format(ch.total);
                final addr = ch.deliveryAddress ?? ch.shippingAddressSnapshot ?? '';

                return InkWell(
                  onTap: ch.isPending ? () => _openForm(existing: ch) : null,
                  child: Container(
                    color: i.isEven ? Colors.white : const Color(0xFFF8F9FA),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        // Date
                        SizedBox(width: 80, child: Text(dateStr,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                        // DC number + status
                        SizedBox(width: 90, child: Row(children: [
                          Text('DC-${ch.challanNumber}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 4),
                          _StatusDot(status: ch.status),
                        ])),
                        // Customer
                        Expanded(flex: 2, child: Text(ch.partyName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                        // Shipping address
                        Expanded(flex: 3, child: Row(children: [
                          if (addr.isNotEmpty) ...[
                            Icon(Icons.local_shipping_outlined, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                          ],
                          Expanded(child: Text(addr,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                        ])),
                        // Total
                        SizedBox(width: 90, child: Text('\u20B9$totalStr',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kTeal))),
                        // Actions
                        SizedBox(width: ch.isPending ? 100 : 36, child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (ch.isPending) InkWell(
                              onTap: () => _openForm(existing: ch),
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.edit_outlined, size: 16, color: _kTeal),
                              ),
                            ),
                            InkWell(
                              onTap: () => DocumentPdf.showChallanPdf(ch),
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.picture_as_pdf_outlined, size: 16, color: _kTeal),
                              ),
                            ),
                            if (ch.isPending) InkWell(
                              onTap: () => _confirmDelete(ch),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.delete_outline, size: 16, color: kRed),
                              ),
                            ),
                          ],
                        )),
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

  String _tryFormatDate(String d, DateFormat fmt) {
    try { return fmt.format(DateTime.parse(d)); } catch (_) { return d; }
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    return Tooltip(
      message: status.toUpperCase(),
      child: Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPending ? Colors.orange : kGreen,
        ),
      ),
    );
  }
}
