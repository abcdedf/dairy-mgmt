// lib/pages/customer_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/customer_controller.dart';
import '../models/models.dart';
import 'shared_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Customers',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(context, null),
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
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _EntityCard(
            name: ctrl.customers[i].name,
            isActive: ctrl.customers[i].isActive,
            tags: ctrl.customers[i].productIds
                .map((pid) => ctrl.products.firstWhereOrNull((p) => p.id == pid)?.name ?? '?')
                .toList(),
            locationTags: ctrl.customers[i].locationIds
                .map((lid) => ctrl.locations.firstWhereOrNull((l) => l.id == lid)?.name ?? '?')
                .toList(),
            onEdit: () => _showDialog(context, ctrl.customers[i]),
          ),
        );
      }),
    );
  }

  void _showDialog(BuildContext context, Customer? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final selectedPids = <int>{...?existing?.productIds};
    final selectedLids = <int>{...?existing?.locationIds};
    final sellable = ctrl.sellableProducts;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(existing == null ? 'Add Customer' : 'Edit Customer',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: fieldDec('Customer Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                const Text('Products', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: sellable.map((p) {
                  final selected = selectedPids.contains(p.id);
                  return FilterChip(
                    label: Text(p.name, style: TextStyle(fontSize: 12, color: selected ? Colors.white : kNavy)),
                    selected: selected,
                    selectedColor: kNavy,
                    checkmarkColor: Colors.white,
                    backgroundColor: kNavy.withValues(alpha: 0.08),
                    onSelected: (val) => setDialogState(() {
                      if (val) { selectedPids.add(p.id); } else { selectedPids.remove(p.id); }
                    }),
                  );
                }).toList()),
                const SizedBox(height: 12),
                const Text('Locations', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: ctrl.locations.map((l) {
                  final selected = selectedLids.contains(l.id);
                  return FilterChip(
                    label: Text(l.name, style: TextStyle(fontSize: 12, color: selected ? Colors.white : kGreen)),
                    selected: selected,
                    selectedColor: kGreen,
                    checkmarkColor: Colors.white,
                    backgroundColor: kGreen.withValues(alpha: 0.08),
                    onSelected: (val) => setDialogState(() {
                      if (val) { selectedLids.add(l.id); } else { selectedLids.remove(l.id); }
                    }),
                  );
                }).toList()),
                Obx(() {
                  if (ctrl.errorMessage.value.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(ctrl.errorMessage.value,
                        style: const TextStyle(color: kRed, fontSize: 12)),
                  );
                }),
              ],
            )),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  final ok = await ctrl.updateCustomer(
                    existing.id, existing.name, existing.productIds.toList(), existing.locationIds.toList(),
                    isActive: !existing.isActive,
                  );
                  if (ok && ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(existing.isActive ? 'Deactivate' : 'Activate',
                    style: TextStyle(color: existing.isActive ? kRed : kGreen)),
              ),
            const Spacer(),
            TextButton(
              onPressed: () { ctrl.errorMessage.value = ''; Navigator.pop(ctx); },
              child: const Text('Cancel'),
            ),
            Obx(() => ElevatedButton(
              onPressed: ctrl.isSaving.value ? null : () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) { ctrl.errorMessage.value = 'Name is required.'; return; }
                if (selectedPids.isEmpty) { ctrl.errorMessage.value = 'Select at least one product.'; return; }
                bool ok;
                if (existing == null) {
                  ok = await ctrl.saveCustomer(name, selectedPids.toList(), selectedLids.toList());
                } else {
                  ok = await ctrl.updateCustomer(existing.id, name, selectedPids.toList(), selectedLids.toList());
                }
                if (ok && ctx.mounted) { ctrl.errorMessage.value = ''; Navigator.pop(ctx); }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(ctrl.isSaving.value ? 'Saving…' : 'Save'),
            )),
          ],
        );
      }),
    );
  }
}

// Shared card widget for customers and vendors
class _EntityCard extends StatelessWidget {
  final String name;
  final bool isActive;
  final List<String> tags;
  final List<String> locationTags;
  final VoidCallback onEdit;
  const _EntityCard({required this.name, required this.isActive, required this.tags, required this.locationTags, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: isActive ? Colors.black87 : Colors.grey,
                )),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 2, children: tags.map((t) => _chip(t, kNavy)).toList()),
                ],
                if (locationTags.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Wrap(spacing: 4, runSpacing: 2, children: locationTags.map((t) => _chip(t, kGreen)).toList()),
                ],
              ],
            )),
            if (!isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                child: const Text('Inactive', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
            const SizedBox(width: 4),
            Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}
