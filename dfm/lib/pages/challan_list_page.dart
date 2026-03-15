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
          return RefreshIndicator(
            onRefresh: ctrl.fetchChallans,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              itemCount: ctrl.challans.length,
              itemBuilder: (_, i) {
                final ch = ctrl.challans[i];
                final dateStr = _tryFormatDate(ch.challanDate, dateFmt);
                final totalStr = inrFmt.format(ch.total);
                final lineCount = ch.lines.length;
                final totalQty = ch.lines.fold<double>(0, (s, l) => s + l.qty);

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: ch.isPending ? () => _openForm(existing: ch) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('DC-${ch.challanNumber}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(width: 8),
                            _StatusBadge(status: ch.status),
                            const Spacer(),
                            Text(dateStr,
                                style: TextStyle(fontSize: 12,
                                    color: Colors.grey.shade600)),
                          ]),
                          const SizedBox(height: 6),
                          Text(ch.partyName,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text('$lineCount product${lineCount == 1 ? '' : 's'}, '
                                '${totalQty.toInt()} pcs',
                                style: TextStyle(fontSize: 12,
                                    color: Colors.grey.shade600)),
                            const Spacer(),
                            Text('\u20B9$totalStr',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14,
                                    color: _kTeal)),
                          ]),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // PDF button
                                InkWell(
                                  onTap: () => DocumentPdf.showChallanPdf(ch),
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.picture_as_pdf_outlined,
                                            size: 14, color: _kTeal),
                                        SizedBox(width: 4),
                                        Text('PDF',
                                            style: TextStyle(
                                                fontSize: 12, color: _kTeal)),
                                      ],
                                    ),
                                  ),
                                ),
                                if (ch.isPending) ...[
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _confirmDelete(ch),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.delete_outline,
                                              size: 14, color: kRed),
                                          const SizedBox(width: 4),
                                          Text('Delete',
                                              style: TextStyle(
                                                  fontSize: 12, color: kRed)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
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

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (isPending ? Colors.orange : kGreen).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isPending ? Colors.orange.shade800 : kGreen,
        ),
      ),
    );
  }
}
