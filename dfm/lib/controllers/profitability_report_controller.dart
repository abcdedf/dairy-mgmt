// lib/controllers/profitability_report_controller.dart

import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class ProfitFlow {
  final String key;
  final String label;
  const ProfitFlow({required this.key, required this.label});
  factory ProfitFlow.fromJson(Map<String, dynamic> j) => ProfitFlow(
    key:   j['key']?.toString() ?? '',
    label: j['label']?.toString() ?? '',
  );
}

class ProfitRow {
  final String  date;
  final String? locationName;
  final String  flow;
  final String  flowLabel;
  final String  inputs;
  final String  outputs;
  final double  cost;
  final double  value;
  final double  profit;
  final double  profitPct;

  const ProfitRow({
    required this.date,
    this.locationName,
    required this.flow,
    required this.flowLabel,
    required this.inputs,
    required this.outputs,
    required this.cost,
    required this.value,
    required this.profit,
    required this.profitPct,
  });

  factory ProfitRow.fromJson(Map<String, dynamic> j) {
    double d(String k) => double.tryParse(j[k]?.toString() ?? '') ?? 0;
    return ProfitRow(
      date:         j['date']?.toString() ?? '',
      locationName: j['location_name']?.toString(),
      flow:         j['flow']?.toString() ?? '',
      flowLabel:    j['flow_label']?.toString() ?? '',
      inputs:       j['inputs']?.toString() ?? '',
      outputs:      j['outputs']?.toString() ?? '',
      cost:         d('cost'),
      value:        d('value'),
      profit:       d('profit'),
      profitPct:    d('profit_pct'),
    );
  }
}

class ProfitabilityReportController extends GetxController {
  final isLoading    = false.obs;
  final errorMessage = ''.obs;
  final rows         = <ProfitRow>[].obs;
  final flows        = <ProfitFlow>[].obs;
  final selectedFlow = ''.obs;  // '' = All
  final reportLocId  = RxnInt();

  int? _effectiveLocId() {
    final appBarLoc = LocationService.instance.selected.value;
    if (appBarLoc != null && appBarLoc.code.toLowerCase() == 'test') {
      return appBarLoc.id;
    }
    return reportLocId.value;
  }

  @override
  void onInit() {
    super.onInit();
    fetchReport();
    ever(LocationService.instance.selected, (_) {
      reportLocId.value = null;
      fetchReport();
    });
  }

  Future<void> fetchReport() async {
    isLoading.value    = true;
    errorMessage.value = '';
    try {
      final locId = _effectiveLocId();
      final params = <String>[];
      if (locId != null) params.add('location_id=$locId');
      if (selectedFlow.value.isNotEmpty) params.add('flow=${selectedFlow.value}');
      final query = params.isNotEmpty ? '?${params.join('&')}' : '';
      final res = await ApiClient.get('/profitability-report$query');
      isLoading.value = false;
      if (!res.ok) {
        errorMessage.value = res.message ?? 'Error loading profitability report.';
        return;
      }
      if (res.data['flows'] != null) {
        flows.value = (res.data['flows'] as List)
            .map((e) => ProfitFlow.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      rows.value = (res.data['rows'] as List)
          .map((e) => ProfitRow.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      isLoading.value    = false;
      errorMessage.value = 'Unexpected error loading profitability report.';
    }
  }
}
