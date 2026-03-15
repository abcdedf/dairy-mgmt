# V4 Database Design — Normalized Transaction Schema

## Overview

The V4 schema replaces ~10 separate production/sales tables (`wp_mf_3_dp_*`) with a normalized two-table design: **transactions** (header) + **transaction_lines** (detail). A unified **parties** table replaces separate vendor/customer tables.

**Prefix:** `wp_mf_4_`
**Database:** `bitnami_wordpress`
**Engine:** InnoDB, utf8mb4

---

## Tables

### `wp_mf_4_parties`

Unified table for all counterparties: vendors, customers, and the reserved "Internal" party used for processing transactions.

| Column | Type | Notes |
|--------|------|-------|
| `id` | INT UNSIGNED AUTO_INCREMENT PK | |
| `name` | VARCHAR(100) NOT NULL | |
| `party_type` | ENUM('vendor', 'customer', 'internal') NOT NULL | |
| `is_active` | TINYINT NOT NULL DEFAULT 1 | |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |

**Constraints:**
- UNIQUE KEY on `(name, party_type)` — same name can exist as both vendor and customer
- **id=1 is reserved** for the "Internal" party (used on all processing transactions)

**Migrated from:** `wp_mf_3_dp_vendors` and `wp_mf_3_dp_customers`

---

### `wp_mf_4_transactions`

Header record for every business event: purchase, processing, or sale.

| Column | Type | Notes |
|--------|------|-------|
| `id` | INT UNSIGNED AUTO_INCREMENT PK | |
| `location_id` | INT UNSIGNED NOT NULL | FK to `wp_mf_3_dp_locations` |
| `transaction_date` | DATE NOT NULL | |
| `transaction_type` | ENUM('purchase', 'processing', 'sale') NOT NULL | |
| `processing_type` | VARCHAR(30) NULL | FK to `wp_mf_3_dp_production_flows.key`; NULL for purchase/sale |
| `party_id` | INT UNSIGNED NOT NULL | FK to `wp_mf_4_parties`; Internal(1) for processing |
| `created_by` | BIGINT UNSIGNED | WordPress user ID |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |

**Indexes:**
- `(location_id, transaction_date)` — primary query pattern
- `(transaction_type)` — filter by type
- `(processing_type)` — filter processing flows
- `(party_id)` — vendor/customer queries

---

### `wp_mf_4_transaction_lines`

Detail lines for each transaction. Every product movement is a line with a signed quantity.

| Column | Type | Notes |
|--------|------|-------|
| `id` | INT UNSIGNED AUTO_INCREMENT PK | |
| `transaction_id` | INT UNSIGNED NOT NULL | FK to `wp_mf_4_transactions` |
| `product_id` | INT UNSIGNED NOT NULL | FK to `wp_mf_3_dp_products` |
| `qty` | DECIMAL(10,2) NOT NULL | **Signed: + inward, - outward** |
| `rate` | DECIMAL(10,2) NULL | Purchase/sale price per unit; NULL for processing |
| `source_transaction_id` | INT UNSIGNED NULL | FK to `wp_mf_4_transactions`; links processing input to original purchase for cost tracing |
| `snf` | DECIMAL(4,1) NULL | Solid-Not-Fat %; relevant for FF Milk, Skim Milk |
| `fat` | DECIMAL(4,1) NULL | Fat %; relevant for FF Milk, Cream, Butter |

**Indexes:**
- `(transaction_id)` — join to header
- `(product_id)` — stock/product queries
- `(source_transaction_id)` — cost traceability joins

---

### `wp_mf_3_dp_production_flows` (existing table, referenced by V4)

Defines the types of processing operations.

| Key | Label |
|-----|-------|
| `ff_milk_processing` | FF Milk -> Cream + Skim |
| `cream_processing` | Cream -> Butter / Ghee |
| `butter_processing` | Butter -> Ghee |
| `curd_production` | FF Milk -> Cream + Curd |
| `pouch_production` | FF Milk -> Cream + Pouches |
| `madhusudan_sale` | FF Milk -> Madhusudan |

---

## Signed Quantity Convention

| Direction | Sign | Examples |
|-----------|------|---------|
| Inward (adds to stock) | **Positive (+)** | Purchases, processing outputs |
| Outward (removes from stock) | **Negative (-)** | Sales, processing inputs (consumption) |

This means **stock = SUM(qty)** for any product at any location/date range.

---

## Transaction Type Examples

### 1. Purchase — FF Milk from Vendor "Sharma"

**Header:**
```
transaction_type = 'purchase'
party_id         = <Sharma's party id>
processing_type  = NULL
```

**Lines:**
| product_id | qty | rate | snf | fat |
|-----------|-----|------|-----|-----|
| 1 (FF Milk) | +500.00 | 54.00 | 8.5 | 6.2 |

---

### 2. Purchase — Multi-product (SMP + Protein + Culture + Matka)

**Header:**
```
transaction_type = 'purchase'
party_id         = <vendor party id>
```

**Lines:**
| product_id | qty | rate |
|-----------|-----|------|
| 7 (SMP) | +10.00 | 200.00 |
| 8 (Protein) | +5.00 | 150.00 |
| 9 (Culture) | +3.00 | 180.00 |
| 11 (Matka) | +500.00 | 15.00 |

---

### 3. Processing — FF Milk -> Skim Milk + Cream (multi-vendor input)

**Header:**
```
transaction_type = 'processing'
processing_type  = 'ff_milk_processing'
party_id         = 1 (Internal)
```

**Lines:**
| product_id | qty | source_transaction_id | snf | fat |
|-----------|-----|-----------------------|-----|-----|
| 1 (FF Milk) | **-300.00** | purchase_txn_A | | |
| 1 (FF Milk) | **-200.00** | purchase_txn_B | | |
| 2 (Skim Milk) | **+440.00** | | 8.8 | |
| 3 (Cream) | **+60.00** | | | 40.0 |

- Inputs are negative (consuming FF Milk)
- `source_transaction_id` on each input line links back to the exact purchase transaction — enables cost attribution
- Outputs are positive (producing new products)

---

### 4. Processing — Cream -> Butter + Ghee

**Header:**
```
transaction_type = 'processing'
processing_type  = 'cream_processing'
party_id         = 1 (Internal)
```

**Lines:**
| product_id | qty | source_transaction_id | fat |
|-----------|-----|-----------------------|-----|
| 3 (Cream) | **-60.00** | <ff_milk_processing txn> | |
| 4 (Butter) | **+45.00** | | 82.0 |
| 5 (Ghee) | **+12.00** | | |

---

### 5. Processing — Curd Production

**Header:**
```
transaction_type = 'processing'
processing_type  = 'curd_production'
party_id         = 1 (Internal)
```

**Lines:**
| product_id | qty | source_transaction_id |
|-----------|-----|-----------------------|
| 1 (FF Milk) | **-500.00** | <purchase txn> |
| 7 (SMP) | **-2.00** | |
| 8 (Protein) | **-0.50** | |
| 9 (Culture) | **-0.30** | |
| 11 (Matka) | **-578.00** | |
| 3 (Cream) | **+60.00** | |
| 10 (Curd) | **+578.00** | |

---

### 6. Sale — Skim Milk to Customer

**Header:**
```
transaction_type = 'sale'
party_id         = <customer party id>
processing_type  = NULL
```

**Lines:**
| product_id | qty | rate |
|-----------|-----|------|
| 2 (Skim Milk) | **-200.00** | 30.00 |

Sales always have negative qty (outward). Rate is the selling price.

---

## Key Queries

### Stock Balance (replaces 27-UNION-ALL query)

```sql
SELECT p.name, SUM(l.qty) AS balance
FROM wp_mf_4_transaction_lines l
JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
JOIN wp_mf_3_dp_products p ON p.id = l.product_id
WHERE t.location_id = ?
  AND t.transaction_date BETWEEN ? AND ?
GROUP BY l.product_id
ORDER BY l.product_id;
```

---

### Cost Traceability — What did processing inputs cost?

```sql
SELECT l.qty AS consumed_qty,
       src_line.rate AS purchase_rate,
       ABS(l.qty) * src_line.rate AS input_cost
FROM wp_mf_4_transaction_lines l
JOIN wp_mf_4_transaction_lines src_line
  ON src_line.transaction_id = l.source_transaction_id
  AND src_line.product_id = l.product_id
  AND src_line.qty > 0
WHERE l.transaction_id = ?
  AND l.qty < 0;
```

Example: FF Milk processing consumed 300 KG @ 54/KG (from purchase A) + 200 KG @ 56/KG (from purchase B) = total input cost 27,400.

---

### All Transactions for a Vendor

```sql
SELECT t.*, l.*
FROM wp_mf_4_transactions t
JOIN wp_mf_4_transaction_lines l ON l.transaction_id = t.id
WHERE t.party_id = ?
ORDER BY t.transaction_date DESC;
```

---

### Vendor Purchase Totals by Product

```sql
SELECT p.name, SUM(l.qty) AS total_qty, SUM(l.qty * l.rate) AS total_value
FROM wp_mf_4_transaction_lines l
JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
JOIN wp_mf_3_dp_products p ON p.id = l.product_id
WHERE t.party_id = ? AND t.transaction_type = 'purchase'
GROUP BY l.product_id;
```

---

### Duplicate Sale Detection (application-level)

```sql
SELECT COUNT(*) FROM (
    SELECT t.location_id, t.transaction_date, t.party_id,
           l.product_id, l.qty, l.rate
    FROM wp_mf_4_transactions t
    JOIN wp_mf_4_transaction_lines l ON l.transaction_id = t.id
    WHERE t.location_id = ?
      AND t.transaction_type = 'sale'
      AND t.transaction_date = ?
      AND t.party_id = ?
      AND l.product_id = ?
      AND l.qty = ?
      AND l.rate = ?
) sub;
```

If count > 0, warn the operator about potential duplicate entry.

---

## Design Rationale

1. **Two-table header/detail** — Every business event (purchase, processing, sale) follows the same pattern: one header with M input lines and N output lines. No need for separate tables per flow type.

2. **Signed quantities** — Stock is a simple `SUM(qty)`. No need for separate "in" and "out" columns or complex UNION queries.

3. **Unified parties** — Vendors, customers, and the internal entity share one table. Supports future attributes (address, GSTIN) uniformly. Prevents the same name collision across types via `UNIQUE(name, party_type)`.

4. **`source_transaction_id`** — Links a processing input line back to the exact purchase transaction. This enables margin calculation: you know exactly what was paid for the raw material that went into a processing batch.

5. **`processing_type` from table** — Not a hardcoded ENUM. New processing flows can be added to `wp_mf_3_dp_production_flows` without schema changes.

6. **Party on header** — A purchase always has one vendor, a sale always has one customer. Processing always uses "Internal". No need for party on individual lines.

---

## Migration Notes

- V4 tables use `wp_mf_4_` prefix
- V3 tables (`wp_mf_3_dp_*`) remain untouched — to be retired after migration is validated
- Vendors and customers are auto-migrated into `wp_mf_4_parties` on first plugin load
- Transaction data migration (if needed) is a separate manual step
- Products table (`wp_mf_3_dp_products`) is shared between V3 and V4
