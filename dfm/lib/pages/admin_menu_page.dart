// lib/pages/admin_menu_page.dart

import 'package:flutter/material.dart';
import 'challan_list_page.dart';
import 'customer_page.dart';
import 'vendor_page.dart';
import 'product_admin_page.dart';
import 'pouch_type_page.dart';
import 'report_email_page.dart';
import 'invoice_list_page.dart';

class AdminMenuPage extends StatelessWidget {
  const AdminMenuPage({super.key});

  static const _items = <_AdminItem>[
    _AdminItem(
      icon: Icons.people_outlined,
      color: Color(0xFF37474F),
      title: 'Manage Customers',
      subtitle: 'Add, edit customers — assign products and locations',
    ),
    _AdminItem(
      icon: Icons.local_shipping_outlined,
      color: Color(0xFF2E7D32),
      title: 'Manage Vendors',
      subtitle: 'Add, edit vendors — assign locations',
    ),
    _AdminItem(
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF1A73E8),
      title: 'Manage Products',
      subtitle: 'Edit product names, units and estimated rates',
    ),
    _AdminItem(
      icon: Icons.local_drink_outlined,
      color: Color(0xFF795548),
      title: 'Pouch Types',
      subtitle: 'Manage pouch types — name, litre, price',
    ),
    _AdminItem(
      icon: Icons.receipt_long_outlined,
      color: Color(0xFF00695C),
      title: 'Delivery Challans',
      subtitle: 'Create and manage delivery challans for customers',
    ),
    _AdminItem(
      icon: Icons.receipt_outlined,
      color: Color(0xFF3949AB),
      title: 'Invoices',
      subtitle: 'Generate invoices from delivery challans — track payments',
    ),
    _AdminItem(
      icon: Icons.email_outlined,
      color: Color(0xFF6A1B9A),
      title: 'Email Schedules',
      subtitle: 'Configure automated report emails — recipients, frequency, timing',
    ),
  ];

  static final _builders = <int, Widget Function()>{
    0: () => const CustomerPage(),
    1: () => const VendorPage(),
    2: () => const ProductAdminPage(),
    3: () => const PouchTypePage(),
    4: () => const ChallanListPage(),
    5: () => const InvoiceListPage(),
    6: () => const ReportEmailPage(),
  };

  @override
  Widget build(BuildContext context) {
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
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          return _AdminCard(
            icon: item.icon,
            color: item.color,
            title: item.title,
            subtitle: item.subtitle,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => _builders[i]!())),
          );
        },
      );
    });
  }
}

class _AdminItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _AdminItem({required this.icon, required this.color,
      required this.title, required this.subtitle});
}

class _AdminCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AdminCard({required this.icon, required this.color,
      required this.title, required this.subtitle, required this.onTap});

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
