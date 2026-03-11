// lib/controllers/production_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/navigation_service.dart';
import '../core/location_service.dart';
import '../models/models.dart';

// All data entry types shown in the dropdown
enum DataEntry {
  ffMilkPurchase(
      'FF Milk Purchase',       Icons.water_drop_outlined),
  ffMilkProcessing(
      'FF Milk → Cream + Skim', Icons.settings_outlined),
  pouchProduction(
      'FF Milk → Cream + Pouches', Icons.local_drink_outlined),
  creamPurchase(
      'Cream Purchase',         Icons.opacity_outlined),
  creamProcessing(
      'Cream → Butter / Ghee',  Icons.blender_outlined),
  butterPurchase(
      'Butter Purchase',        Icons.kitchen_outlined),
  butterProcessing(
      'Butter → Ghee',          Icons.local_fire_department_outlined),
  smpPurchase(
      'SMP / Protein / Culture Purchase', Icons.science_outlined),
  dahiProcessing(
      'Dahi Production',        Icons.set_meal_outlined),
  curdProduction(
      'FF Milk → Cream + Curd',  Icons.soup_kitchen_outlined),
  madhusudanSale(
      'FF Milk → Madhusudan',   Icons.sell_outlined);

  final String   label;
  final IconData icon;
  const DataEntry(this.label, this.icon);
}

// Kept for backward compatibility with NavigationService / stock page
enum DairyFlow { milkCream, creamButterGhee, butterGhee, dahi }

// Maps server-side flow keys to DataEntry enum values
const _keyToEntry = <String, DataEntry>{
  'ff_milk_purchase':   DataEntry.ffMilkPurchase,
  'ff_milk_processing': DataEntry.ffMilkProcessing,
  'pouch_production':   DataEntry.pouchProduction,
  'cream_purchase':     DataEntry.creamPurchase,
  'cream_processing':   DataEntry.creamProcessing,
  'butter_purchase':    DataEntry.butterPurchase,
  'butter_processing':  DataEntry.butterProcessing,
  'smp_purchase':       DataEntry.smpPurchase,
  'dahi_processing':    DataEntry.dahiProcessing,
  'curd_production':    DataEntry.curdProduction,
  'madhusudan_sale':    DataEntry.madhusudanSale,
};

class FlowDef {
  final String key;
  final String label;
  final int sortOrder;
  final DataEntry? entry;

  const FlowDef({required this.key, required this.label, required this.sortOrder, this.entry});

  factory FlowDef.fromJson(Map<String, dynamic> j) {
    final key = j['key'] as String;
    return FlowDef(
      key: key,
      label: j['label'] as String,
      sortOrder: int.tryParse(j['sort_order'].toString()) ?? 0,
      entry: _keyToEntry[key],
    );
  }
}

// TODO(refactor): Consider decomposing per-flow logic into separate strategy
// objects or sub-controllers when the number of flows grows or unit testing
// becomes necessary.
class ProductionController extends GetxController {
  final isVendorLoading   = true.obs;
  final vendors           = <Vendor>[].obs;
  final selectedVendorId  = RxnInt();
  final isLoading         = false.obs;
  final flowDefs          = <FlowDef>[].obs;
  final isFlowsLoading    = true.obs;
  final entryDate         = DateTime.now().obs;
  final selectedEntry     = DataEntry.ffMilkPurchase.obs;
  final errorMessage      = ''.obs;
  final successMessage    = ''.obs;

  // ── Stock badges (read-only, shown in processing forms) ───────
  final stockFfMilk  = RxnInt(); // ProductIds.ffMilk
  final stockSkimMilk= RxnInt(); // ProductIds.skimMilk
  final stockCream   = RxnInt(); // ProductIds.cream
  final stockButter  = RxnInt(); // ProductIds.butter
  final stockDahi    = RxnInt(); // ProductIds.dahi
  final stockSmp     = RxnInt(); // ProductIds.smp
  final stockProtein = RxnInt(); // ProductIds.protein
  final stockCulture = RxnInt(); // ProductIds.culture
  final stockCurd    = RxnInt(); // ProductIds.curd

  final formKey = GlobalKey<FormState>();

  // ── Flow 1: FF Milk Purchase + Processing ─────────────────────
  final ffMilkCtrl     = TextEditingController();
  final inSnfCtrl      = TextEditingController();
  final inFatCtrl      = TextEditingController();
  final rateCtrl       = TextEditingController();
  final ffMilkUsedCtrl = TextEditingController();
  final skimMilkCtrl   = TextEditingController();
  final outSkimSnfCtrl = TextEditingController();
  final creamOutCtrl   = TextEditingController();
  final creamFatCtrl   = TextEditingController();

  // ── Flow 2: Cream Purchase + Cream → Butter/Ghee ─────────────
  final creamInCtrl     = TextEditingController();
  final creamInFatCtrl  = TextEditingController();
  final creamInRateCtrl = TextEditingController();
  final creamUsedCtrl   = TextEditingController();
  final butterOutCtrl   = TextEditingController();
  final butterFatCtrl   = TextEditingController();
  final gheeOutCtrl     = TextEditingController();

  // ── Flow 3: Butter Purchase + Butter → Ghee ──────────────────
  final butterInCtrl     = TextEditingController();
  final butterInFatCtrl  = TextEditingController();
  final butterInRateCtrl = TextEditingController();
  final butterUsedCtrl   = TextEditingController();
  final gheeOut3Ctrl     = TextEditingController();

  // ── SMP / Protein / Culture Purchase ─────────────────────────
  final smpCtrl         = TextEditingController();
  final smpRateCtrl     = TextEditingController();
  final proteinCtrl     = TextEditingController();
  final proteinRateCtrl = TextEditingController();
  final cultureCtrl     = TextEditingController();
  final cultureRateCtrl = TextEditingController();

  // ── Flow 4: Dahi Processing ───────────────────────────────────
  final dahiSkimMilkCtrl  = TextEditingController();
  final dahiSmpCtrl       = TextEditingController();
  final dahiProteinCtrl   = TextEditingController(); // decimal kg
  final dahiCultureCtrl   = TextEditingController(); // decimal kg
  final dahiContainerCtrl = TextEditingController();
  final dahiSealCtrl      = TextEditingController(); // auto-mirrored from container
  final dahiOutCtrl       = TextEditingController();

  // ── Flow 5: FF Milk → Cream + Pouches ──────────────────────
  final pouchCreamOutCtrl = TextEditingController();
  final pouchCreamFatCtrl = TextEditingController();

  // ── Flow: FF Milk → Cream + Curd ──────────────────────
  final curdCreamOutCtrl = TextEditingController();
  final curdCreamFatCtrl = TextEditingController();
  final curdOutCtrl      = TextEditingController();

  // ── Madhusudan Sale ───────────────────────────────────────
  final madhusudanRateCtrl = TextEditingController();

  // ── Shared: vendor milk picker state ────────────────────────
  final milkAvailability   = <VendorMilkAvailability>[].obs;
  final isLoadingAvail     = false.obs;
  // Each entry: {'vendor_id': int, 'ff_milk_kg': int, 'ctrl': TextEditingController}
  final milkUsageRows      = <Map<String, dynamic>>[].obs;

  // ── Shared: pouch types + pouch line state ──────────────────
  final pouchTypes         = <PouchType>[].obs;
  // Each entry: {'pouch_type_id': int, 'quantity': int, 'ctrl': TextEditingController}
  final pouchLineRows      = <Map<String, dynamic>>[].obs;

  String get _date => DateFormat('yyyy-MM-dd').format(entryDate.value);

  List<TextEditingController> get _all => [
    ffMilkCtrl, inSnfCtrl, inFatCtrl, rateCtrl, ffMilkUsedCtrl,
    skimMilkCtrl, outSkimSnfCtrl, creamOutCtrl, creamFatCtrl,
    creamInCtrl, creamInFatCtrl, creamInRateCtrl,
    creamUsedCtrl, butterOutCtrl, butterFatCtrl, gheeOutCtrl,
    butterInCtrl, butterInFatCtrl, butterInRateCtrl,
    butterUsedCtrl, gheeOut3Ctrl,
    smpCtrl, smpRateCtrl, proteinCtrl, proteinRateCtrl,
    cultureCtrl, cultureRateCtrl,
    dahiSkimMilkCtrl, dahiSmpCtrl, dahiProteinCtrl, dahiCultureCtrl,
    dahiContainerCtrl, dahiSealCtrl, dahiOutCtrl,
    pouchCreamOutCtrl, pouchCreamFatCtrl,
    madhusudanRateCtrl,
    curdCreamOutCtrl, curdCreamFatCtrl, curdOutCtrl,
  ];

  Map<DataEntry, List<TextEditingController>> get _entryFields => {
    DataEntry.ffMilkPurchase:   [ffMilkCtrl, inSnfCtrl, inFatCtrl, rateCtrl],
    DataEntry.creamPurchase:    [creamInCtrl, creamInFatCtrl, creamInRateCtrl],
    DataEntry.butterPurchase:   [butterInCtrl, butterInFatCtrl, butterInRateCtrl],
    DataEntry.smpPurchase:      [smpCtrl, smpRateCtrl, proteinCtrl, proteinRateCtrl,
                                  cultureCtrl, cultureRateCtrl],
    DataEntry.ffMilkProcessing: [ffMilkUsedCtrl, skimMilkCtrl, outSkimSnfCtrl,
                                  creamOutCtrl, creamFatCtrl],
    DataEntry.creamProcessing:  [creamUsedCtrl, butterOutCtrl, butterFatCtrl,
                                  gheeOutCtrl],
    DataEntry.butterProcessing: [butterUsedCtrl, gheeOut3Ctrl],
    DataEntry.dahiProcessing:   [dahiSkimMilkCtrl, dahiSmpCtrl, dahiProteinCtrl,
                                  dahiCultureCtrl, dahiContainerCtrl,
                                  dahiSealCtrl, dahiOutCtrl],
    DataEntry.pouchProduction:  [pouchCreamOutCtrl, pouchCreamFatCtrl],
    DataEntry.curdProduction:   [curdCreamOutCtrl, curdCreamFatCtrl, curdOutCtrl],
    DataEntry.madhusudanSale:   [madhusudanRateCtrl],
  };

  // POST endpoint for writing new records.
  // creamPurchase and butterPurchase differ from their read endpoints.
  String _writeEndpointFor(DataEntry e) => switch (e) {
    DataEntry.ffMilkPurchase   => '/milk-cream',
    DataEntry.ffMilkProcessing => '/milk-cream',
    DataEntry.creamPurchase    => '/cream-input',
    DataEntry.creamProcessing  => '/cream-butter-ghee',
    DataEntry.butterPurchase   => '/butter-input',
    DataEntry.butterProcessing => '/butter-ghee',
    DataEntry.smpPurchase      => '/smp-purchase',
    DataEntry.dahiProcessing   => '/dahi',
    DataEntry.pouchProduction  => '/pouch-production',
    DataEntry.curdProduction   => '/curd-production',
    DataEntry.madhusudanSale   => '/madhusudan-sale',
  };

  @override
  void onInit() {
    super.onInit();
    final nav = NavigationService.instance;
    if (nav.pendingProductionDate != null) {
      entryDate.value = nav.pendingProductionDate!;
      nav.pendingProductionDate = null;
    }
    _loadVendors();
    _fetchPouchTypes();
    _fetchFlows();
    ever(LocationService.instance.selected, (_) {
      _loadVendors();
      _fetchStock();
      _fetchMilkAvailability();
    });
    ever(entryDate, (_) { _fetchStock(); _fetchMilkAvailability(); });
    ever(selectedEntry, (_) {
      _fetchStock();
      if (_.name == 'ffMilkProcessing' || _.name == 'pouchProduction' || _.name == 'madhusudanSale' || _.name == 'curdProduction') {
        _fetchMilkAvailability();
      }
    });
    // Mirror container count → seal count automatically
    dahiContainerCtrl.addListener(() {
      if (dahiSealCtrl.text != dahiContainerCtrl.text) {
        dahiSealCtrl.text = dahiContainerCtrl.text;
      }
    });
    _fetchStock();
  }

  @override
  void onClose() {
    for (final c in _all) { c.dispose(); }
    for (final row in milkUsageRows) { (row['ctrl'] as TextEditingController).dispose(); }
    for (final row in pouchLineRows) { (row['ctrl'] as TextEditingController).dispose(); }
    super.onClose();
  }

  Future<void> _loadVendors() async {
    isVendorLoading.value = true;
    try {
      final locId = LocationService.instance.locId;
      final path = locId != null ? '/vendors?location_id=$locId' : '/vendors';
      final res = await ApiClient.get(path);
      if (res.ok) {
        vendors.value = (res.data as List)
            .map((e) => Vendor.fromJson(e as Map<String, dynamic>))
            .toList();
        if (vendors.isNotEmpty) selectedVendorId.value = vendors.first.id;
      }
    } catch (_) {}
    isVendorLoading.value = false;
    _fetchStock();
  }

  // ── Fetch production flow definitions from server ────────────

  Future<void> _fetchFlows() async {
    isFlowsLoading.value = true;
    final res = await ApiClient.get('/production-flows');
    if (res.ok) {
      flowDefs.value = (res.data as List)
          .map((e) => FlowDef.fromJson(e as Map<String, dynamic>))
          .where((f) => f.entry != null)
          .toList();
      // If the currently selected entry is no longer in the list, reset to first
      if (flowDefs.isNotEmpty && !flowDefs.any((f) => f.entry == selectedEntry.value)) {
        selectedEntry.value = flowDefs.first.entry!;
      }
    }
    isFlowsLoading.value = false;
  }

  // ── Milk availability per vendor ──────────────────────────────

  Future<void> _fetchMilkAvailability() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    isLoadingAvail.value = true;
    final res = await ApiClient.get('/milk-availability?location_id=$locId&as_of=$_date');
    if (res.ok) {
      milkAvailability.value = (res.data as List)
          .map((e) => VendorMilkAvailability.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    isLoadingAvail.value = false;
  }

  void addMilkUsageRow() {
    milkUsageRows.add({
      'vendor_id': null as int?,
      'ff_milk_kg': 0,
      'ctrl': TextEditingController(),
    });
  }

  void removeMilkUsageRow(int index) {
    if (milkUsageRows.length > 1) {
      (milkUsageRows[index]['ctrl'] as TextEditingController).dispose();
      milkUsageRows.removeAt(index);
    }
  }

  void resetMilkUsageRows() {
    for (final row in milkUsageRows) { (row['ctrl'] as TextEditingController).dispose(); }
    milkUsageRows.clear();
    addMilkUsageRow();
  }

  // ── Pouch types ─────────────────────────────────────────────

  Future<void> _fetchPouchTypes() async {
    final res = await ApiClient.get('/pouch-types');
    if (res.ok) {
      pouchTypes.value = (res.data as List)
          .map((e) => PouchType.fromJson(e as Map<String, dynamic>))
          .where((p) => p.isActive)
          .toList();
    }
  }

  void addPouchLineRow() {
    pouchLineRows.add({
      'pouch_type_id': null as int?,
      'quantity': 0,
      'ctrl': TextEditingController(),
    });
  }

  void removePouchLineRow(int index) {
    if (pouchLineRows.length > 1) {
      (pouchLineRows[index]['ctrl'] as TextEditingController).dispose();
      pouchLineRows.removeAt(index);
    }
  }

  void resetPouchLineRows() {
    for (final row in pouchLineRows) { (row['ctrl'] as TextEditingController).dispose(); }
    pouchLineRows.clear();
    addPouchLineRow();
  }

  Future<void> refreshPouchTypes() => _fetchPouchTypes();

  // ── Fetch running stock balances for all badge products ───────

  Future<void> _fetchStock() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    final date = _date;
    final from = DateFormat('yyyy-MM-dd')
        .format(DateTime.parse(date).subtract(const Duration(days: 29)));
    final res = await ApiClient.get(
        '/stock?location_id=$locId&from=$from&to=$date');
    if (!res.ok) return;
    final dates = res.data['dates'] as List?;
    if (dates == null || dates.isEmpty) {
      stockFfMilk.value   = null;
      stockSkimMilk.value = null;
      stockCream.value    = null;
      stockButter.value   = null;
      stockDahi.value     = null;
      stockSmp.value      = null;
      stockProtein.value  = null;
      stockCulture.value  = null;
      stockCurd.value     = null;
      return;
    }
    final last   = dates.last as Map<String, dynamic>;
    final stocks = last['stocks'] as Map<String, dynamic>? ?? {};
    int? val(int id) {
      final v = stocks[id.toString()];
      return v == null ? null : num.tryParse(v.toString())?.toInt();
    }
    stockFfMilk.value   = val(ProductIds.ffMilk);
    stockSkimMilk.value = val(ProductIds.skimMilk);
    stockCream.value    = val(ProductIds.cream);
    stockButter.value   = val(ProductIds.butter);
    stockDahi.value     = val(ProductIds.dahi);
    stockSmp.value      = val(ProductIds.smp);
    stockProtein.value  = val(ProductIds.protein);
    stockCulture.value  = val(ProductIds.culture);
    stockCurd.value     = val(ProductIds.curd);
  }

  // ── Save ──────────────────────────────────────────────────────

  Future<void> save() async {
    final locId = LocationService.instance.locId;
    if (locId == null) { errorMessage.value = 'No location selected.'; return; }
    if (!(formKey.currentState?.validate() ?? false)) return;

    isLoading.value      = true;
    errorMessage.value   = '';
    successMessage.value = '';

    final endpoint = _writeEndpointFor(selectedEntry.value);
    late Map<String, dynamic> payload;

    switch (selectedEntry.value) {

      case DataEntry.ffMilkPurchase:
        final p = MilkCreamInput(
          locationId:   locId, entryDate: _date,
          ffMilkKg:     int.parse(ffMilkCtrl.text),
          snf:          double.parse(inSnfCtrl.text),
          fat:          double.parse(inFatCtrl.text),
          rate:         double.parse(rateCtrl.text),
          ffMilkUsedKg: 0,
          skimMilkKg:   0, skimSnf: 0, creamKg: 0, creamFat: 0,
        ).toJson();
        if (selectedVendorId.value != null) p['vendor_id'] = selectedVendorId.value;
        payload = p;

      case DataEntry.ffMilkProcessing:
        // Build milk_usage from vendor picker rows
        final muList = <Map<String, dynamic>>[];
        for (final row in milkUsageRows) {
          final vid = row['vendor_id'] as int?;
          final qty = int.tryParse((row['ctrl'] as TextEditingController).text) ?? 0;
          if (vid != null && qty > 0) muList.add({'vendor_id': vid, 'ff_milk_kg': qty});
        }
        if (muList.isEmpty) { errorMessage.value = 'Select at least one vendor with milk quantity.'; isLoading.value = false; return; }
        payload = {
          'location_id': locId, 'entry_date': _date,
          'input_ff_milk_kg': 0, 'input_snf': 0, 'input_fat': 0, 'input_rate': 0,
          'output_skim_milk_kg': int.parse(skimMilkCtrl.text),
          'output_skim_snf': double.parse(outSkimSnfCtrl.text),
          'output_cream_kg': int.parse(creamOutCtrl.text),
          'output_cream_fat': double.parse(creamFatCtrl.text),
          'milk_usage': muList,
        };

      case DataEntry.creamPurchase:
        final p = CreamInput(
          locationId: locId, entryDate: _date,
          creamKg:    int.parse(creamInCtrl.text),
          fat:        double.tryParse(creamInFatCtrl.text) ?? 0,
          rate:       double.tryParse(creamInRateCtrl.text) ?? 0,
        ).toJson();
        if (selectedVendorId.value != null) p['vendor_id'] = selectedVendorId.value;
        payload = p;

      case DataEntry.creamProcessing:
        payload  = CreamButterGheeOutput(
          locationId:  locId, entryDate: _date,
          creamUsedKg: int.tryParse(creamUsedCtrl.text) ?? 0,
          butterKg:    int.parse(butterOutCtrl.text),
          butterFat:   double.parse(butterFatCtrl.text),
          gheeKg:      int.parse(gheeOutCtrl.text),
        ).toJson();

      case DataEntry.butterPurchase:
        final p = ButterInput(
          locationId: locId, entryDate: _date,
          butterKg:   int.parse(butterInCtrl.text),
          fat:        double.tryParse(butterInFatCtrl.text) ?? 0,
          rate:       double.tryParse(butterInRateCtrl.text) ?? 0,
        ).toJson();
        if (selectedVendorId.value != null) p['vendor_id'] = selectedVendorId.value;
        payload = p;

      case DataEntry.butterProcessing:
        payload  = ButterGheeOutput(
          locationId:   locId, entryDate: _date,
          butterUsedKg: int.tryParse(butterUsedCtrl.text) ?? 0,
          gheeKg:       int.parse(gheeOut3Ctrl.text),
        ).toJson();

      case DataEntry.smpPurchase:
        payload  = {
          'location_id':  locId,
          'entry_date':   _date,
          'smp_bags':     double.tryParse(smpCtrl.text)     ?? 0,
          'smp_rate':     double.tryParse(smpRateCtrl.text) ?? 0,
          'protein_kg':   double.tryParse(proteinCtrl.text) ?? 0,
          'protein_rate': double.tryParse(proteinRateCtrl.text) ?? 0,
          'culture_kg':   double.tryParse(cultureCtrl.text) ?? 0,
          'culture_rate': double.tryParse(cultureRateCtrl.text) ?? 0,
        };

      case DataEntry.dahiProcessing:
        final containers = int.tryParse(dahiContainerCtrl.text) ?? 0;
        payload = DahiInput(
          locationId:           locId,
          entryDate:            _date,
          skimMilkKg:           int.tryParse(dahiSkimMilkCtrl.text) ?? 0,
          smpBags:              int.tryParse(dahiSmpCtrl.text) ?? 0,
          // FIX: cultureKg and proteinKg are now double (DB is DECIMAL(10,2))
          cultureKg:            double.tryParse(dahiCultureCtrl.text) ?? 0,
          proteinKg:            double.tryParse(dahiProteinCtrl.text) ?? 0,
          containerCount:       containers,
          sealCount:            containers, // always mirrors container count
          outputContainerCount: int.tryParse(dahiOutCtrl.text) ?? 0,
        ).toJson();

      case DataEntry.pouchProduction:
        // Build milk_usage from vendor picker rows
        final muList = <Map<String, dynamic>>[];
        for (final row in milkUsageRows) {
          final vid = row['vendor_id'] as int?;
          final qty = int.tryParse((row['ctrl'] as TextEditingController).text) ?? 0;
          if (vid != null && qty > 0) muList.add({'vendor_id': vid, 'ff_milk_kg': qty});
        }
        if (muList.isEmpty) { errorMessage.value = 'Select at least one vendor with milk quantity.'; isLoading.value = false; return; }
        // Build pouch lines
        final plList = <Map<String, dynamic>>[];
        for (final row in pouchLineRows) {
          final ptId = row['pouch_type_id'] as int?;
          final qty  = int.tryParse((row['ctrl'] as TextEditingController).text) ?? 0;
          if (ptId != null && qty > 0) plList.add({'pouch_type_id': ptId, 'crate_count': qty});
        }
        if (plList.isEmpty) { errorMessage.value = 'Add at least one pouch type with crate count.'; isLoading.value = false; return; }
        payload = {
          'location_id': locId, 'entry_date': _date,
          'output_cream_kg': int.tryParse(pouchCreamOutCtrl.text) ?? 0,
          'output_cream_fat': double.tryParse(pouchCreamFatCtrl.text) ?? 0,
          'milk_usage': muList,
          'pouch_lines': plList,
        };

      case DataEntry.curdProduction:
        final muList = <Map<String, dynamic>>[];
        for (final row in milkUsageRows) {
            final vid = row['vendor_id'] as int?;
            final qty = int.tryParse((row['ctrl'] as TextEditingController).text) ?? 0;
            if (vid != null && qty > 0) muList.add({'vendor_id': vid, 'ff_milk_kg': qty});
        }
        if (muList.isEmpty) { errorMessage.value = 'Select at least one vendor with milk quantity.'; isLoading.value = false; return; }
        payload = {
            'location_id': locId, 'entry_date': _date,
            'output_cream_kg': int.tryParse(curdCreamOutCtrl.text) ?? 0,
            'output_cream_fat': double.tryParse(curdCreamFatCtrl.text) ?? 0,
            'output_curd_matka': int.tryParse(curdOutCtrl.text) ?? 0,
            'milk_usage': muList,
        };

      case DataEntry.madhusudanSale:
        final muList = <Map<String, dynamic>>[];
        for (final row in milkUsageRows) {
          final vid = row['vendor_id'] as int?;
          final qty = int.tryParse((row['ctrl'] as TextEditingController).text) ?? 0;
          if (vid != null && qty > 0) muList.add({'vendor_id': vid, 'ff_milk_kg': qty});
        }
        if (muList.isEmpty) { errorMessage.value = 'Select at least one vendor with milk quantity.'; isLoading.value = false; return; }
        final saleRate = double.tryParse(madhusudanRateCtrl.text) ?? 0;
        if (saleRate <= 0) { errorMessage.value = 'Madhusudan Rate must be greater than 0.'; isLoading.value = false; return; }
        payload = {
          'location_id': locId, 'entry_date': _date,
          'sale_rate': saleRate,
          'milk_usage': muList,
        };
    }

    final res = await ApiClient.post(endpoint, payload);
    isLoading.value = false;
    if (res.ok) {
      for (final c in _entryFields[selectedEntry.value] ?? []) { c.clear(); }
      if (vendors.isNotEmpty) selectedVendorId.value = vendors.first.id;
      resetMilkUsageRows();
      resetPouchLineRows();
      errorMessage.value   = '';
      successMessage.value = 'Saved successfully.';
      await _fetchStock();
      await _fetchMilkAvailability();
    } else {
      errorMessage.value = res.message ?? 'Save failed.';
    }
  }

  Future<void> retryVendors() => _loadVendors();

  void pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: entryDate.value,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) entryDate.value = picked;
  }
}
