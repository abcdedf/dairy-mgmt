// lib/pages/customer_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/customer_controller.dart';
import 'shared_widgets.dart';
import 'customer_edit_page.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  late CustomerController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<CustomerController>(force: true);
    ctrl = Get.put(CustomerController());
  }

  @override
  void dispose() {
    Get.delete<CustomerController>(force: true);
    super.dispose();
  }

  void _openEdit({int? index}) async {
    final existing = index != null ? ctrl.customers[index] : null;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CustomerEditPage(ctrl: ctrl, existing: existing)),
    );
    if (result == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titleWithLocation('Manage Customers'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEdit(),
        backgroundColor: kNavy,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Obx(() {
        if (ctrl.isLoading.value) return const LoadingCenter();
        if (ctrl.customers.isEmpty) {
          return const Center(child: EmptyState(
            icon: Icons.people_outline,
            message: 'No customers yet.',
          ));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: ctrl.customers.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (_, i) => _EntityCard(
            name: ctrl.customers[i].name,
            isActive: ctrl.customers[i].isActive,
            tags: ctrl.customers[i].productIds
                .map((pid) => ctrl.products.firstWhereOrNull((p) => p.id == pid)?.name ?? '?')
                .toList(),
            locationTags: ctrl.customers[i].locationIds
                .map((lid) => ctrl.locations.firstWhereOrNull((l) => l.id == lid)?.name ?? '?')
                .toList(),
            onEdit: () => _openEdit(index: i),
          ),
        );
      }),
    );
  }
}

// Compact single-row card for customers and vendors
class _EntityCard extends StatelessWidget {
  final String name;
  final bool isActive;
  final List<String> tags;
  final List<String> locationTags;
  final VoidCallback onEdit;
  const _EntityCard({required this.name, required this.isActive, required this.tags, required this.locationTags, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          Expanded(child: Text(name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: isActive ? Colors.black87 : Colors.grey,
            ),
          )),
          const SizedBox(width: 8),
          ...tags.map((t) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _chip(t, kNavy),
          )),
          ...locationTags.map((t) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _chip(t, kGreen),
          )),
          if (!isActive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
              child: const Text('Off', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
            const SizedBox(width: 4),
          ],
          Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(fontSize: 10, color: color)),
  );
}
