// lib/models/models.dart

// ── Location ────────────────────────────────────────────────
class DairyLocation {
  final int id;
  final String name;
  final String code;
  const DairyLocation({required this.id, required this.name, required this.code});
  factory DairyLocation.fromJson(Map<String, dynamic> j) => DairyLocation(
    id: int.parse(j['id'].toString()), name: j['name'], code: j['code']);
}

// ── Customer ────────────────────────────────────────────────
class Customer {
  final int    id;
  final String name;
  const Customer({required this.id, required this.name});
  factory Customer.fromJson(Map<String, dynamic> j) =>
      Customer(id: int.parse(j['id'].toString()), name: j['name'].toString());
}

// ── Vendor ───────────────────────────────────────────────────
class Vendor {
  final int    id;
  final String name;
  const Vendor({required this.id, required this.name});
  factory Vendor.fromJson(Map<String, dynamic> j) =>
      Vendor(id: int.parse(j['id'].toString()), name: j['name'].toString());
}

// ── Product ─────────────────────────────────────────────────
class DairyProduct {
  final int id;
  final String name;
  final String unit;
  const DairyProduct({required this.id, required this.name, required this.unit});
  factory DairyProduct.fromJson(Map<String, dynamic> j) => DairyProduct(
    id: int.parse(j['id'].toString()), name: j['name'], unit: j['unit'] ?? 'KG');
}

// ── Product ID constants ─────────────────────────────────────
abstract class ProductIds {
  static const int ffMilk   = 1;
  static const int skimMilk = 2;
  static const int cream    = 3;
  static const int butter   = 4;
  static const int ghee     = 5;
  static const int dahi     = 6;
  static const int smp      = 7;
  static const int protein  = 8;
  static const int culture  = 9;
  static const int curd     = 10;
}

// ── Production payloads ─────────────────────────────────────

// Flow 1: FF Milk purchase + processing into Skim Milk + Cream
class MilkCreamInput {
  final int locationId; final String entryDate;
  final int ffMilkKg; final double snf; final double fat; final double rate;
  final int ffMilkUsedKg;
  final int skimMilkKg; final double skimSnf; final int creamKg; final double creamFat;
  const MilkCreamInput({
    required this.locationId,   required this.entryDate,
    required this.ffMilkKg,     required this.snf,
    required this.fat,          required this.rate,
    required this.ffMilkUsedKg,
    required this.skimMilkKg,   required this.skimSnf,
    required this.creamKg,      required this.creamFat,
  });
  Map<String, dynamic> toJson() => {
    'location_id': locationId, 'entry_date': entryDate,
    'input_ff_milk_kg': ffMilkKg, 'input_snf': snf,
    'input_fat': fat, 'input_rate': rate,
    'input_ff_milk_used_kg': ffMilkUsedKg,
    'output_skim_milk_kg': skimMilkKg, 'output_skim_snf': skimSnf,
    'output_cream_kg': creamKg, 'output_cream_fat': creamFat,
  };
}

// Flow 2 input: cream received from vendor
class CreamInput {
  final int locationId; final String entryDate;
  final int creamKg; final double fat; final double rate;
  const CreamInput({
    required this.locationId, required this.entryDate,
    required this.creamKg,    required this.fat, required this.rate,
  });
  Map<String, dynamic> toJson() => {
    'location_id': locationId, 'entry_date': entryDate,
    'input_cream_kg': creamKg, 'input_fat': fat, 'input_rate': rate,
  };
}

// Flow 2 output: cream consumed, butter + ghee produced
class CreamButterGheeOutput {
  final int locationId; final String entryDate;
  final int creamUsedKg; final int butterKg;
  final double butterFat; final int gheeKg;
  const CreamButterGheeOutput({
    required this.locationId,  required this.entryDate,
    required this.creamUsedKg, required this.butterKg,
    required this.butterFat,   required this.gheeKg,
  });
  Map<String, dynamic> toJson() => {
    'location_id': locationId, 'entry_date': entryDate,
    'input_cream_used_kg': creamUsedKg,
    'output_butter_kg': butterKg,
    'output_butter_fat': butterFat, 'output_ghee_kg': gheeKg,
  };
}

// Flow 3 input: butter received from vendor
class ButterInput {
  final int locationId; final String entryDate;
  final int butterKg; final double fat; final double rate;
  const ButterInput({
    required this.locationId, required this.entryDate,
    required this.butterKg,   required this.fat, required this.rate,
  });
  Map<String, dynamic> toJson() => {
    'location_id': locationId, 'entry_date': entryDate,
    'input_butter_kg': butterKg, 'input_fat': fat, 'input_rate': rate,
  };
}

// Flow 3 output: butter consumed, ghee produced
class ButterGheeOutput {
  final int locationId; final String entryDate;
  final int butterUsedKg; final int gheeKg;
  const ButterGheeOutput({
    required this.locationId,    required this.entryDate,
    required this.butterUsedKg,  required this.gheeKg,
  });
  Map<String, dynamic> toJson() => {
    'location_id': locationId, 'entry_date': entryDate,
    'input_butter_used_kg': butterUsedKg, 'output_ghee_kg': gheeKg,
  };
}

// Flow 4: Dahi production
// FIX: cultureKg and proteinKg changed from int → double (DB column is DECIMAL(10,2))
class DahiInput {
  final int    locationId;
  final String entryDate;
  final int    smpBags;
  final double cultureKg;   // was int — DB is DECIMAL(10,2)
  final double proteinKg;   // was int — DB is DECIMAL(10,2)
  final int    skimMilkKg;
  final int    containerCount;
  final int    sealCount;
  final int    outputContainerCount;

  const DahiInput({
    required this.locationId,           required this.entryDate,
    required this.smpBags,              required this.cultureKg,
    required this.proteinKg,            required this.skimMilkKg,
    required this.containerCount,       required this.sealCount,
    required this.outputContainerCount,
  });

  Map<String, dynamic> toJson() => {
    'location_id':            locationId,
    'entry_date':             entryDate,
    'input_smp_bags':         smpBags,
    'input_culture_kg':       cultureKg,
    'input_protein_kg':       proteinKg,
    'input_skim_milk_kg':     skimMilkKg,
    'input_container_count':  containerCount,
    'input_seal_count':       sealCount,
    'output_container_count': outputContainerCount,
  };
}

// ── Stock ────────────────────────────────────────────────────
class StockDayRow {
  final String date;
  final Map<int, int> stocks;
  final Map<int, double> values;
  final double totalValue;

  const StockDayRow({
    required this.date, required this.stocks,
    required this.values, required this.totalValue,
  });

  factory StockDayRow.fromJson(Map<String, dynamic> j) {
    final stocks = <int, int>{};
    (j['stocks'] as Map).forEach(
        (k, v) => stocks[int.parse(k.toString())] = (v as num).toInt());
    final values = <int, double>{};
    if (j['values'] != null) {
      (j['values'] as Map).forEach(
          (k, v) => values[int.parse(k.toString())] = (v as num).toDouble());
    }
    return StockDayRow(
      date:       j['date'],
      stocks:     stocks,
      values:     values,
      totalValue: (j['total_value'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ── Estimated Rate ───────────────────────────────────────────
class EstimatedRate {
  final int productId;
  final String productName;
  double rate;
  EstimatedRate({required this.productId, required this.productName, required this.rate});
  factory EstimatedRate.fromJson(Map<String, dynamic> j) => EstimatedRate(
    productId:   int.parse(j['product_id'].toString()),
    productName: j['product_name'],
    rate:        double.parse(j['rate'].toString()),
  );
}

// ── Vendor Milk Availability ─────────────────────────────────
class VendorMilkAvailability {
  final int vendorId;
  final String vendorName;
  final int availableKg;
  const VendorMilkAvailability({required this.vendorId, required this.vendorName, required this.availableKg});
  factory VendorMilkAvailability.fromJson(Map<String, dynamic> j) => VendorMilkAvailability(
    vendorId: int.parse(j['vendor_id'].toString()),
    vendorName: j['vendor_name'].toString(),
    availableKg: int.parse(j['available_kg'].toString()),
  );
}

// ── Pouch Type ──────────────────────────────────────────────
class PouchType {
  final int id;
  final String name;
  final double milkPerPouch;
  final int pouchesPerCrate;
  final bool isActive;
  const PouchType({required this.id, required this.name, required this.milkPerPouch, required this.pouchesPerCrate, required this.isActive});
  factory PouchType.fromJson(Map<String, dynamic> j) => PouchType(
    id: int.parse(j['id'].toString()),
    name: j['name'].toString(),
    milkPerPouch: double.parse((j['milk_per_pouch'] ?? j['litre'] ?? '0').toString()),
    pouchesPerCrate: int.tryParse((j['pouches_per_crate'] ?? '12').toString()) ?? 12,
    isActive: j['is_active'].toString() == '1',
  );
}

// ── Pouch Stock Row ─────────────────────────────────────────
class PouchStockRow {
  final int pouchTypeId;
  final String name;
  final double milkPerPouch;
  final int pouchesPerCrate;
  final int crateCount;
  const PouchStockRow({required this.pouchTypeId, required this.name, required this.milkPerPouch, required this.pouchesPerCrate, required this.crateCount});
  factory PouchStockRow.fromJson(Map<String, dynamic> j) => PouchStockRow(
    pouchTypeId: int.parse(j['pouch_type_id'].toString()),
    name: j['name'].toString(),
    milkPerPouch: double.parse((j['milk_per_pouch'] ?? '0').toString()),
    pouchesPerCrate: int.tryParse((j['pouches_per_crate'] ?? '12').toString()) ?? 12,
    crateCount: int.parse((j['crate_count'] ?? '0').toString()),
  );
}

// ── Audit Log ────────────────────────────────────────────────
class AuditLogEntry {
  final int id;
  final String tableName;
  final String tableLabel;
  final int recordId;
  final String action;
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final int userId;
  final String userName;
  final String? ipAddress;
  final DateTime createdAt;

  const AuditLogEntry({
    required this.id,         required this.tableName,
    required this.tableLabel, required this.recordId,
    required this.action,     this.oldData, this.newData,
    required this.userId,     required this.userName,
    this.ipAddress,           required this.createdAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> j) => AuditLogEntry(
    id:         int.parse(j['id'].toString()),
    tableName:  j['table_name'],
    tableLabel: j['table_label'] ?? j['table_name'],
    recordId:   int.parse(j['record_id'].toString()),
    action:     j['action'],
    oldData:    j['old_data'] as Map<String, dynamic>?,
    newData:    j['new_data'] as Map<String, dynamic>?,
    userId:     int.parse(j['user_id'].toString()),
    userName:   j['user_name'],
    ipAddress:  j['ip_address'],
    createdAt:  DateTime.parse(j['created_at']),
  );
}
