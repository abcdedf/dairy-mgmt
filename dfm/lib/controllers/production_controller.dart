// lib/controllers/production_controller.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/navigation_service.dart';
import '../core/location_service.dart';
import '../models/models.dart';
import 'transactions_controller.dart';

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
  curdProduction(
      'FF Milk → Cream + Curd',  Icons.soup_kitchen_outlined),
  madhusudanSale(
      'FF Milk → Madhusudan',   Icons.sell_outlined);

  final String   label;
  final IconData icon;
  const DataEntry(this.label, this.icon);
}

// Kept for backward compatibility with NavigationService / stock page
enum DairyFlow { milkCream, creamButterGhee, butterGhee }

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

class ProductionController extends GetxController {
  final isVendorLoading   = true.obs;
  final vendors           = <Party>[].obs;  // V4: unified parties
  final selectedVendorId  = RxnInt();       // stores party_id
  final isLoading         = false.obs;
  final flowDefs          = <FlowDef>[].obs;
  final isFlowsLoading    = true.obs;
  final entryDate         = DateTime.now().obs;
  final selectedEntry     = DataEntry.ffMilkPurchase.obs;
  final errorMessage      = ''.obs;
  final successMessage    = ''.obs;

  // ── Stock badges (read-only, shown in processing forms) ───────
  final stockFfMilk  = RxnInt();
  final stockSkimMilk= RxnInt();
  final stockCream   = RxnInt();
  final stockButter  = RxnInt();
  final stockGhee    = RxnInt();
  final stockSmp     = RxnInt();
  final stockProtein = RxnInt();
  final stockCulture = RxnInt();
  final stockCurd    = RxnInt();
  final stockMatka   = RxnInt();

  // ── Saved entries (shown below the form) ───
  final savedEntries       = <ProdTx>[].obs;
  final isLoadingEntries   = false.obs;

  // Maps DataEntry → type label strings from V4 transactions
  static const _entryTypeMap = <DataEntry, List<String>>{
    DataEntry.ffMilkPurchase:   ['FF Milk Purchase'],
    DataEntry.ffMilkProcessing: ['FF Milk Processing'],
    DataEntry.creamPurchase:    ['Cream Purchase'],
    DataEntry.creamProcessing:  ['Cream Processing'],
    DataEntry.butterPurchase:   ['Butter Purchase'],
    DataEntry.butterProcessing: ['Butter Processing'],
    DataEntry.smpPurchase:      ['Ingredient Purchase'],
    DataEntry.pouchProduction:  ['Pouch Production'],
    DataEntry.curdProduction:   ['Curd Production'],
    DataEntry.madhusudanSale:   ['Madhusudan Sale'],
  };

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

  // ── SMP / Protein / Culture / Matka Purchase ─────────────────
  final smpCtrl         = TextEditingController();
  final smpRateCtrl     = TextEditingController();
  final proteinCtrl     = TextEditingController();
  final proteinRateCtrl = TextEditingController();
  final cultureCtrl     = TextEditingController();
  final cultureRateCtrl = TextEditingController();
  final matkaCtrl       = TextEditingController();
  final matkaRateCtrl   = TextEditingController();

  // ── Flow 5: FF Milk → Cream + Pouches ──────────────────────
  final pouchCreamOutCtrl = TextEditingController();
  final pouchCreamFatCtrl = TextEditingController();

  // ── Flow: FF Milk → Cream + Curd ──────────────────────
  final curdCreamOutCtrl  = TextEditingController();
  final curdCreamFatCtrl  = TextEditingController();
  final curdOutCtrl       = TextEditingController();
  final curdSmpCtrl       = TextEditingController();
  final curdProteinCtrl   = TextEditingController();
  final curdCultureCtrl   = TextEditingController();

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
    cultureCtrl, cultureRateCtrl, matkaCtrl, matkaRateCtrl,
    pouchCreamOutCtrl, pouchCreamFatCtrl,
    madhusudanRateCtrl,
    curdCreamOutCtrl, curdCreamFatCtrl, curdOutCtrl,
    curdSmpCtrl, curdProteinCtrl, curdCultureCtrl,
  ];

  Map<DataEntry, List<TextEditingController>> get _entryFields => {
    DataEntry.ffMilkPurchase:   [ffMilkCtrl, inSnfCtrl, inFatCtrl, rateCtrl],
    DataEntry.creamPurchase:    [creamInCtrl, creamInFatCtrl, creamInRateCtrl],
    DataEntry.butterPurchase:   [butterInCtrl, butterInFatCtrl, butterInRateCtrl],
    DataEntry.smpPurchase:      [smpCtrl, smpRateCtrl, proteinCtrl, proteinRateCtrl,
                                  cultureCtrl, cultureRateCtrl, matkaCtrl, matkaRateCtrl],
    DataEntry.ffMilkProcessing: [ffMilkUsedCtrl, skimMilkCtrl, outSkimSnfCtrl,
                                  creamOutCtrl, creamFatCtrl],
    DataEntry.creamProcessing:  [creamUsedCtrl, butterOutCtrl, butterFatCtrl,
                                  gheeOutCtrl],
    DataEntry.butterProcessing: [butterUsedCtrl, gheeOut3Ctrl],
    DataEntry.pouchProduction:  [pouchCreamOutCtrl, pouchCreamFatCtrl],
    DataEntry.curdProduction:   [curdCreamOutCtrl, curdCreamFatCtrl, curdOutCtrl,
                                  curdSmpCtrl, curdProteinCtrl, curdCultureCtrl],
    DataEntry.madhusudanSale:   [madhusudanRateCtrl],
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
      _fetchSavedEntries();
    });
    ever(entryDate, (_) { _fetchStock(); _fetchMilkAvailability(); _fetchSavedEntries(); });
    ever(selectedEntry, (_) {
      _fetchStock();
      _fetchSavedEntries();
      if (_.name == 'ffMilkProcessing' || _.name == 'pouchProduction' || _.name == 'madhusudanSale' || _.name == 'curdProduction') {
        _fetchMilkAvailability();
      }
    });
    _fetchStock();
    _fetchSavedEntries();
  }

  @override
  void onClose() {
    for (final c in _all) { c.dispose(); }
    for (final row in milkUsageRows) { (row['ctrl'] as TextEditingController).dispose(); }
    for (final row in pouchLineRows) { (row['ctrl'] as TextEditingController).dispose(); }
    super.onClose();
  }

  // ── V4: Load vendors from unified parties table ────────────────

  Future<void> _loadVendors() async {
    isVendorLoading.value = true;
    try {
      final locId = LocationService.instance.locId;
      final path = locId != null
          ? '/v4/parties?party_type=vendor&location_id=$locId'
          : '/v4/parties?party_type=vendor';
      final res = await ApiClient.get(path);
      if (res.ok) {
        vendors.value = (res.data as List)
            .map((e) => Party.fromJson(e as Map<String, dynamic>))
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
      if (flowDefs.isNotEmpty && !flowDefs.any((f) => f.entry == selectedEntry.value)) {
        selectedEntry.value = flowDefs.first.entry!;
      }
    }
    isFlowsLoading.value = false;
  }

  // ── V4: Milk availability per vendor ──────────────────────────

  Future<void> _fetchMilkAvailability() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    isLoadingAvail.value = true;
    final res = await ApiClient.get('/v4/milk-availability?location_id=$locId&as_of=$_date');
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
    final res = await ApiClient.get('/pouch-products');
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

  // ── V4: Fetch running stock balances ───────────────────────────

  Future<void> _fetchStock() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    final date = _date;
    final from = DateFormat('yyyy-MM-dd')
        .format(DateTime.parse(date).subtract(const Duration(days: 29)));
    final res = await ApiClient.get(
        '/v4/stock?location_id=$locId&from=$from&to=$date');
    if (!res.ok) return;
    final dates = res.data['dates'] as List?;
    if (dates == null || dates.isEmpty) {
      stockFfMilk.value   = null;
      stockSkimMilk.value = null;
      stockCream.value    = null;
      stockButter.value   = null;
      stockGhee.value     = null;
      stockSmp.value      = null;
      stockProtein.value  = null;
      stockCulture.value  = null;
      stockCurd.value     = null;
      stockMatka.value    = null;
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
    stockGhee.value     = val(ProductIds.ghee);
    stockSmp.value      = val(ProductIds.smp);
    stockProtein.value  = val(ProductIds.protein);
    stockCulture.value  = val(ProductIds.culture);
    stockCurd.value     = val(ProductIds.curd);
    stockMatka.value    = val(11);
  }

  // ── V4: Fetch saved entries for activity history ──────────────

  Future<void> _fetchSavedEntries() async {
    final locId = LocationService.instance.locId;
    if (locId == null) return;
    isLoadingEntries.value = true;
    final to = _date;
    final from = DateFormat('yyyy-MM-dd')
        .format(entryDate.value.subtract(const Duration(days: 6)));
    final res = await ApiClient.get(
        '/v4/transactions?location_id=$locId&from=$from&to=$to');
    if (res.ok) {
      final allRows = (res.data['rows'] as List)
          .map((e) => ProdTx.fromJson(e as Map<String, dynamic>))
          .toList();
      final types = _entryTypeMap[selectedEntry.value] ?? [];
      savedEntries.value = allRows.where((r) => types.contains(r.type)).toList();
    } else {
      savedEntries.clear();
    }
    isLoadingEntries.value = false;
  }

  // ── V4: Build milk_usage list from vendor picker rows ─────────

  List<Map<String, dynamic>>? _buildMilkUsage() {
    final muList = <Map<String, dynamic>>[];
    for (final row in milkUsageRows) {
      final vid = row['vendor_id'] as int?;
      final qty = int.tryParse((row['ctrl'] as TextEditingController).text) ?? 0;
      if (vid != null && qty != 0) muList.add({'party_id': vid, 'qty': qty});
    }
    if (muList.isEmpty) {
      errorMessage.value = 'Select at least one vendor with milk quantity.';
      return null;
    }
    return muList;
  }

  // ── V4: Save ──────────────────────────────────────────────────

  Future<void> save() async {
    final locId = LocationService.instance.locId;
    if (locId == null) { errorMessage.value = 'No location selected.'; return; }
    if (!(formKey.currentState?.validate() ?? false)) return;

    isLoading.value      = true;
    errorMessage.value   = '';
    successMessage.value = '';

    late Map<String, dynamic> payload;

    switch (selectedEntry.value) {

      case DataEntry.ffMilkPurchase:
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'purchase',
          'party_id': selectedVendorId.value,
          'lines': [{
            'product_id': ProductIds.ffMilk,
            'qty': int.parse(ffMilkCtrl.text),
            'rate': double.parse(rateCtrl.text),
            'snf': double.parse(inSnfCtrl.text),
            'fat': double.parse(inFatCtrl.text),
          }],
        };

      case DataEntry.ffMilkProcessing:
        final muList = _buildMilkUsage();
        if (muList == null) { isLoading.value = false; return; }
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'processing',
          'processing_type': 'ff_milk_processing',
          'milk_usage': muList,
          'outputs': [
            {'product_id': ProductIds.skimMilk, 'qty': int.parse(skimMilkCtrl.text), 'snf': double.parse(outSkimSnfCtrl.text)},
            {'product_id': ProductIds.cream, 'qty': double.parse(creamOutCtrl.text), 'fat': double.parse(creamFatCtrl.text)},
          ],
        };

      case DataEntry.creamPurchase:
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'purchase',
          'party_id': selectedVendorId.value,
          'lines': [{
            'product_id': ProductIds.cream,
            'qty': int.parse(creamInCtrl.text),
            'rate': double.tryParse(creamInRateCtrl.text) ?? 0,
            'fat': double.tryParse(creamInFatCtrl.text) ?? 0,
          }],
        };

      case DataEntry.creamProcessing:
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'processing',
          'processing_type': 'cream_processing',
          'inputs': [
            {'product_id': ProductIds.cream, 'qty': int.tryParse(creamUsedCtrl.text) ?? 0},
          ],
          'outputs': [
            {'product_id': ProductIds.butter, 'qty': int.parse(butterOutCtrl.text), 'fat': double.parse(butterFatCtrl.text)},
            {'product_id': ProductIds.ghee, 'qty': int.parse(gheeOutCtrl.text)},
          ],
        };

      case DataEntry.butterPurchase:
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'purchase',
          'party_id': selectedVendorId.value,
          'lines': [{
            'product_id': ProductIds.butter,
            'qty': int.parse(butterInCtrl.text),
            'rate': double.tryParse(butterInRateCtrl.text) ?? 0,
            'fat': double.tryParse(butterInFatCtrl.text) ?? 0,
          }],
        };

      case DataEntry.butterProcessing:
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'processing',
          'processing_type': 'butter_processing',
          'inputs': [
            {'product_id': ProductIds.butter, 'qty': int.tryParse(butterUsedCtrl.text) ?? 0},
          ],
          'outputs': [
            {'product_id': ProductIds.ghee, 'qty': int.parse(gheeOut3Ctrl.text)},
          ],
        };

      case DataEntry.smpPurchase:
        final lines = <Map<String, dynamic>>[];
        final smpQty = double.tryParse(smpCtrl.text) ?? 0;
        if (smpQty != 0) lines.add({'product_id': ProductIds.smp, 'qty': smpQty, 'rate': double.tryParse(smpRateCtrl.text) ?? 0});
        final protQty = double.tryParse(proteinCtrl.text) ?? 0;
        if (protQty != 0) lines.add({'product_id': ProductIds.protein, 'qty': protQty, 'rate': double.tryParse(proteinRateCtrl.text) ?? 0});
        final cultQty = double.tryParse(cultureCtrl.text) ?? 0;
        if (cultQty != 0) lines.add({'product_id': ProductIds.culture, 'qty': cultQty, 'rate': double.tryParse(cultureRateCtrl.text) ?? 0});
        final matkQty = double.tryParse(matkaCtrl.text) ?? 0;
        if (matkQty != 0) lines.add({'product_id': 11, 'qty': matkQty, 'rate': double.tryParse(matkaRateCtrl.text) ?? 0});
        if (lines.isEmpty) { errorMessage.value = 'Enter at least one item.'; isLoading.value = false; return; }
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'purchase',
          'party_id': selectedVendorId.value,
          'lines': lines,
        };

      case DataEntry.pouchProduction:
        final muList = _buildMilkUsage();
        if (muList == null) { isLoading.value = false; return; }
        final plList = <Map<String, dynamic>>[];
        for (final row in pouchLineRows) {
          final ptId = row['pouch_type_id'] as int?;
          final qty  = int.tryParse((row['ctrl'] as TextEditingController).text) ?? 0;
          if (ptId != null && qty != 0) {
            final ptName = pouchTypes.firstWhereOrNull((p) => p.id == ptId)?.name ?? '';
            plList.add({'pouch_type_id': ptId, 'crate_count': qty, 'name': ptName});
          }
        }
        if (plList.isEmpty) { errorMessage.value = 'Add at least one pouch type with crate count.'; isLoading.value = false; return; }
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'processing',
          'processing_type': 'pouch_production',
          'milk_usage': muList,
          'outputs': [
            {'product_id': ProductIds.cream, 'qty': double.tryParse(pouchCreamOutCtrl.text) ?? 0, 'fat': double.tryParse(pouchCreamFatCtrl.text) ?? 0},
          ],
          'notes': jsonEncode({'pouch_lines': plList}),
        };

      case DataEntry.curdProduction:
        final muList = _buildMilkUsage();
        if (muList == null) { isLoading.value = false; return; }
        final curdQty = int.tryParse(curdOutCtrl.text) ?? 0;
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'processing',
          'processing_type': 'curd_production',
          'milk_usage': muList,
          'inputs': [
            {'product_id': ProductIds.smp, 'qty': int.tryParse(curdSmpCtrl.text) ?? 0},
            {'product_id': ProductIds.protein, 'qty': double.tryParse(curdProteinCtrl.text) ?? 0},
            {'product_id': ProductIds.culture, 'qty': double.tryParse(curdCultureCtrl.text) ?? 0},
            {'product_id': 11, 'qty': curdQty}, // Matka consumed
          ],
          'outputs': [
            {'product_id': ProductIds.cream, 'qty': double.tryParse(curdCreamOutCtrl.text) ?? 0, 'fat': double.tryParse(curdCreamFatCtrl.text) ?? 0},
            {'product_id': ProductIds.curd, 'qty': curdQty},
          ],
        };

      case DataEntry.madhusudanSale:
        final muList = _buildMilkUsage();
        if (muList == null) { isLoading.value = false; return; }
        final saleRate = double.tryParse(madhusudanRateCtrl.text) ?? 0;
        if (saleRate <= 0) { errorMessage.value = 'Madhusudan Rate must be greater than 0.'; isLoading.value = false; return; }
        payload = {
          'location_id': locId,
          'transaction_date': _date,
          'transaction_type': 'processing',
          'processing_type': 'madhusudan_sale',
          'milk_usage': muList,
          'notes': jsonEncode({'sale_rate': saleRate}),
        };
    }

    final res = await ApiClient.post('/v4/transaction', payload);
    isLoading.value = false;
    if (res.ok) {
      for (final c in _entryFields[selectedEntry.value] ?? []) { c.clear(); }
      if (vendors.isNotEmpty) selectedVendorId.value = vendors.first.id;
      resetMilkUsageRows();
      resetPouchLineRows();
      errorMessage.value   = '';
      successMessage.value = 'Saved successfully.';
      Get.showSnackbar(const GetSnackBar(
        message: 'Saved successfully.',
        duration: Duration(seconds: 2),
        snackPosition: SnackPosition.TOP,
      ));
      await _fetchStock();
      await _fetchMilkAvailability();
      await _fetchSavedEntries();
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
