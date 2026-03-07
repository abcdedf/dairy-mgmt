// lib/pages/anomaly_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/anomaly_controller.dart';
import 'shared_widgets.dart';

class AnomalyPage extends StatelessWidget {
  const AnomalyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(AnomalyController());

    return Column(children: [
      Expanded(child: Obx(() {
        if (ctrl.isLoading.value) return const LoadingCenter();
        if (ctrl.errorMessage.value.isNotEmpty) {
          return EmptyState(
            icon: Icons.error_outline,
            message: ctrl.errorMessage.value,
            buttonLabel: 'Retry',
            onButton: ctrl.fetchAnomalies,
          );
        }
        if (ctrl.rows.isEmpty) {
          return EmptyState(
            icon: Icons.check_circle_outline,
            message: 'No Flow 1 records with processing found.',
            buttonLabel: 'Refresh',
            onButton: ctrl.fetchAnomalies,
          );
        }
        return RefreshIndicator(
          onRefresh: ctrl.fetchAnomalies,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ctrl.rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _AnomalyCard(row: ctrl.rows[i]),
          ),
        );
      })),
    ]);
  }
}

class _AnomalyCard extends StatelessWidget {
  final AnomalyRow row;
  const _AnomalyCard({required this.row});

  static final _dateFmt = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final accentColor = row.isAnomalous ? kRed : kGreen;

    return DCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Accent bar
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header: date + ratio badge
            Row(children: [
              Icon(Icons.calendar_today_outlined,
                  size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                _formatDate(row.entryDate),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${row.ratio.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            // Flow detail
            Row(children: [
              _metric('FF Milk Used', '${row.inputFfMilkUsedKg} KG'),
              const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              _metric('Skim', '${row.outputSkimMilkKg} KG'),
              const Text(' + ',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              _metric('Cream', '${row.outputCreamKg} KG'),
            ]),
            const SizedBox(height: 8),
            // Meta: vendor + user
            Row(children: [
              if (row.vendorName.isNotEmpty) ...[
                Icon(Icons.storefront_outlined,
                    size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(row.vendorName,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 12),
              ],
              Icon(Icons.person_outline,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Flexible(
                child: Text(row.userName,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _metric(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  String _formatDate(String iso) {
    try {
      return _dateFmt.format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }
}
