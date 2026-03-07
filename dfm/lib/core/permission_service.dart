// lib/core/permission_service.dart
//
// Stores the permissions object received from /dairy/v1/me after login.
// This is the single source of truth for what the current user can see.
// The server drives everything — the app just reads and renders.

import '../models/models.dart';

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  List<DairyLocation> _locations  = [];
  List<String>        _pages      = [];
  bool                _canFinance = false;

  List<DairyLocation> get locations  => List.unmodifiable(_locations);
  List<String>        get pages      => List.unmodifiable(_pages);
  bool                get canFinance => _canFinance;

  bool canSeePage(String page) => _pages.contains(page);

  void load(Map<String, dynamic> permissions) {
    _locations  = (permissions['locations'] as List? ?? [])
        .map((e) => DairyLocation.fromJson(e as Map<String, dynamic>))
        .toList();
    _pages      = (permissions['pages'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    _canFinance = permissions['can_finance'] == true;
  }

  void clear() {
    _locations  = [];
    _pages      = [];
    _canFinance = false;
  }
}
