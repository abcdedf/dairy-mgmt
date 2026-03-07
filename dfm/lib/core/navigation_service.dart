// lib/core/navigation_service.dart
//
// Lets any page request a tab switch + optional context.
// AppShell reacts via Obx; ProductionController picks up pendingDate in onInit.

import 'package:get/get.dart';

class NavigationService extends GetxService {
  static NavigationService get instance => Get.find();

  // AppShell watches this; null = no pending jump
  final jumpRequest = Rxn<_TabJumpRequest>();

  // If ProductionController isn't registered yet when the jump fires,
  // we store the date here and onInit() will pick it up.
  DateTime? pendingProductionDate;

  void jumpTo(String pageKey, {DateTime? date}) {
    if (date != null && pageKey == 'production') {
      pendingProductionDate = date;
    }
    jumpRequest.value = _TabJumpRequest(pageKey: pageKey, date: date);
  }
}

class _TabJumpRequest {
  final String   pageKey;
  final DateTime? date;
  const _TabJumpRequest({required this.pageKey, this.date});
}
