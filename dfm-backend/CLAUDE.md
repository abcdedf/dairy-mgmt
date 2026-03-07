# Dairy Farm Management System — Project Brief

## Project Structure

```
dairy-mgmt/                             ← You are here (Claude Code root)
├── CLAUDE.md                           ← This file
├── flutter-app/                        ← Flutter project root (pubspec.yaml here)
│   └── lib/
│       └── lib/                        ← Dart source root
│           ├── main.dart
│           ├── models/
│           │   └── models.dart
│           ├── core/
│           │   ├── api_client.dart
│           │   ├── app_config.dart
│           │   ├── auth_service.dart
│           │   ├── permission_service.dart
│           │   ├── location_service.dart
│           │   ├── navigation_service.dart
│           │   └── connectivity_service.dart
│           ├── controllers/
│           │   ├── production_controller.dart
│           │   ├── sales_controller.dart
│           │   ├── stock_controller.dart
│           │   ├── stock_valuation_controller.dart
│           │   ├── audit_log_controller.dart
│           │   ├── transactions_controller.dart
│           │   ├── sales_report_controller.dart
│           │   └── vendor_purchase_report_controller.dart
│           └── pages/
│               ├── shared_widgets.dart
│               ├── production_page.dart
│               ├── sales_page.dart
│               ├── stock_page.dart
│               ├── stock_valuation_page.dart
│               ├── audit_log_page.dart
│               ├── transactions_page.dart
│               ├── sales_report_page.dart
│               ├── vendor_purchase_report_page.dart
│               ├── reports_menu_page.dart
│               ├── login_page.dart
│               └── splash_page.dart
└── wordpress-backend/
    ├── dairy-production-api/
    │   └── dairy-production-api.php    ← Main plugin — ALL endpoints (v3.1.0)
    └── dairy-jwt-auth/
        └── dairy-jwt-auth.php          ← JWT auth bridge plugin
```

---

## Architecture Overview

```
Flutter App  (flutter-app/)
    │  JWT Bearer token on every request
    ▼
WordPress REST API  (wordpress-backend/)
    Namespace: /wp-json/dairy/v1
    │  wpdb queries
    ▼
MariaDB — bitnami_wordpress
    Table prefix: wp_mf_3_dp_
```

This is an end-to-end system. When making changes, always consider both sides:
- A new feature typically requires changes to **both** the PHP plugin and the Flutter controller/page
- API endpoint paths, request payload keys, and response field names must match exactly between PHP and Dart
- DB column types must match Dart types (e.g. `DECIMAL(10,2)` → `double`, `INT UNSIGNED` → `int`)

---

## Making changes to the flutter app:
project root: dfm/
You can make changes to project.

## Making changes to wordpress server:
The code is maintained locally at dfm-backend/  
Make changes there, verify php syntax etc. Once satisfied, copy the code to the wordpress server.
You can use "scp -i ../pem/<your-key.pem> ...". to copy the file to the server.
Do not edit the server php code directly. I want the most up to date coopy be available for source control. So, edit locally and scp to the server.
plugin root folder is at <your-wp-plugins-dir>
There are two plugins installed 
dairy-jwt-auth -- for jwt auth functionality
dairy-production-api -- for the business logic and backend database access.
All access to the backend from the flutter app are through REST API that you can find details looking into the code.

## Testing your changes:
## Workflow for Changes

Hot-reload or rebuild Flutter web
Report what was tested and what passed/failed
The instruction may not be complete. Ask me any questions and update this file accordingly.

## Running the App

```bash
# Flutter commands must be run from dfm/ — not the parent
cd dfm

flutter run -d chrome           # Run on Chrome
flutter run                     # Run on connected device (single device)
flutter run -d <device-id>      # Run on specific device
flutter devices                 # List available devices
```

---

## Flutter Conventions

### State Management — GetX
- Controllers extend `GetxController`, registered with `Get.put()` in page `build()`
- Observables: `.obs`, `.value`, `RxnInt()` for nullable ints
- Reactive widgets: `Obx(() => ...)`, `ever(observable, (_) { ... })`

### API Calls — always use ApiClient
```dart
final res = await ApiClient.get('/endpoint?param=value');
final res = await ApiClient.post('/endpoint', {'key': value});
final res = await ApiClient.delete('/endpoint/$id');

if (res.ok) {
  // res.data contains the 'data' field from the JSON response
} else {
  errorMessage.value = res.message ?? 'Failed.';
}
```
- 401 responses auto-logout and redirect to login — no manual handling needed
- Timeout: 15 seconds
- Base URL: `AppConfig.baseUrl` = `{wpBase}/wp-json/dairy/v1`

### Permissions & Navigation
- `PermissionService.instance` — holds the `/me` response after login
- `LocationService.instance.locId` — currently selected location ID (nullable int)
- Pages shown/hidden by `permissions.pages` list from server
- Page keys: `production`, `sales`, `stock`, `reports`, `stock_valuation`, `audit_log`
- **TEST location** — always accessible to all users, no DB assignment needed

### Shared Widgets (`pages/shared_widgets.dart`)

| Widget | Constructor | Purpose |
|--------|-------------|---------|
| `IntField` | `(ctrl, label, unit, {hint, optional=false})` | Whole-number inputs |
| `DecimalKgField` | `(ctrl, label, {unit='KG', optional=false})` | Fractional KG inputs |
| `SnfFatField` | `(ctrl, label)` | SNF/Fat % — 1 decimal, must be < 10 |
| `RateField` | `(ctrl, label, {suffix='INR', optional=false})` | Currency/rate — 2 decimals |
| `CellField` | `(ctrl, {isDecimal=false, onChanged})` | Compact inline table cells |
| `Row2` | `(widgetA, widgetB)` | Two equal-width columns |
| `DCard` | `({child, padding})` | White card with rounded corners + shadow |
| `FeedbackBanner` | `(message, {isError})` | Success/error feedback bar |
| `OfflineBanner` | `()` | Auto-shown when offline |
| `LoadingCenter` | `()` | Centred loading spinner |

**Colours:** `kNavy = #1B4F72`, `kGreen = #1E8449`, `kRed = #E74C3C`

### Models (`models/models.dart`)
Contains shared DTOs and production payload classes:
`DairyLocation`, `Customer`, `Vendor`, `DairyProduct`,
`MilkCreamInput`, `CreamInput`, `CreamButterGheeOutput`,
`ButterInput`, `ButterGheeOutput`, `DahiInput`,
`StockDayRow`, `EstimatedRate`, `AuditLogEntry`

**`SaleEntry` lives in `sales_controller.dart` only — do not add it to models.dart.**

---

## PHP Plugin Conventions (`wordpress-backend/dairy-production-api/dairy-production-api.php`)

**Current version:** 3.1.0
**Class:** `Dairy_Production_API`
**Error log prefix:** `[DairyAPI]`

### Key helper methods
```php
$this->d1($v)                            // 1 decimal string — for SNF/Fat
$this->d2($v)                            // 2 decimal string — for rates, decimal KG
$this->uid()                             // Current WP user ID (int)
$this->db()                              // Returns global $wpdb
$this->ok($data, $status = 200)          // Success response
$this->err($msg, $status = 400)          // Error response
$this->audit($table, $id, $action, $old, $new)  // Write audit log entry
$this->check_db($ctx)                    // Log wpdb error if any after a query
$this->log($message)                     // Write to PHP error log
```

### Standard endpoint handler pattern
```php
public function save_something(WP_REST_Request $r): WP_REST_Response {
    // 1. Check location access
    if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
    try {
        // 2. Validate inputs
        // 3. Build $data array
        // 4. Insert
        if ($db->insert('wp_mf_3_dp_...', $data) === false) {
            $this->log_db('save_something', $db->last_error);
            return $this->err('Database error.', 500);
        }
        // 5. Audit log
        $this->audit('wp_mf_3_dp_...', $db->insert_id, 'INSERT', null, $data);
        return $this->ok(['id' => $db->insert_id], 201);
    } catch (\Exception $e) { return $this->exc('save_something', $e); }
}
```

### JSON response envelope (all endpoints)
```json
{ "success": true,  "data": { ... } }    // 200 or 201
{ "success": false, "message": "..." }   // 4xx or 5xx
```

### DB migrations
Self-healing migrations run in `ensure_dahi_product()` on WordPress `init`. Always check before altering:
```php
$exists = $this->db()->get_var("SELECT COUNT(*) FROM information_schema.X WHERE ...");
if (!$exists) { $this->db()->query("ALTER TABLE ... ADD ..."); }
```

---

## Database Schema

**Database:** `bitnami_wordpress`
**Engine:** InnoDB, utf8mb4
**Table prefix:** `wp_mf_3_dp_`

### Tables

| Table | Purpose |
|-------|---------|
| `wp_mf_3_dp_locations` | Plant locations. `code='TEST'` always accessible |
| `wp_mf_3_dp_products` | Fixed product master — IDs 1–9 never change |
| `wp_mf_3_dp_customers` | Customers. UNIQUE on `name` |
| `wp_mf_3_dp_vendors` | Vendors. UNIQUE on `name` |
| `wp_mf_3_dp_milk_cream_production` | Flow 1 — FF Milk purchase + processing |
| `wp_mf_3_dp_cream_butter_ghee` | Flow 2 — Cream purchase + Cream→Butter/Ghee |
| `wp_mf_3_dp_butter_ghee` | Flow 3 — Butter purchase + Butter→Ghee |
| `wp_mf_3_dp_dahi_production` | Flow 4 — Dahi production |
| `wp_mf_3_dp_sales` | Sales. UNIQUE on `(location_id, product_id, entry_date, customer_id)` |
| `wp_mf_3_dp_ingredient_purchase` | SMP/Protein/Culture purchases. `product_id` 7/8/9 only |
| `wp_mf_3_dp_estimated_rates` | Per-product valuation rates. Finance-only |
| `wp_mf_3_dp_audit_log` | All data changes with old/new JSON. Finance-only |
| `wp_mf_3_dp_user_location_access` | User→Location mapping. ON DELETE CASCADE |
| `wp_mf_3_dp_user_flags` | `user_id` IS the PK (no auto-increment id). `can_finance` flag |

### Fixed Product IDs — never change these

| ID | Name | Unit | Notes |
|----|------|------|-------|
| 1 | FF Milk | KG | Full-fat milk purchased from vendors |
| 2 | Skim Milk | KG | Produced in Flow 1 |
| 3 | Cream | KG | Produced in Flow 1 or purchased |
| 4 | Butter | KG | Produced in Flow 2 or purchased |
| 5 | Ghee | KG | Produced in Flow 2 or Flow 3 |
| 6 | Dahi | pcs | Produced in Flow 4 (container count) |
| 7 | SMP | Bags | Skim Milk Powder — purchased ingredient |
| 8 | Protein | KG | Purchased ingredient — `DECIMAL(10,2)` |
| 9 | Culture | KG | Purchased ingredient — `DECIMAL(10,2)` |

### Critical schema notes
- `input_culture_kg` and `input_protein_kg` in `dahi_production` are `DECIMAL(10,2)` → always `double` in Dart, always `$this->d2()` in PHP
- `wp_mf_3_dp_user_flags` — `user_id` is the primary key, no `id` column
- `wp_mf_3_dp_ingredient_purchase` — no FK on `product_id` (intentional)

---

## Production Flows

```
Flow 1:  FF Milk purchased  →  processing  →  Skim Milk  +  Cream
Flow 2:  Cream purchased/from Flow 1  →  processing  →  Butter  +  Ghee
Flow 3:  Butter purchased/from Flow 2  →  processing  →  Ghee
Flow 4:  SMP + Protein + Culture + Skim Milk  →  processing  →  Dahi (pcs)
```

Stock is a **30-day running cumulative balance** — movements summed per day and carried forward. Negative values are valid and shown in red.

---

## API Endpoints

| Method | Path | Purpose | Extra auth |
|--------|------|---------|------------|
| GET | `/me` | Permissions object after login | — |
| GET | `/locations` | User's permitted locations | — |
| GET | `/products` | All active products | — |
| GET | `/vendors` | All active vendors | — |
| GET | `/customers` | All active customers | — |
| GET | `/milk-cream` | Flow 1 records | location |
| POST | `/milk-cream` | Save Flow 1 entry | location |
| GET | `/cream-butter-ghee` | Flow 2 records | location |
| POST | `/cream-butter-ghee` | Save Flow 2 processing | location |
| POST | `/cream-input` | Save Flow 2 cream purchase | location |
| GET | `/butter-ghee` | Flow 3 records | location |
| POST | `/butter-ghee` | Save Flow 3 processing | location |
| POST | `/butter-input` | Save Flow 3 butter purchase | location |
| GET | `/dahi` | Flow 4 records | location |
| POST | `/dahi` | Save Flow 4 entry | location |
| POST | `/smp-purchase` | Save SMP/Protein/Culture purchase | location |
| GET | `/sales` | Sales for date + location | location |
| POST | `/sales` | Add sale entry | location |
| DELETE | `/sales/{id}` | Delete sale entry | location |
| GET | `/stock` | 30-day running stock | location |
| GET | `/sales-report` | Pivoted sales by product | location |
| GET | `/vendor-purchase-report` | Purchase history by vendor | location |
| GET | `/production-transactions` | Recent production entries | location |
| GET | `/sales-transactions` | Recent sales entries | location |
| GET | `/estimated-rates` | Per-product valuation rates | finance |
| POST | `/estimated-rates` | Update valuation rates | finance |
| GET | `/stock-valuation` | Stock with estimated values | location + finance |
| GET | `/audit-log` | Change history log | finance |
| GET | `/settings` | App settings (transaction_days) | — |

---

## Access Control

| Condition | Pages accessible |
|-----------|-----------------|
| No location assigned | None — access screen only |
| Location assigned | `production`, `sales`, `stock`, `reports` |
| `code = 'TEST'` location | Always accessible — no assignment needed |
| `can_finance = true` | Additionally: `stock_valuation`, `audit_log` |

Access enforced server-side. App only reads `pages` array from `/me` to show/hide tabs.

---

## File Update Rules

**Always output complete files** — never partial snippets or diffs. Developer replaces files wholesale.

Before delivering any changed file:
1. Read the full current file first
2. Make only the targeted changes
3. Diff against the original — verify only intended lines changed
4. Check bracket/brace balance
5. Output the complete file

### Files that must stay in sync

| Flutter file | Must match |
|---|---|
| `models/models.dart` | PHP payload fields + DB column names |
| `production_controller.dart` | `production_page.dart` — same field names |
| `shared_widgets.dart` | All pages using field widgets |
| Any controller | Corresponding PHP endpoint — path, payload keys, response fields |

---

## Deployment

### PHP plugin
```
Server path: <your-wp-plugins-dir>/dairy-production-api/dairy-production-api.php
```
Replace file → live immediately. DB migrations run automatically on next page load.

### Flutter web
```bash
cd flutter-app
flutter build web --base-href /dairyapp/
# Upload build/web/ to /bitnami/wordpress/dairyapp/ on server
```

---

## Known Gotchas — Do Not Reintroduce

- `SaleEntry` is defined in `sales_controller.dart` — **never** add it to `models.dart`
- `input_culture_kg` / `input_protein_kg` are `DECIMAL(10,2)` — use `double` not `int`
- `wp_mf_3_dp_user_flags` has no `id` column — `user_id` is the PK
- Sales duplicate inserts fail silently at DB level due to UNIQUE constraint
- Stock query window must be 30 days to get correct cumulative balance
- `dairy_transaction_days` WP option controls transaction history (default 7, max 90)


## Publishing the app  on the web server:
**CRITICAL: NEVER deploy to the server (Flutter web build, PHP plugin, or any file) unless the user explicitly says "deploy" or "publish". The server is a PRODUCTION host. All testing must be done locally using `flutter run -d chrome`. This applies to both Flutter and PHP files — do not scp anything to the server without explicit ask.**
Access to the server is ssh. The pem details are given in an earlier section.
Path for the site on the server: <your-wp-root>/dairyapp
The server is accessed through ssh/scp. The pem detailes is given earlier.
URL accessing the app on the web: https://<your-domain>/dairyapp/

## User credential for all testing
See: ../../pem/dairy-mgmt-credentials.txt (outside source control)


