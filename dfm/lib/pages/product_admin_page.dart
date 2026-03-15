// lib/pages/product_admin_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/product_admin_controller.dart';
import 'shared_widgets.dart';

class ProductAdminPage extends StatefulWidget {
  const ProductAdminPage({super.key});

  @override
  State<ProductAdminPage> createState() => _ProductAdminPageState();
}

class _ProductAdminPageState extends State<ProductAdminPage> {
  late ProductAdminController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<ProductAdminController>(force: true);
    ctrl = Get.put(ProductAdminController());
  }

  @override
  void dispose() {
    Get.delete<ProductAdminController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titleWithLocation('Manage Products'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
      ),
      body: Obx(() {
        if (ctrl.isLoading.value) return const LoadingCenter();
        if (ctrl.products.isEmpty) {
          return const Center(child: EmptyState(
            icon: Icons.inventory_2_outlined,
            message: 'No products.',
          ));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: ctrl.products.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final p = ctrl.products[i];
            return _ProductCard(
              product: p,
              onEdit: () => _showDialog(context, p),
            );
          },
        );
      }),
    );
  }

  void _showDialog(BuildContext context, AdminProduct product) {
    final nameCtrl = TextEditingController(text: product.name);
    final unitCtrl = TextEditingController(text: product.unit);
    final rateCtrl = TextEditingController(
        text: product.rate > 0 ? product.rate.toStringAsFixed(2) : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Edit ${product.name}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: fieldDec('Product Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: unitCtrl,
                decoration: fieldDec('Unit (KG, Matka, Bags, pcs)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: rateCtrl,
                decoration: fieldDec('Estimated Rate (INR)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              Obx(() {
                if (ctrl.errorMessage.value.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(ctrl.errorMessage.value,
                      style: const TextStyle(color: kRed, fontSize: 12)),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await ctrl.updateProduct(product.id,
                  isActive: !product.isActive);
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(product.isActive ? 'Deactivate' : 'Activate',
                style: TextStyle(color: product.isActive ? kRed : kGreen)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () { ctrl.errorMessage.value = ''; Navigator.pop(ctx); },
            child: const Text('Cancel'),
          ),
          Obx(() => ElevatedButton(
            onPressed: ctrl.isSaving.value ? null : () async {
              final name = nameCtrl.text.trim();
              final unit = unitCtrl.text.trim();
              final rate = double.tryParse(rateCtrl.text.trim());
              if (name.isEmpty) { ctrl.errorMessage.value = 'Name is required.'; return; }
              final ok = await ctrl.updateProduct(product.id,
                  name: name,
                  unit: unit.isNotEmpty ? unit : null,
                  rate: rate);
              if (ok && ctx.mounted) { ctrl.errorMessage.value = ''; Navigator.pop(ctx); }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kNavy, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(ctrl.isSaving.value ? 'Saving…' : 'Save'),
          )),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final AdminProduct product;
  final VoidCallback onEdit;
  const _ProductCard({required this.product, required this.onEdit});

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
                Text(product.name, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: product.isActive ? Colors.black87 : Colors.grey,
                )),
                const SizedBox(height: 2),
                Text('Unit: ${product.unit}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            )),
            if (product.rate > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('₹${product.rate.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kNavy)),
              ),
            if (!product.isActive) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                child: const Text('Inactive', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }
}
