#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# V4 Schema Test Suite — wp_mf_4_parties, wp_mf_4_transactions,
#                         wp_mf_4_transaction_lines
# ═══════════════════════════════════════════════════════════════
#
# Tests run directly against the production DB via SSH.
# All test data is inserted then cleaned up at the end.
# Uses location_id=999 and party names prefixed with 'TEST_' to
# avoid collision with real data.
#
# Usage: bash test/v4_schema_test.sh

set -e

PEM="/Users/abhayapat/git-repos/pem/awsls001.pem"
HOST="bitnami@www.nkp45fd.fanol.xyz"
DB_USER="bn_wordpress"
DB_PASS="51c25c040d0193219ba3e75e53badb316eb957e023efe3811c72234969c70014"
DB="bitnami_wordpress"

PASS=0
FAIL=0
TOTAL=0

sql() {
    ssh -i "$PEM" "$HOST" "mysql -u $DB_USER -p'$DB_PASS' $DB -N -e \"$1\"" 2>/dev/null
}

assert_eq() {
    TOTAL=$((TOTAL + 1))
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected='$expected', actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_gt() {
    TOTAL=$((TOTAL + 1))
    local desc="$1" threshold="$2" actual="$3"
    if [ "$actual" -gt "$threshold" ] 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected > $threshold, actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "═══════════════════════════════════════════════════"
echo " V4 Schema Test Suite"
echo "═══════════════════════════════════════════════════"
echo ""

# ── Cleanup any leftover test data ──
sql "DELETE FROM wp_mf_4_transaction_lines WHERE transaction_id IN (SELECT id FROM wp_mf_4_transactions WHERE location_id=999);"
sql "DELETE FROM wp_mf_4_transactions WHERE location_id=999;"
sql "DELETE FROM wp_mf_4_parties WHERE name LIKE 'TEST_%';"

# ══════════════════════════════════════════
echo "1. PARTIES TABLE"
echo "──────────────────────────────────────"

# 1a. Internal party exists with id=1
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_parties WHERE id=1 AND name='Internal' AND party_type='internal';")
assert_eq "Internal party exists with id=1" "1" "$RESULT"

# 1b. Vendors migrated
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_parties WHERE party_type='vendor';")
assert_gt "Vendors migrated (count > 0)" 0 "$RESULT"

# 1c. Customers migrated
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_parties WHERE party_type='customer';")
assert_gt "Customers migrated (count > 0)" 0 "$RESULT"

# 1d. Insert test vendor
sql "INSERT INTO wp_mf_4_parties (name, party_type) VALUES ('TEST_VendorA', 'vendor');"
TV_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_VendorA';")
assert_gt "Test vendor created" 0 "$TV_ID"

# 1e. Insert test customer
sql "INSERT INTO wp_mf_4_parties (name, party_type) VALUES ('TEST_CustomerA', 'customer');"
TC_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_CustomerA';")
assert_gt "Test customer created" 0 "$TC_ID"

# 1f. Unique constraint — duplicate name+type should fail
RESULT=$(sql "INSERT INTO wp_mf_4_parties (name, party_type) VALUES ('TEST_VendorA', 'vendor');" 2>&1 || echo "DUPLICATE")
echo "$RESULT" | grep -q "Duplicate\|DUPLICATE" && DUP_OK="yes" || DUP_OK="no"
assert_eq "Duplicate vendor name rejected" "yes" "$DUP_OK"

# 1g. Same name different type should succeed
sql "INSERT INTO wp_mf_4_parties (name, party_type) VALUES ('TEST_VendorA', 'customer');"
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_parties WHERE name='TEST_VendorA';")
assert_eq "Same name, different type allowed" "2" "$RESULT"

echo ""

# ══════════════════════════════════════════
echo "2. PURCHASE TRANSACTIONS"
echo "──────────────────────────────────────"

# 2a. FF Milk Purchase — single product, single line
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'purchase', $TV_ID, 1);"
P1_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate, snf, fat) VALUES ($P1_ID, 1, 500.00, 54.00, 8.5, 6.2);"
RESULT=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$P1_ID;")
assert_eq "FF Milk purchase: qty=500" "500.00" "$RESULT"

# 2b. Verify transaction type
RESULT=$(sql "SELECT transaction_type FROM wp_mf_4_transactions WHERE id=$P1_ID;")
assert_eq "FF Milk purchase: type=purchase" "purchase" "$RESULT"

# 2c. Verify party
RESULT=$(sql "SELECT party_id FROM wp_mf_4_transactions WHERE id=$P1_ID;")
assert_eq "FF Milk purchase: party=test vendor" "$TV_ID" "$RESULT"

# 2d. Second FF Milk purchase from same vendor, different rate
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-14', 'purchase', $TV_ID, 1);"
P2_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate, snf, fat) VALUES ($P2_ID, 1, 300.00, 56.00, 8.3, 6.0);"

# 2e. Multi-product purchase (SMP + Protein + Culture)
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'purchase', $TV_ID, 1);"
P3_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate) VALUES ($P3_ID, 7, 10.00, 200.00);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate) VALUES ($P3_ID, 8, 5.00, 150.00);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate) VALUES ($P3_ID, 9, 3.00, 180.00);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate) VALUES ($P3_ID, 11, 500.00, 15.00);"
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$P3_ID;")
assert_eq "Multi-product purchase: 4 lines" "4" "$RESULT"

# 2f. Cream purchase with fat
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'purchase', $TV_ID, 1);"
P4_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate, fat) VALUES ($P4_ID, 3, 100.00, 275.00, 40.0);"
RESULT=$(sql "SELECT fat FROM wp_mf_4_transaction_lines WHERE transaction_id=$P4_ID;")
assert_eq "Cream purchase: fat=40.0" "40.0" "$RESULT"

# 2g. Butter purchase with fat
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'purchase', $TV_ID, 1);"
P5_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate, fat) VALUES ($P5_ID, 4, 50.00, 350.00, 82.0);"
RESULT=$(sql "SELECT fat FROM wp_mf_4_transaction_lines WHERE transaction_id=$P5_ID;")
assert_eq "Butter purchase: fat=82.0" "82.0" "$RESULT"

echo ""

# ══════════════════════════════════════════
echo "3. PROCESSING TRANSACTIONS"
echo "──────────────────────────────────────"

# Flow keys (VARCHAR, not integer IDs)
FLOW_FF="ff_milk_processing"
FLOW_CREAM="cream_processing"
FLOW_BUTTER="butter_processing"
FLOW_CURD="curd_production"

# 3a. FF Milk Processing — multi-vendor input, skim+cream output
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, processing_type, party_id, created_by) VALUES (999, '2026-03-13', 'processing', '$FLOW_FF', 1, 1);"
PR1_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
# Inputs (negative qty, with source_transaction_id)
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, source_transaction_id) VALUES ($PR1_ID, 1, -300.00, $P1_ID);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, source_transaction_id) VALUES ($PR1_ID, 1, -200.00, $P2_ID);"
# Outputs (positive qty)
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, snf) VALUES ($PR1_ID, 2, 440.00, 8.8);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, fat) VALUES ($PR1_ID, 3, 60.00, 40.0);"

RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR1_ID;")
assert_eq "FF Milk processing: 4 lines (2 in, 2 out)" "4" "$RESULT"

RESULT=$(sql "SELECT transaction_type FROM wp_mf_4_transactions WHERE id=$PR1_ID;")
assert_eq "FF Milk processing: type=processing" "processing" "$RESULT"

RESULT=$(sql "SELECT party_id FROM wp_mf_4_transactions WHERE id=$PR1_ID;")
assert_eq "FF Milk processing: party=Internal(1)" "1" "$RESULT"

# Verify inputs are negative
RESULT=$(sql "SELECT SUM(qty) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR1_ID AND qty < 0;")
assert_eq "FF Milk processing: total input = -500" "-500.00" "$RESULT"

# Verify outputs are positive
RESULT=$(sql "SELECT SUM(qty) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR1_ID AND qty > 0;")
assert_eq "FF Milk processing: total output = 500 (440+60)" "500.00" "$RESULT"

# Verify source_transaction_id on inputs
RESULT=$(sql "SELECT source_transaction_id FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR1_ID AND qty=-300.00;")
assert_eq "FF Milk processing: input 300 sourced from purchase $P1_ID" "$P1_ID" "$RESULT"

# 3b. Cream Processing — cream in, butter+ghee out
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, processing_type, party_id, created_by) VALUES (999, '2026-03-13', 'processing', '$FLOW_CREAM', 1, 1);"
PR2_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, source_transaction_id) VALUES ($PR2_ID, 3, -60.00, $PR1_ID);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, fat) VALUES ($PR2_ID, 4, 45.00, 82.0);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty) VALUES ($PR2_ID, 5, 12.00);"
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR2_ID;")
assert_eq "Cream processing: 3 lines (1 in, 2 out)" "3" "$RESULT"

# 3c. Butter Processing — butter in, ghee out
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, processing_type, party_id, created_by) VALUES (999, '2026-03-13', 'processing', '$FLOW_BUTTER', 1, 1);"
PR3_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, source_transaction_id) VALUES ($PR3_ID, 4, -45.00, $PR2_ID);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty) VALUES ($PR3_ID, 5, 38.00);"
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR3_ID;")
assert_eq "Butter processing: 2 lines (1 in, 1 out)" "2" "$RESULT"

# 3d. Curd Production — FF Milk + ingredients in, cream + curd out
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, processing_type, party_id, created_by) VALUES (999, '2026-03-13', 'processing', '$FLOW_CURD', 1, 1);"
PR4_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, source_transaction_id) VALUES ($PR4_ID, 1, -500.00, $P1_ID);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty) VALUES ($PR4_ID, 7, -2.00);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty) VALUES ($PR4_ID, 8, -0.50);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty) VALUES ($PR4_ID, 9, -0.30);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty) VALUES ($PR4_ID, 11, -578.00);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, fat) VALUES ($PR4_ID, 3, 60.00, 38.0);"
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty) VALUES ($PR4_ID, 10, 578.00);"
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR4_ID;")
assert_eq "Curd production: 7 lines (5 in, 2 out)" "7" "$RESULT"

INPUT_COUNT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR4_ID AND qty < 0;")
OUTPUT_COUNT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR4_ID AND qty > 0;")
assert_eq "Curd production: 5 inputs" "5" "$INPUT_COUNT"
assert_eq "Curd production: 2 outputs" "2" "$OUTPUT_COUNT"

echo ""

# ══════════════════════════════════════════
echo "4. SALE TRANSACTIONS"
echo "──────────────────────────────────────"

# 4a. Simple sale — Skim Milk
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'sale', $TC_ID, 1);"
S1_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate) VALUES ($S1_ID, 2, -200.00, 30.00);"
RESULT=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$S1_ID;")
assert_eq "Skim Milk sale: qty=-200" "-200.00" "$RESULT"

RESULT=$(sql "SELECT rate FROM wp_mf_4_transaction_lines WHERE transaction_id=$S1_ID;")
assert_eq "Skim Milk sale: rate=30" "30.00" "$RESULT"

# 4b. Madhusudan sale — FF Milk with source_transaction_id
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'sale', $TC_ID, 1);"
S2_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate, source_transaction_id) VALUES ($S2_ID, 1, -300.00, 58.00, $P1_ID);"
RESULT=$(sql "SELECT source_transaction_id FROM wp_mf_4_transaction_lines WHERE transaction_id=$S2_ID;")
assert_eq "Madhusudan sale: source traced to purchase" "$P1_ID" "$RESULT"

# 4c. Duplicate sale detection (application-level) — same location, date, party, product, qty, rate
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'sale', $TC_ID, 1);"
S3_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate) VALUES ($S3_ID, 2, -200.00, 30.00);"

# Check: should detect duplicate via query
DUP_COUNT=$(sql "
    SELECT COUNT(*) FROM (
        SELECT t.location_id, t.transaction_date, t.party_id, l.product_id, l.qty, l.rate
        FROM wp_mf_4_transactions t
        JOIN wp_mf_4_transaction_lines l ON l.transaction_id = t.id
        WHERE t.location_id=999 AND t.transaction_type='sale'
          AND t.transaction_date='2026-03-13' AND t.party_id=$TC_ID
          AND l.product_id=2 AND l.qty=-200.00 AND l.rate=30.00
    ) sub;
")
assert_eq "Duplicate sale detection: found 2 matching entries" "2" "$DUP_COUNT"

# 4d. Same product, different qty — NOT a duplicate
sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'sale', $TC_ID, 1);"
S4_ID=$(sql "SELECT MAX(id) FROM wp_mf_4_transactions WHERE location_id=999;")
sql "INSERT INTO wp_mf_4_transaction_lines (transaction_id, product_id, qty, rate) VALUES ($S4_ID, 2, -150.00, 30.00);"
RESULT=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$S4_ID;")
assert_eq "Different qty sale: not a duplicate, qty=-150" "-150.00" "$RESULT"

echo ""

# ══════════════════════════════════════════
echo "5. STOCK BALANCE QUERY"
echo "──────────────────────────────────────"

# Stock = SUM of all transaction lines for location 999
STOCK=$(sql "
    SELECT CONCAT(p.name, '=', CAST(SUM(l.qty) AS CHAR))
    FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
    JOIN wp_mf_3_dp_products p ON p.id = l.product_id
    WHERE t.location_id = 999
      AND t.transaction_date BETWEEN '2026-03-01' AND '2026-03-31'
    GROUP BY l.product_id
    ORDER BY l.product_id;
")
echo "  Stock balances for test location:"
echo "$STOCK" | while read line; do echo "    $line"; done

# Verify FF Milk balance:
# Purchased: +500 + 300 = 800
# Consumed: -300 (proc1) -200 (proc1) -500 (curd) -300 (madhusudan sale) = -1300
# Expected: 800 - 1300 = -500
FF_STOCK=$(sql "
    SELECT SUM(l.qty) FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
    WHERE t.location_id=999 AND l.product_id=1;
")
assert_eq "FF Milk stock balance = -500" "-500.00" "$FF_STOCK"

# Verify Skim Milk balance:
# Produced: +440
# Sold: -200 -200 -150 = -550
# Expected: 440 - 550 = -110
SKIM_STOCK=$(sql "
    SELECT SUM(l.qty) FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
    WHERE t.location_id=999 AND l.product_id=2;
")
assert_eq "Skim Milk stock balance = -110" "-110.00" "$SKIM_STOCK"

# Verify Cream balance:
# Purchased: +100, Produced: +60 (proc1) +60 (curd) = +220
# Consumed: -60 (cream proc) = -60
# Expected: 220 - 60 = 160
CREAM_STOCK=$(sql "
    SELECT SUM(l.qty) FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
    WHERE t.location_id=999 AND l.product_id=3;
")
assert_eq "Cream stock balance = 160" "160.00" "$CREAM_STOCK"

# Verify Ghee balance:
# Produced: +12 (cream proc) + 38 (butter proc) = 50
GHEE_STOCK=$(sql "
    SELECT SUM(l.qty) FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
    WHERE t.location_id=999 AND l.product_id=5;
")
assert_eq "Ghee stock balance = 50" "50.00" "$GHEE_STOCK"

echo ""

# ══════════════════════════════════════════
echo "6. COST TRACEABILITY"
echo "──────────────────────────────────────"

# 6a. Trace processing input back to purchase rate
RESULT=$(sql "
    SELECT src_line.rate
    FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transaction_lines src_line
      ON src_line.transaction_id = l.source_transaction_id
      AND src_line.product_id = l.product_id
      AND src_line.qty > 0
    WHERE l.transaction_id = $PR1_ID AND l.qty = -300.00;
")
assert_eq "Processing input 300 KG traces to purchase rate 54.00" "54.00" "$RESULT"

RESULT=$(sql "
    SELECT src_line.rate
    FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transaction_lines src_line
      ON src_line.transaction_id = l.source_transaction_id
      AND src_line.product_id = l.product_id
      AND src_line.qty > 0
    WHERE l.transaction_id = $PR1_ID AND l.qty = -200.00;
")
assert_eq "Processing input 200 KG traces to purchase rate 56.00" "56.00" "$RESULT"

# 6b. Total input cost for FF Milk processing
RESULT=$(sql "
    SELECT CAST(SUM(ABS(l.qty) * src_line.rate) AS DECIMAL(10,2))
    FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transaction_lines src_line
      ON src_line.transaction_id = l.source_transaction_id
      AND src_line.product_id = l.product_id
      AND src_line.qty > 0
    WHERE l.transaction_id = $PR1_ID AND l.qty < 0;
")
# 300*54 + 200*56 = 16200 + 11200 = 27400
assert_eq "FF Milk processing total input cost = 27400" "27400.00" "$RESULT"

echo ""

# ══════════════════════════════════════════
echo "7. PARTY QUERIES"
echo "──────────────────────────────────────"

# 7a. All transactions for test vendor
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transactions WHERE party_id=$TV_ID;")
assert_gt "Transactions for test vendor (count > 0)" 0 "$RESULT"

# 7b. All transactions for test customer
RESULT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transactions WHERE party_id=$TC_ID;")
assert_gt "Transactions for test customer (count > 0)" 0 "$RESULT"

# 7c. Vendor purchase total
RESULT=$(sql "
    SELECT CAST(SUM(l.qty * l.rate) AS DECIMAL(10,2))
    FROM wp_mf_4_transaction_lines l
    JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
    WHERE t.party_id = $TV_ID AND t.transaction_type = 'purchase' AND l.product_id = 1;
")
# 500*54 + 300*56 = 27000 + 16800 = 43800
assert_eq "Vendor FF Milk purchase total = 43800" "43800.00" "$RESULT"

echo ""

# ══════════════════════════════════════════
echo "8. SCHEMA INTEGRITY"
echo "──────────────────────────────────────"

# 8a. ENUM validation — invalid transaction_type should fail
RESULT=$(sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, party_id, created_by) VALUES (999, '2026-03-13', 'transfer', 1, 1);" 2>&1 || echo "ENUM_FAIL")
echo "$RESULT" | grep -q "Data truncated\|ENUM_FAIL\|doesn't have a default" && ENUM_OK="yes" || ENUM_OK="no"
assert_eq "Invalid transaction_type rejected" "yes" "$ENUM_OK"

# 8b. NOT NULL — transaction without party_id should fail
RESULT=$(sql "INSERT INTO wp_mf_4_transactions (location_id, transaction_date, transaction_type, created_by) VALUES (999, '2026-03-13', 'purchase', 1);" 2>&1 || echo "NULL_FAIL")
echo "$RESULT" | grep -q "doesn't have a default\|NULL_FAIL\|Field 'party_id' doesn't" && NULL_OK="yes" || NULL_OK="no"
assert_eq "NULL party_id rejected" "yes" "$NULL_OK"

# 8c. Signed qty works — negative values stored correctly
RESULT=$(sql "SELECT MIN(qty) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PR4_ID;")
assert_eq "Negative qty stored correctly (curd: -578)" "-578.00" "$RESULT"

echo ""

# ══════════════════════════════════════════
echo "CLEANUP"
echo "──────────────────────────────────────"
sql "DELETE FROM wp_mf_4_transaction_lines WHERE transaction_id IN (SELECT id FROM wp_mf_4_transactions WHERE location_id=999);"
sql "DELETE FROM wp_mf_4_transactions WHERE location_id=999;"
sql "DELETE FROM wp_mf_4_parties WHERE name LIKE 'TEST_%';"
echo "  Test data cleaned up."

echo ""
echo "═══════════════════════════════════════════════════"
echo " RESULTS: $PASS passed, $FAIL failed out of $TOTAL tests"
echo "═══════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
