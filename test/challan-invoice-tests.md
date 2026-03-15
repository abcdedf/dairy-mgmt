# Challan & Invoice — Test Cases

All tests run against the **Test location** via REST API.
Test location is always accessible to all users — no assignment needed.

---

## Challan CRUD

### C1. Create challan with bulk product lines
- **Action:** POST `/v4/challan` with 2 bulk product lines (e.g., Ghee 5 KG @ 450, Butter 3 KG @ 300)
- **Expected:** 201 response, `challan_number` assigned, lines saved with correct amounts (2250, 900)

### C2. Create challan with pouch product lines
- **Action:** POST `/v4/challan` with 2 pouch lines (`pouch_product_id`, qty = crate count, rate = crate_rate)
- **Expected:** 201, lines stored with `pouch_product_id` set and `product_id` NULL

### C3. Create challan with mixed lines (pouch + bulk)
- **Action:** POST `/v4/challan` with 1 pouch line + 1 bulk product line
- **Expected:** 201, both lines saved correctly, amounts computed as qty x rate

### C4. List challans
- **Action:** GET `/v4/challans?location_id=TEST&status=all`
- **Expected:** Returns challans with lines; product names resolved for both bulk and pouch lines (COALESCE); `pouch_product_id` present on pouch lines

### C5. List challans — status filter
- **Action:** GET with `status=pending` then `status=invoiced`
- **Expected:** Only challans matching the filter are returned

### C6. Delete pending challan
- **Action:** DELETE `/v4/challan/{id}` on a pending challan
- **Expected:** 200, challan and all its lines are gone (FK CASCADE)

### C7. Delete invoiced challan — should fail
- **Action:** DELETE `/v4/challan/{id}` on an invoiced challan
- **Expected:** 400 error — "Cannot delete an invoiced challan"

### C8. Challan number auto-increment
- **Action:** Create 3 challans at Test location in sequence
- **Expected:** `challan_number` values are sequential (N, N+1, N+2)

---

## Challan Validation

### C9. Missing customer
- **Action:** POST `/v4/challan` with `party_id=0`
- **Expected:** 400 — "Customer is required"

### C10. Empty lines
- **Action:** POST `/v4/challan` with `lines=[]`
- **Expected:** 400 — "At least one line item is required"

### C11. Zero-qty lines skipped
- **Action:** POST `/v4/challan` with lines where some have qty=0 mixed with valid lines
- **Expected:** Only non-zero-qty lines are inserted; challan still created

---

## Invoice CRUD

### I1. Create invoice from pending challans
- **Action:** Create 2 challans for same customer, then POST `/v4/invoice` with both challan IDs
- **Expected:** 201, invoice `total` = sum of challan totals, both challans updated to `status=invoiced` with `invoice_id` set

### I2. Invoice consolidated lines — bulk products
- **Action:** GET `/v4/invoices` for the invoice created in I1
- **Expected:** `lines` array shows aggregated quantities per product with weighted average rate

### I3. Invoice consolidated lines — mixed pouch + bulk
- **Action:** Create challans with pouch and bulk lines, invoice them together
- **Expected:** Invoice `lines` show both types with correct `product_name` and `product_unit` (`crates` for pouch, KG etc. for bulk)

### I4. Mark invoice paid
- **Action:** POST `/v4/invoice/{id}/pay`
- **Expected:** `payment_status` changes to `paid`

### I5. Mark invoice unpaid (toggle back)
- **Action:** POST `/v4/invoice/{id}/pay` again on a paid invoice
- **Expected:** `payment_status` changes back to `unpaid`

### I6. Delete invoice — challans revert
- **Action:** DELETE `/v4/invoice/{id}`
- **Expected:** Invoice deleted; associated challans revert to `status=pending` and `invoice_id=NULL`

### I7. Invoice number auto-increment
- **Action:** Create 2 invoices at Test location in sequence
- **Expected:** `invoice_number` values are sequential (N, N+1)

---

## Invoice Validation

### I8. Cannot invoice already-invoiced challans
- **Action:** POST `/v4/invoice` with challan IDs that are already invoiced
- **Expected:** 400 — "Challan #X is already invoiced"

### I9. Cannot invoice challans from different customers
- **Action:** Create challans for customer A and customer B, try to invoice together
- **Expected:** 400 — "Challan #X belongs to a different customer"

### I10. Cannot invoice challans from different locations
- **Action:** POST `/v4/invoice` with `location_id=X` but challan belongs to location Y
- **Expected:** 400 — "Challan #X belongs to a different location"

---

## Pouch Products

### P1. List pouch products
- **Action:** GET `/pouch-products`
- **Expected:** Returns array with fields: `id`, `name`, `milk_per_pouch`, `pouches_per_crate`, `crate_rate`, `is_active`

### P2. Create pouch product
- **Action:** POST `/pouch-products` with `name`, `milk_per_pouch`, `pouches_per_crate`
- **Expected:** 201, row created with `crate_rate` defaulting to 0

### P3. Update pouch product — set crate_rate
- **Action:** POST `/pouch-products/{id}` with `crate_rate=250.00`
- **Expected:** `crate_rate` updated to 250.00

### P4. Deactivate pouch product
- **Action:** POST `/pouch-products/{id}` with `is_active=0`
- **Expected:** Pouch product no longer returned in challan GET response's `pouch_products` list (only active ones are returned)

---

## Cleanup

### X1. Teardown
- Delete all invoices created during the test run (this reverts challans to pending)
- Delete all challans created during the test run
- Deactivate or delete any test pouch products created
- Verify: Test location has no orphaned data from this test run
