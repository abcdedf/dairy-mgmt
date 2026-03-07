import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dairy_mgmt/core/api_client.dart';
import 'package:dairy_mgmt/core/permission_service.dart';
import 'package:dairy_mgmt/core/location_service.dart';
import 'package:dairy_mgmt/models/models.dart';
import 'fake_api_client.dart';

/// Sets up PermissionService with test data.
void setupPermissions({
  bool canFinance = false,
  List<String> pages = const ['production', 'sales', 'stock', 'reports'],
  List<Map<String, dynamic>> locations = const [],
}) {
  final allPages = canFinance
      ? [...pages, 'stock_valuation', 'audit_log', 'vendor_ledger', 'funds_report']
      : pages;
  PermissionService.instance.load({
    'can_finance': canFinance,
    'pages': allPages,
    'locations': locations,
  });
}

/// Sets up LocationService with a test location.
void setupLocation({int id = 99, String name = 'Test', String code = 'TEST'}) {
  setupPermissions(locations: [
    {'id': id.toString(), 'name': name, 'code': code},
  ]);
  LocationService.instance.selected.value =
      DairyLocation(id: id, name: name, code: code);
}

/// Creates a [FakeApiClient], installs it as [ApiClient.testOverride],
/// and returns it for configuring canned responses.
FakeApiClient setupFakeApi() {
  final fake = FakeApiClient();
  ApiClient.testOverride = fake;
  return fake;
}

/// Clears PermissionService, LocationService, ApiClient override, and resets GetX.
void cleanupTestState() {
  ApiClient.testOverride = null;
  LocationService.instance.clear();
  PermissionService.instance.clear();
  Get.reset();
}

/// Extension to pump a widget inside a MaterialApp scaffold.
extension PumpPage on WidgetTester {
  Future<void> pumpPage(Widget page) async {
    await pumpWidget(MaterialApp(home: Scaffold(body: page)));
  }
}
