// lib/pages/pouch_stock_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/pouch_stock_controller.dart';
import 'shared_widgets.dart';

class PouchStockPage extends StatefulWidget {
  const PouchStockPage({super.key});
  @override
  State<PouchStockPage> createState() => _PouchStockPageState();
}

class _PouchStockPageState extends State<PouchStockPage> {
  late final PouchStockController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<PouchStockController>(force: true);
    ctrl = Get.put(PouchStockController());
  }

  @override
  void dispose() {
    Get.delete<PouchStockController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pouch Stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.fetchPouchStock,
          ),
        ],
      ),
      body: Obx(() {
        if (ctrl.isLoading.value && ctrl.pouchStock.isEmpty) return const LoadingCenter();
        if (ctrl.errorMessage.value.isNotEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: FeedbackBanner(ctrl.errorMessage.value, isError: true),
          ));
        }
        if (ctrl.pouchStock.isEmpty) {
          return const Center(child: Text('No pouch stock data.'));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: DCard(
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(1.5),
                3: FlexColumnWidth(1.5),
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.05)),
                  children: const [
                    _HeaderCell('Pouch Type'),
                    _HeaderCell('L/Pouch'),
                    _HeaderCell('Per Crate'),
                    _HeaderCell('Crates'),
                  ],
                ),
                ...ctrl.pouchStock.map((row) => TableRow(children: [
                  _DataCell(row.name),
                  _DataCell(row.milkPerPouch.toString()),
                  _DataCell(row.pouchesPerCrate.toString()),
                  _DataCell(row.crateCount.toString(),
                      color: row.crateCount > 0 ? kGreen : Colors.grey),
                ])),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    child: Text(text, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700, color: kNavy)),
  );
}

class _DataCell extends StatelessWidget {
  final String text;
  final Color? color;
  const _DataCell(this.text, {this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    child: Text(text, style: TextStyle(fontSize: 13, color: color)),
  );
}
