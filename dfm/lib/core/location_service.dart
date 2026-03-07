// lib/core/location_service.dart
//
// Single source of truth for which location is currently active.
// All controllers read from here instead of managing their own selection.
// The AppBar dropdown writes here; every page reacts automatically.

import 'package:get/get.dart';
import '../models/models.dart';
import 'permission_service.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  // Reactive — controllers use ever() or just read .value
  final selected = Rxn<DairyLocation>();

  List<DairyLocation> get locations => PermissionService.instance.locations;

  int? get locId => selected.value?.id;

  // Called once after login when permissions are loaded.
  // Defaults to a location named "Test" (case-insensitive) if one exists —
  // so accidental data entry goes to Test, not a production location.
  // If no Test location exists, falls back to the first in the list.
  void init() {
    final locs = locations;
    if (locs.isEmpty) return;
    selected.value =
        locs.firstWhereOrNull(
            (l) => l.name.trim().toLowerCase() == 'test') ??
        locs.first;
  }

  void select(int? id) {
    selected.value = locations.firstWhereOrNull((l) => l.id == id);
  }

  void clear() {
    selected.value = null;
  }
}
