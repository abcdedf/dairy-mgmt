// lib/controllers/madhusudan_pnl_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class MadhusudanPnlRow {
  final int id;
  final String entryDate;
  final int totalFfMilkKg;
  final double saleRate;
  final double revenue;
  final double cost;
  final double profit;

  const MadhusudanPnlRow({
    required this.id,
    required this.entryDate,
    required this.totalFfMilkKg,
    required this.saleRate,
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  factory MadhusudanPnlRow.fromJson(Map<String, dynamic> j) => MadhusudanPnlRow(
    id:             int.parse(j['id'].toString()),
    entryDate:      j['entry_date'] ?? '',
    totalFfMilkKg:  int.tryParse(j['total_ff_milk_kg'].toString()) ?? 0,
    saleRate:       double.tryParse(j['sale_rate'].toString()) ?? 0,
    revenue:        double.tryParse(j['revenue'].toString()) ?? 0,
    cost:           double.tryParse(j['cost'].toString()) ?? 0,
    profit:         double.tryParse(j['profit'].toString()) ?? 0,
  );
}

class MadhusudanPnlTotals {
  final int totalFfMilkKg;
  final double revenue;
  final double cost;
  final double profit;

  const MadhusudanPnlTotals({
    required this.totalFfMilkKg,
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  factory MadhusudanPnlTotals.fromJson(Map<String, dynamic> j) => MadhusudanPnlTotals(
    totalFfMilkKg: int.tryParse(j['total_ff_milk_kg'].toString()) ?? 0,
    revenue:       double.tryParse(j['revenue'].toString()) ?? 0,
    cost:          double.tryParse(j['cost'].toString()) ?? 0,
    profit:        double.tryParse(j['profit'].toString()) ?? 0,
  );
}

class MadhusudanPnlController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final rows         = <MadhusudanPnlRow>[].obs;
  final totals       = Rxn<MadhusudanPnlTotals>();

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
    final res = await ApiClient.get('/madhusudan-pnl?location_id=$locId');
    isLoading.value = false;
    if (!res.ok) { errorMessage.value = res.message ?? 'Error fetching report.'; return; }
    rows.value = (res.data['rows'] as List)
        .map((e) => MadhusudanPnlRow.fromJson(e as Map<String, dynamic>))
        .toList();
    if (res.data['totals'] != null) {
      totals.value = MadhusudanPnlTotals.fromJson(res.data['totals'] as Map<String, dynamic>);
    }
  }
}
