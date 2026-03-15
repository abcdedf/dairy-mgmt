// lib/pages/shared_widgets.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../core/connectivity_service.dart';
import '../core/location_service.dart';
import '../core/permission_service.dart';
import '../models/models.dart';

// ── Colours ───────────────────────────────────────────────────
const kNavy  = Color(0xFF1B4F72);
const kGreen = Color(0xFF1E8449);
const kRed   = Color(0xFFE74C3C);

/// Appends " (Location: XXX)" to a title based on the currently selected location.
String titleWithLocation(String title) {
  final loc = LocationService.instance.selected.value;
  if (loc == null) return title;
  return '$title (${loc.name})';
}

// ── Mobile form factor wrapper ────────────────────────────────
// Wrap data-entry pages with this to cap width at 390px on wide screens.
// Report pages should NOT use this — they get full browser width.

class MobileFormFactor extends StatelessWidget {
  final Widget child;
  const MobileFormFactor({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: child,
      ),
    );
  }
}

// ── Input decoration factory ──────────────────────────────────

InputDecoration fieldDec(String label, {
  String?  suffix,
  String?  hint,
  IconData? prefixIcon,
  Widget?  suffixWidget,
  Color    accent   = kNavy,
  bool     isDense  = false,
}) {
  return InputDecoration(
    labelText:  label,
    hintText:   hint,
    suffixText: suffix,
    prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
    suffixIcon: suffixWidget,
    isDense:    isDense,
    contentPadding: isDense
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kRed)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kRed, width: 1.5)),
    filled: true, fillColor: const Color(0xFFFAFBFC),
    labelStyle: const TextStyle(fontSize: 13),
    floatingLabelStyle: TextStyle(color: accent, fontSize: 13),
  );
}

// ── Card ──────────────────────────────────────────────────────

class DCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const DCard({required this.child, this.padding, super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

// ── Section label ─────────────────────────────────────────────

class SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const SectionLabel(this.text, {this.color = const Color(0xFF2C3E50), super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 4, height: 16,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 0.3)),
  ]);
}

// ── Feedback banner ───────────────────────────────────────────

class FeedbackBanner extends StatelessWidget {
  final String message;
  final bool isError;
  const FeedbackBanner(this.message, {required this.isError, super.key});

  @override
  Widget build(BuildContext context) {
    final c  = isError ? kRed   : kGreen;
    final bg = isError ? const Color(0xFFFDECEC) : const Color(0xFFE8F8F0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg,
          border: Border.all(color: c), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
            color: c, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

// ── Offline banner ────────────────────────────────────────────

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = Get.find<ConnectivityService>();
    return Obx(() => conn.isOnline.value
        ? const SizedBox.shrink()
        : Container(
            width: double.infinity,
            color: const Color(0xFF2C3E50),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: const Row(children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 15),
              SizedBox(width: 8),
              Expanded(child: Text('No internet connection',
                  style: TextStyle(color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w500))),
            ]),
          ));
  }
}

// ── Two-column row ────────────────────────────────────────────

class Row2 extends StatelessWidget {
  final Widget a, b;
  const Row2(this.a, this.b, {super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: a), const SizedBox(width: 12), Expanded(child: b),
  ]);
}

// ── Whole-number field ────────────────────────────────────────

class IntField extends StatelessWidget {
  final TextEditingController controller;
  final String label, unit;
  final String? hint;
  final int maxDigits;
  final bool optional;
  const IntField(this.controller, this.label, this.unit,
      {this.hint, this.maxDigits = 6, this.optional = false, super.key});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(signed: true),
    maxLength: maxDigits,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
    decoration: fieldDec(label, suffix: unit.isNotEmpty ? unit : null,
        hint: hint ?? (optional ? '0 (optional)' : null))
        .copyWith(counterText: ''),
    validator: (v) {
      if (optional && (v == null || v.trim().isEmpty)) return null;
      if (v == null || v.trim().isEmpty) return 'Required';
      if (int.tryParse(v) == null) return 'Whole number';
      return null;
    },
  );
}

// ── SNF / Fat field (1 decimal, < 10) ────────────────────────

class SnfFatField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const SnfFatField(this.controller, this.label, {super.key});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}'))
    ],
    decoration: fieldDec(label, hint: '0.0–9.9'),
    validator: (v) {
      if (v == null || v.trim().isEmpty) return 'Required';
      final n = double.tryParse(v);
      if (n == null) return 'Invalid';
      if (n >= 10) return 'Must be < 10';
      return null;
    },
  );
}

// ── Decimal KG field (2 decimals, no upper limit) ────────────

class DecimalKgField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String unit;
  final bool optional;
  const DecimalKgField(this.controller, this.label,
      {this.unit = 'KG', this.optional = false, super.key});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}'))
    ],
    decoration: fieldDec(label, suffix: unit,
        hint: optional ? '0.00 (optional)' : '0.00'),
    validator: (v) {
      if (optional && (v == null || v.trim().isEmpty)) return null;
      if (v == null || v.trim().isEmpty) return 'Required';
      if (double.tryParse(v) == null) return 'Invalid';
      return null;
    },
  );
}

// ── Rate field (2 decimals) ───────────────────────────────────

class RateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool optional;
  const RateField(this.controller, this.label,
      {this.suffix = 'INR', this.optional = false, super.key});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}'))
    ],
    decoration: fieldDec(label, suffix: suffix,
        hint: optional ? '0.00 (optional)' : null),
    validator: (v) {
      if (optional && (v == null || v.trim().isEmpty)) return null;
      if (v == null || v.trim().isEmpty) return 'Required';
      if (double.tryParse(v) == null) return 'Invalid';
      return null;
    },
  );
}

// ── Compact cell field (sales table) ─────────────────────────

class CellField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDecimal;
  final VoidCallback? onChanged;
  const CellField(this.controller,
      {this.isDecimal = false, this.onChanged, super.key});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: isDecimal
        ? const TextInputType.numberWithOptions(signed: true, decimal: true)
        : const TextInputType.numberWithOptions(signed: true),
    inputFormatters: isDecimal
        ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}'))]
        : [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
    textAlign: TextAlign.center,
    onChanged: (_) => onChanged?.call(),
    decoration: InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kNavy)),
      filled: true, fillColor: const Color(0xFFFAFBFC),
    ),
    validator: (v) => (v == null || v.isEmpty) ? '' : null,
  );
}

// ── Loading / empty states ────────────────────────────────────

class LoadingCenter extends StatelessWidget {
  const LoadingCenter({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onButton;
  const EmptyState({required this.icon, required this.message,
      this.buttonLabel, this.onButton, super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 64, color: Colors.grey.shade400),
      const SizedBox(height: 12),
      Text(message,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
          textAlign: TextAlign.center),
      if (buttonLabel != null && onButton != null) ...[
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: onButton,
          icon: const Icon(Icons.refresh),
          label: Text(buttonLabel!),
          style: ElevatedButton.styleFrom(
              backgroundColor: kNavy, foregroundColor: Colors.white),
        ),
      ],
    ]),
  );
}

// ── Synced horizontal scroll body ─────────────────────────────
//
// Wraps [child] in a horizontal SingleChildScrollView whose controller
// is bidirectionally linked to the external [hScroll] controller.
// Used to keep a frozen header and a scrollable body in horizontal sync.

class SyncedHorizontalBody extends StatefulWidget {
  final ScrollController hScroll;
  final double gridWidth;
  final Widget child;

  const SyncedHorizontalBody({
    required this.hScroll,
    required this.gridWidth,
    required this.child,
    super.key,
  });

  @override
  State<SyncedHorizontalBody> createState() => _SyncedHorizontalBodyState();
}

class _SyncedHorizontalBodyState extends State<SyncedHorizontalBody> {
  final _bodyHScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _bodyHScroll.addListener(() {
      if (!widget.hScroll.hasClients) return;
      if (_bodyHScroll.offset != widget.hScroll.offset) {
        widget.hScroll.jumpTo(_bodyHScroll.offset);
      }
    });
    widget.hScroll.addListener(() {
      if (!_bodyHScroll.hasClients) return;
      if (widget.hScroll.offset != _bodyHScroll.offset) {
        _bodyHScroll.jumpTo(widget.hScroll.offset);
      }
    });
  }

  @override
  void dispose() {
    _bodyHScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      controller: _bodyHScroll,
      child: SingleChildScrollView(
        controller: _bodyHScroll,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          width: widget.gridWidth,
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Report Location Dropdown ─────────────────────────────────
// Shared dropdown for reports. Shows "All" + user's non-Test locations.
// When app bar is set to Test, hides dropdown and returns Test location ID.
//
// Usage:
//   final reportLocId = RxnInt();  // null = All
//   ReportLocationDropdown(selected: reportLocId, onChanged: (v) { ... })

bool get _isTestSelected {
  final loc = LocationService.instance.selected.value;
  return loc != null && loc.code.toLowerCase() == 'test';
}

List<DairyLocation> get _reportLocations =>
    PermissionService.instance.locations
        .where((l) => l.code.toLowerCase() != 'test')
        .toList();

class ReportLocationDropdown extends StatelessWidget {
  final RxnInt selected; // null = All
  final void Function(int?) onChanged;
  const ReportLocationDropdown({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // When Test is selected in app bar, don't show dropdown
    return Obx(() {
      if (_isTestSelected) return const SizedBox.shrink();
      final locs = _reportLocations;
      if (locs.isEmpty) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonFormField<int>(
          initialValue: selected.value ?? -1, // -1 = All
          decoration: const InputDecoration(
            labelText: 'Location',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            const DropdownMenuItem(value: -1, child: Text('All Locations')),
            ...locs.map((l) =>
                DropdownMenuItem(value: l.id, child: Text(l.name))),
          ],
          onChanged: (v) {
            selected.value = (v == null || v == -1) ? null : v;
            onChanged(selected.value);
          },
        ),
      );
    });
  }
}

/// Returns the effective location_id for a report API call.
/// When Test is selected in app bar, returns Test's ID.
/// Otherwise returns the dropdown selection (null = All).
int? reportLocationId(RxnInt dropdownSelection) {
  if (_isTestSelected) return LocationService.instance.locId;
  return dropdownSelection.value;
}
