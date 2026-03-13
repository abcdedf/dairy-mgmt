// lib/pages/funds_report_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'shared_widgets.dart';
import '../controllers/funds_report_controller.dart';

class FundsReportPage extends StatefulWidget {
  const FundsReportPage({super.key});
  @override
  State<FundsReportPage> createState() => _FundsReportPageState();
}

class _FundsReportPageState extends State<FundsReportPage> {
  late final FundsReportController c;

  @override
  void initState() {
    super.initState();
    Get.delete<FundsReportController>(force: true);
    c = Get.put(FundsReportController());
  }

  @override
  void dispose() {
    Get.delete<FundsReportController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##,##0.00', 'en_IN');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Funds Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: c.fetchReport,
          ),
        ],
      ),
      body: SelectionArea(child: Obx(() {
        if (c.isLoading.value) return const LoadingCenter();
        if (c.errorMessage.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(c.errorMessage.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: c.fetchReport,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: c.fetchReport,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _MetricCard(
                icon: Icons.trending_up,
                color: const Color(0xFF1E8449),
                label: 'Funds from Sales',
                value: '₹ ${fmt.format(c.salesTotal.value)}',
              ),
              const SizedBox(height: 12),
              _MetricCard(
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF1A73E8),
                label: 'Stock Value',
                value: '₹ ${fmt.format(c.stockValue.value)}',
              ),
              const SizedBox(height: 12),
              _MetricCard(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFE74C3C),
                label: 'Total Vendor Due',
                value: '₹ ${fmt.format(c.vendorDue.value)}',
              ),
              const SizedBox(height: 16),
              _MetricCard(
                icon: Icons.account_balance_outlined,
                color: const Color(0xFF1B4F72),
                label: 'Free Cash',
                value: '₹ ${fmt.format(c.freeCash.value)}',
                isHighlighted: true,
              ),
            ],
          ),
        );
      })),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool isHighlighted;

  const _MetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return DCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(
                fontSize: isHighlighted ? 22 : 18,
                fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w700,
                color: color,
              )),
            ],
          )),
        ]),
      ),
    );
  }
}
