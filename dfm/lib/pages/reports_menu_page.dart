// lib/pages/reports_menu_page.dart

import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/permission_service.dart';
import 'sales_report_page.dart';
import 'vendor_purchase_report_page.dart';
import 'vendor_ledger_page.dart';
import 'cashflow_report_page.dart';
import 'profitability_report_page.dart';
import 'transactions_page.dart';
import 'stock_page.dart';
import 'stock_valuation_page.dart';
import 'pouch_stock_page.dart';
import 'cash_stock_report_page.dart';
import 'shared_widgets.dart';

/// Static registry: key → (icon, color, page builder).
/// Only these need a code change when adding a brand-new report page.
final Map<String, _ReportDef> _registry = {
  'daily_product_sales':    _ReportDef(Icons.table_chart_outlined,           const Color(0xFF1A73E8), () => const DailySalesReportPage()),
  'daily_customer_sales':   _ReportDef(Icons.receipt_outlined,               const Color(0xFF6A1B9A), () => const SalesLedgerPage()),
  'sales_transactions':     _ReportDef(Icons.receipt_outlined,               const Color(0xFF6A1B9A), () => const SalesTransactionsPage()),
  'production_transactions':_ReportDef(Icons.precision_manufacturing_outlined,const Color(0xFFE65100), () => const ProductionTransactionsPage()),
  'vendor_purchase_report': _ReportDef(Icons.local_shipping_outlined,        const Color(0xFF2E7D32), () => const VendorPurchaseReportPage()),
  'stock':                  _ReportDef(Icons.inventory_2_outlined,           const Color(0xFF455A64), () => const StockPage()),
  'vendor_ledger':          _ReportDef(Icons.account_balance_wallet_outlined,const Color(0xFF00897B), () => const VendorLedgerPage()),
  'cashflow_report':        _ReportDef(Icons.account_balance_outlined,       const Color(0xFF0D47A1), () => const CashflowReportPage()),
  'profitability_report':   _ReportDef(Icons.trending_up_outlined,           const Color(0xFF1B5E20), () => const ProfitabilityReportPage()),
  'stock_valuation':        _ReportDef(Icons.bar_chart_outlined,             const Color(0xFF6A1B9A), () => const StockValuationPage()),
  'pouch_stock':            _ReportDef(Icons.local_drink_outlined,           const Color(0xFF00838F), () => const PouchStockPage()),
  'cash_stock_report':      _ReportDef(Icons.account_balance_outlined,       const Color(0xFF4A148C), () => const CashStockReportPage()),
};

class _ReportDef {
  final IconData icon;
  final Color color;
  final Widget Function() builder;
  const _ReportDef(this.icon, this.color, this.builder);
}

class ReportsMenuPage extends StatefulWidget {
  const ReportsMenuPage({super.key});
  @override
  State<ReportsMenuPage> createState() => _ReportsMenuPageState();
}

class _ReportsMenuPageState extends State<ReportsMenuPage> {
  List<_ReportItem>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchMenu();
  }

  Future<void> _fetchMenu() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/report-menu');
      if (!res.ok) {
        setState(() { _loading = false; _error = res.message ?? 'Failed to load menu.'; });
        return;
      }
      final canFinance = PermissionService.instance.canFinance;
      final items = <_ReportItem>[];
      for (final r in (res.data as List)) {
        final m = r as Map<String, dynamic>;
        final key = m['key']?.toString() ?? '';
        final perm = m['permission']?.toString() ?? 'all';
        // Permission check: 'finance' requires canFinance
        if (perm == 'finance' && !canFinance) continue;
        final def = _registry[key];
        if (def == null) continue; // unknown key — skip
        items.add(_ReportItem(
          key: key,
          label: m['label']?.toString() ?? key,
          subtitle: m['subtitle']?.toString() ?? '',
          icon: def.icon,
          color: def.color,
          builder: def.builder,
        ));
      }
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = 'Unexpected error loading menu.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingCenter();
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        message: _error!,
        buttonLabel: 'Retry',
        onButton: _fetchMenu,
      );
    }
    final items = _items ?? [];
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.list_alt_outlined,
        message: 'No reports available.',
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth >= 900 ? 3
                 : constraints.maxWidth >= 560 ? 2
                 : 1;
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 1 ? 4.0 : 2.8,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return _ReportCard(
            icon: item.icon,
            color: item.color,
            title: item.label,
            subtitle: item.subtitle,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => item.builder())),
          );
        },
      );
    });
  }
}

class _ReportItem {
  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget Function() builder;
  const _ReportItem({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.builder,
  });
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
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            )),
          ]),
        ),
      ),
    );
  }
}
