// lib/pages/pouch_type_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/pouch_type_controller.dart';
import '../models/models.dart';
import 'shared_widgets.dart';

class PouchTypePage extends StatelessWidget {
  const PouchTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(PouchTypeController());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pouch Types', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
      ),
      body: Obx(() {
        if (ctrl.isLoading.value && ctrl.pouchTypes.isEmpty) return const LoadingCenter();
        return Column(children: [
          if (ctrl.errorMessage.value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: FeedbackBanner(ctrl.errorMessage.value, isError: true),
            ),
          if (ctrl.successMessage.value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: FeedbackBanner(ctrl.successMessage.value, isError: false),
            ),
          Expanded(
            child: ctrl.pouchTypes.isEmpty
                ? const Center(child: Text('No pouch types yet. Tap + to add one.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: ctrl.pouchTypes.length,
                    itemBuilder: (_, i) => _PouchTypeCard(ctrl: ctrl, pt: ctrl.pouchTypes[i]),
                  ),
          ),
        ]);
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ctrl),
        backgroundColor: kNavy,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context, PouchTypeController ctrl) {
    final nameCtrl  = TextEditingController();
    final litreCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Pouch Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: fieldDec('Name')),
          const SizedBox(height: 12),
          TextField(controller: litreCtrl, decoration: fieldDec('Litre', suffix: 'L'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 12),
          TextField(controller: priceCtrl, decoration: fieldDec('Price', suffix: 'INR'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () async {
              final name  = nameCtrl.text.trim();
              final litre = double.tryParse(litreCtrl.text) ?? 0;
              final price = double.tryParse(priceCtrl.text) ?? 0;
              if (name.isEmpty || litre <= 0) return;
              final ok = await ctrl.savePouchType(name, litre, price);
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _PouchTypeCard extends StatelessWidget {
  final PouchTypeController ctrl;
  final PouchType pt;
  const _PouchTypeCard({required this.ctrl, required this.pt});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: kNavy.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.local_drink_outlined, color: kNavy, size: 22),
        ),
        title: Text(pt.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${pt.litre} L  |  INR ${pt.price.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!pt.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: kRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: const Text('Inactive', style: TextStyle(fontSize: 10, color: kRed)),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _showEditDialog(context),
          ),
        ]),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final nameCtrl  = TextEditingController(text: pt.name);
    final litreCtrl = TextEditingController(text: pt.litre.toString());
    final priceCtrl = TextEditingController(text: pt.price.toString());
    var active = pt.isActive;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Pouch Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: fieldDec('Name')),
            const SizedBox(height: 12),
            TextField(controller: litreCtrl, decoration: fieldDec('Litre', suffix: 'L'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            TextField(controller: priceCtrl, decoration: fieldDec('Price', suffix: 'INR'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Active', style: TextStyle(fontSize: 14)),
              value: active,
              onChanged: (v) => setState(() => active = v),
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
              onPressed: () async {
                final ok = await ctrl.updatePouchType(
                  pt.id,
                  name: nameCtrl.text.trim(),
                  litre: double.tryParse(litreCtrl.text),
                  price: double.tryParse(priceCtrl.text),
                  isActive: active ? 1 : 0,
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}

