// lib/pages/reports_menu_page.dart

import 'package:flutter/material.dart';
import 'sales_report_page.dart';
import 'vendor_purchase_report_page.dart';
import 'vendor_ledger_page.dart';
import 'funds_report_page.dart';
import 'transactions_page.dart';
import 'stock_page.dart';
import 'stock_valuation_page.dart';
import '../core/permission_service.dart';

class ReportsMenuPage extends StatelessWidget {
  const ReportsMenuPage({super.key});

  static bool _can(String page) => PermissionService.instance.canSeePage(page);

  @override
  Widget build(BuildContext context) {
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ReportCard(
            icon: Icons.table_chart_outlined,
            color: const Color(0xFF1A73E8),
            title: 'Daily Sales Summary',
            subtitle: 'Product-wise sales aggregated by date — last 30 days',
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const DailySalesReportPage())),
          ),
          const SizedBox(height: 12),
          _ReportCard(
            icon: Icons.receipt_outlined,
            color: const Color(0xFF6A1B9A),
            title: 'Sales Transactions',
            subtitle: 'Every sale entry with customer, qty, rate and user — last 7 days',
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const SalesTransactionsPage())),
          ),
          const SizedBox(height: 12),
          _ReportCard(
            icon: Icons.precision_manufacturing_outlined,
            color: const Color(0xFFE65100),
            title: 'Production Transactions',
            subtitle: 'All production entries with quantities and user — last 7 days',
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const ProductionTransactionsPage())),
          ),
          const SizedBox(height: 12),
          _ReportCard(
            icon: Icons.local_shipping_outlined,
            color: const Color(0xFF2E7D32),
            title: 'Vendor Purchase Report',
            subtitle: 'All purchases by vendor with product, qty, rate and amount',
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const VendorPurchaseReportPage())),
          ),
          const SizedBox(height: 12),
          _ReportCard(
            icon: Icons.inventory_2_outlined,
            color: const Color(0xFF455A64),
            title: 'Stock',
            subtitle: '30-day running stock balance across all products',
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const StockPage())),
          ),
          if (_can('vendor_ledger')) ...[
            const SizedBox(height: 12),
            _ReportCard(
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFF00897B),
              title: 'Vendor Ledger',
              subtitle: 'Payment tracking — purchases, payments and balance due per vendor',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const VendorLedgerPage())),
            ),
          ],
          if (_can('funds_report')) ...[
            const SizedBox(height: 12),
            _ReportCard(
              icon: Icons.account_balance_outlined,
              color: const Color(0xFF0D47A1),
              title: 'Funds Report',
              subtitle: 'Sales revenue, stock value, vendor dues and free cash',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const FundsReportPage())),
            ),
          ],
          if (_can('stock_valuation')) ...[
            const SizedBox(height: 12),
            _ReportCard(
              icon: Icons.bar_chart_outlined,
              color: const Color(0xFF6A1B9A),
              title: 'Stock Valuation',
              subtitle: 'Stock quantities with estimated values per product',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const StockValuationPage())),
            ),
          ],
        ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   subtitle;
  final VoidCallback onTap;

  const _ReportCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                Text(title, style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600)),
              ],
            )),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }
}
