// lib/controllers/anomaly_controller.dart

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';

class AnomalyRow {
  final int id;
  final String entryDate;
  final int inputFfMilkUsedKg;
  final int outputSkimMilkKg;
  final int outputCreamKg;
  final double ratio;
  final bool isAnomalous;
  final String vendorName;
  final String userName;
  final String createdAt;

  AnomalyRow({
    required this.id,
    required this.entryDate,
    required this.inputFfMilkUsedKg,
    required this.outputSkimMilkKg,
    required this.outputCreamKg,
    required this.ratio,
    required this.isAnomalous,
    required this.vendorName,
    required this.userName,
    required this.createdAt,
  });

  factory AnomalyRow.fromJson(Map<String, dynamic> j) => AnomalyRow(
        id: int.parse(j['id'].toString()),
        entryDate: j['entry_date'] ?? '',
        inputFfMilkUsedKg: int.parse(j['input_ff_milk_used_kg'].toString()),
        outputSkimMilkKg: int.parse(j['output_skim_milk_kg'].toString()),
        outputCreamKg: int.parse(j['output_cream_kg'].toString()),
        ratio: (j['ratio'] as num).toDouble(),
        isAnomalous: j['is_anomalous'] == true,
        vendorName: j['vendor_name'] ?? '',
        userName: j['user_name'] ?? '',
        createdAt: j['created_at'] ?? '',
      );
}

class AnomalyController extends GetxController {
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final rows = <AnomalyRow>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchAnomalies();
    ever(LocationService.instance.selected, (_) => fetchAnomalies());
  }

  Future<void> fetchAnomalies() async {
    final locId = LocationService.instance.locId;
    if (locId == null) {
      rows.clear();
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/anomalies?location_id=$locId');
    isLoading.value = false;
    if (res.ok) {
      rows.value = (res.data['rows'] as List)
          .map((e) => AnomalyRow.fromJson(e))
          .toList();
      debugPrint('[AnomalyController] loaded ${rows.length} rows');
    } else {
      errorMessage.value = res.message ?? 'Error loading anomalies.';
      debugPrint('[AnomalyController] fetchAnomalies failed: ${res.message}');
    }
  }
}
