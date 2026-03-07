// lib/core/connectivity_service.dart

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

class ConnectivityService extends GetxService {
  final isOnline = true.obs;

  @override
  void onInit() {
    super.onInit();
    _check();
    Connectivity().onConnectivityChanged.listen((results) {
      isOnline.value = results.any((r) => r != ConnectivityResult.none);
    });
  }

  Future<void> _check() async {
    final results = await Connectivity().checkConnectivity();
    isOnline.value = results.any((r) => r != ConnectivityResult.none);
  }
}
