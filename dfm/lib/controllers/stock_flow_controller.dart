// lib/controllers/stock_flow_controller.dart

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/api_client.dart';
import '../core/location_service.dart';
import '../models/models.dart';

class StockFlowDay {
  final String date;
  final Map<int, StockFlowEntry> flows; // product_id → {in, out, current}

  const StockFlowDay({required this.date, required this.flows});

  factory StockFlowDay.fromJson(Map<String, dynamic> j) {
    final flows = <int, StockFlowEntry>{};
    (j['flows'] as Map).forEach((k, v) {
      final pid = int.parse(k.toString());
      final m = v as Map<String, dynamic>;
      flows[pid] = StockFlowEntry(
        inQty:   (m['in'] as num?)?.toInt() ?? 0,
        outQty:  (m['out'] as num?)?.toInt() ?? 0,
        current: (m['current'] as num?)?.toInt() ?? 0,
      );
    });
    return StockFlowDay(date: j['date']?.toString() ?? '', flows: flows);
  }
}

class StockFlowEntry {
  final int inQty;
  final int outQty;
  final int current;
  const StockFlowEntry({required this.inQty, required this.outQty, required this.current});
}

class StockFlowController extends GetxController {
  final isLoading    = false.obs;
  final products     = <DairyProduct>[].obs;
  final days         = <StockFlowDay>[].obs;
  final errorMessage = ''.obs;
  final reportLocId  = RxnInt();

  int? _effectiveLocId() {
    final appBarLoc = LocationService.instance.selected.value;
    if (appBarLoc != null && appBarLoc.code.toLowerCase() == 'test') {
      return appBarLoc.id;
    }
    return reportLocId.value ?? LocationService.instance.locId;
  }

  @override
  void onInit() {
    super.onInit();
    fetchStock();
    ever(LocationService.instance.selected, (_) {
      reportLocId.value = null;
      fetchStock();
    });
  }

  Future<void> fetchStock() async {
    final locId = _effectiveLocId();
    if (locId == null) return;
    isLoading.value    = true;
    errorMessage.value = '';
    final res = await ApiClient.get('/v4/stock-flow?location_id=$locId');
    isLoading.value = false;
    if (res.ok) {
      products.value = (res.data['products'] as List)
          .map((e) => DairyProduct.fromJson(e)).toList();
      days.value = (res.data['dates'] as List)
          .map((e) => StockFlowDay.fromJson(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
      if (kDebugMode) debugPrint('[StockFlowController] loaded ${days.length} days');
    } else {
      errorMessage.value = res.message ?? 'Error loading stock flow.';
    }
  }
}
