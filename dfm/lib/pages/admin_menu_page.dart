// lib/pages/admin_menu_page.dart

import 'package:flutter/material.dart';
import 'customer_page.dart';
import 'vendor_page.dart';
import 'product_admin_page.dart';

class AdminMenuPage extends StatelessWidget {
  const AdminMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminCard(
          icon: Icons.people_outlined,
          color: const Color(0xFF37474F),
          title: 'Manage Customers',
          subtitle: 'Add, edit customers — assign products and locations',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CustomerPage())),
        ),
        const SizedBox(height: 12),
        _AdminCard(
          icon: Icons.local_shipping_outlined,
          color: const Color(0xFF2E7D32),
          title: 'Manage Vendors',
          subtitle: 'Add, edit vendors — assign locations',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const VendorPage())),
        ),
        const SizedBox(height: 12),
        _AdminCard(
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFF1A73E8),
          title: 'Manage Products',
          subtitle: 'Edit product names, units and estimated rates',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProductAdminPage())),
        ),
      ],
    );
  }
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
