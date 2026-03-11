// lib/controllers/pouch_pnl_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class PouchPnlRow {
  final int id;
  final String entryDate;
  final int totalCrates;
  final double revenue;
  final double cost;
  final double profit;

  const PouchPnlRow({
    required this.id,
    required this.entryDate,
    required this.totalCrates,
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  factory PouchPnlRow.fromJson(Map<String, dynamic> j) => PouchPnlRow(
    id:          int.parse(j['id'].toString()),
    entryDate:   j['entry_date'] ?? '',
    totalCrates: int.tryParse(j['total_crates'].toString()) ?? 0,
    revenue:     double.tryParse(j['revenue'].toString()) ?? 0,
    cost:        double.tryParse(j['cost'].toString()) ?? 0,
    profit:      double.tryParse(j['profit'].toString()) ?? 0,
  );
}

class PouchPnlTotals {
  final int totalCrates;
  final double revenue;
  final double cost;
  final double profit;

  const PouchPnlTotals({
    required this.totalCrates,
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  factory PouchPnlTotals.fromJson(Map<String, dynamic> j) => PouchPnlTotals(
    totalCrates: int.tryParse(j['total_crates'].toString()) ?? 0,
    revenue:     double.tryParse(j['revenue'].toString()) ?? 0,
    cost:        double.tryParse(j['cost'].toString()) ?? 0,
    profit:      double.tryParse(j['profit'].toString()) ?? 0,
  );
}

class PouchPnlController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final rows         = <PouchPnlRow>[].obs;
  final totals       = Rxn<PouchPnlTotals>();

  @override
  void onInit() {
    super.onInit();
    fetchReport();
    ever(LocationService.instance.selected, (_) => fetchReport());
  }

  Future<void> fetchReport() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    isLoading.value    = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/pouch-pnl?location_id=$locId');
    isLoading.value = false;
    if (!res.ok) { errorMessage.value = res.message ?? 'Error fetching report.'; return; }
    rows.value = (res.data['rows'] as List)
        .map((e) => PouchPnlRow.fromJson(e as Map<String, dynamic>))
        .toList();
    if (res.data['totals'] != null) {
      totals.value = PouchPnlTotals.fromJson(res.data['totals'] as Map<String, dynamic>);
    }
  }
}
