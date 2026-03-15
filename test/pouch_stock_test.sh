#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Pouch Stock Test Suite — Tests pouch production → stock IN,
# invoice → stock OUT, and cleanup on invoice delete.
# ═══════════════════════════════════════════════════════════════
#
# Uses the TEST location (id=3) to avoid polluting real data.
# All test data is cleaned up at the end.
#
# Usage: bash test/pouch_stock_test.sh

set -e

# ── Config ────────────────────────────────────────────────────
BASE="https://www.nkp45fd.fanol.xyz/wp-json"
APP_USER="a1p1"
APP_PASS='DpFT$56%Def'
PEM="/Users/abhayapat/git-repos/pem/awsls001.pem"
HOST="bitnami@www.nkp45fd.fanol.xyz"
DB_USER="root"
DB_PASS="5Zmxpbjun1Tw"
DB="bitnami_wordpress"

TEST_LOC=3
TEST_DATE="2099-12-25"
POUCH_PRODUCT_ID=12  # Aggregated Pouch Milk product

# Track IDs for cleanup
CREATED_TXN_IDS=()
CREATED_CHALLAN_IDS=()
CREATED_INVOICE_IDS=()

PASS=0
FAIL=0
TOTAL=0

# ── Helpers ───────────────────────────────────────────────────

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

assert_neq() {
    TOTAL=$((TOTAL + 1))
    local desc="$1" not_expected="$2" actual="$3"
    if [ "$not_expected" != "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (should not be '$not_expected')"
        FAIL=$((FAIL + 1))
    fi
}

assert_gt() {
    TOTAL=$((TOTAL + 1))
    local desc="$1" threshold="$2" actual="$3"
    if [ "$(echo "$actual > $threshold" | bc -l 2>/dev/null)" = "1" ]; then
        echo "  PASS: $desc ($actual > $threshold)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (actual='$actual', expected > '$threshold')"
        FAIL=$((FAIL + 1))
    fi
}

# ── Auth ──────────────────────────────────────────────────────

echo "═══ Pouch Stock Test Suite ═══"
echo ""
echo "── Authenticating ──"

TOKEN=$(curl -s -X POST "$BASE/dairy/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$APP_USER\",\"password\":\"$APP_PASS\"}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('token',''))")

if [ -z "$TOKEN" ]; then
    echo "FATAL: Could not authenticate. Aborting."
    exit 1
fi
echo "  Authenticated as $APP_USER"

api_get() {
    curl -s -H "Authorization: Bearer $TOKEN" "$BASE/dairy/v1$1"
}

api_post() {
    curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
        -d "$2" "$BASE/dairy/v1$1"
}

api_delete() {
    curl -s -X DELETE -H "Authorization: Bearer $TOKEN" "$BASE/dairy/v1$1"
}

json_val() {
    echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print($2)"
}

# ── Setup ─────────────────────────────────────────────────────

echo ""
echo "── Setup ──"

# Ensure test vendor
TEST_VENDOR_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_POUCH_VENDOR' AND party_type='vendor' LIMIT 1")
if [ -z "$TEST_VENDOR_ID" ]; then
    sql "INSERT INTO wp_mf_4_parties (name, party_type, is_active) VALUES ('TEST_POUCH_VENDOR', 'vendor', 1)"
    TEST_VENDOR_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_POUCH_VENDOR' AND party_type='vendor' LIMIT 1")
fi
echo "  Test vendor party_id=$TEST_VENDOR_ID"

# Ensure test customer
TEST_CUSTOMER_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_POUCH_CUSTOMER' AND party_type='customer' LIMIT 1")
if [ -z "$TEST_CUSTOMER_ID" ]; then
    sql "INSERT INTO wp_mf_4_parties (name, party_type, is_active) VALUES ('TEST_POUCH_CUSTOMER', 'customer', 1)"
    TEST_CUSTOMER_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_POUCH_CUSTOMER' AND party_type='customer' LIMIT 1")
fi
echo "  Test customer party_id=$TEST_CUSTOMER_ID"

# Ensure customer has pouch product (12) assigned
HAS_POUCH=$(sql "SELECT COUNT(*) FROM wp_mf_3_dp_customer_products WHERE party_id=$TEST_CUSTOMER_ID AND product_id=12")
if [ "$HAS_POUCH" = "0" ]; then
    sql "INSERT INTO wp_mf_3_dp_customer_products (party_id, product_id) VALUES ($TEST_CUSTOMER_ID, 12)"
fi
echo "  Customer has Pouch Milk (product 12) assigned"

# Get first active pouch product for testing
POUCH_TYPE_ID=$(sql "SELECT id FROM wp_mf_3_dp_pouch_products WHERE is_active=1 LIMIT 1")
echo "  Using pouch_type_id=$POUCH_TYPE_ID for tests"

# Record initial stock balance for product 12
INITIAL_BALANCE=$(sql "SELECT COALESCE(SUM(l.qty), 0) FROM wp_mf_4_transaction_lines l JOIN wp_mf_4_transactions t ON t.id = l.transaction_id WHERE t.location_id=$TEST_LOC AND l.product_id=$POUCH_PRODUCT_ID")
echo "  Initial product 12 balance: $INITIAL_BALANCE"

# ══════════════════════════════════════════════════════════════
# TEST 1: Pouch Production → Product 12 stock IN
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 1. Pouch Production → stock IN ──"

# Create FF Milk purchase first (needed as input)
RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"purchase\",
    \"party_id\": $TEST_VENDOR_ID,
    \"lines\": [{\"product_id\": 1, \"qty\": 500, \"rate\": 45.00}]
}")
PURCHASE_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
if [ -n "$PURCHASE_ID" ] && [ "$PURCHASE_ID" != "None" ]; then
    CREATED_TXN_IDS+=("$PURCHASE_ID")
    echo "  Created FF Milk purchase txn=$PURCHASE_ID (500 KG)"
fi

# Create pouch production: 10 crates → should create product 12 line with qty = 10 * 12 = 120 KG
POUCH_NOTES="{\"pouch_lines\":[{\"pouch_type_id\":$POUCH_TYPE_ID,\"crate_count\":10}]}"
RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"processing\",
    \"processing_type\": \"pouch_production\",
    \"party_id\": 1,
    \"milk_usage\": [{\"party_id\": $TEST_VENDOR_ID, \"qty\": 120}],
    \"notes\": $(echo "$POUCH_NOTES" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
}")
PROD_OK=$(json_val "$RES" "d.get('success', False)")
PROD_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "Pouch production returns success" "True" "$PROD_OK"
assert_neq "Pouch production returns an ID" "" "$PROD_ID"

if [ -n "$PROD_ID" ] && [ "$PROD_ID" != "None" ]; then
    CREATED_TXN_IDS+=("$PROD_ID")

    # Check product 12 line was auto-created with qty = 10 * 12 = 120
    P12_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROD_ID AND product_id=$POUCH_PRODUCT_ID")
    assert_eq "Product 12 line created with qty=120.00 (10 crates × 12)" "120.00" "$P12_QTY"

    # Check FF Milk consumed
    FF_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROD_ID AND product_id=1")
    assert_eq "FF Milk consumed: -120.00" "-120.00" "$FF_QTY"

    # Verify total line count (1 milk usage + 1 product 12)
    LINE_COUNT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROD_ID")
    assert_eq "Transaction has 2 lines (milk usage + pouch milk)" "2" "$LINE_COUNT"
fi

# ══════════════════════════════════════════════════════════════
# TEST 2: Multi-pouch-type production
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 2. Multi-type pouch production → aggregated stock IN ──"

# Get second pouch product
POUCH_TYPE_ID2=$(sql "SELECT id FROM wp_mf_3_dp_pouch_products WHERE is_active=1 AND id > $POUCH_TYPE_ID LIMIT 1")
if [ -z "$POUCH_TYPE_ID2" ]; then
    POUCH_TYPE_ID2=$POUCH_TYPE_ID
    echo "  (Only one pouch type available, using same ID)"
fi

# 5 crates type 1 + 8 crates type 2 = 13 crates = 156 KG
POUCH_NOTES2="{\"pouch_lines\":[{\"pouch_type_id\":$POUCH_TYPE_ID,\"crate_count\":5},{\"pouch_type_id\":$POUCH_TYPE_ID2,\"crate_count\":8}]}"
RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"processing\",
    \"processing_type\": \"pouch_production\",
    \"party_id\": 1,
    \"milk_usage\": [{\"party_id\": $TEST_VENDOR_ID, \"qty\": 156}],
    \"notes\": $(echo "$POUCH_NOTES2" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
}")
PROD2_OK=$(json_val "$RES" "d.get('success', False)")
PROD2_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "Multi-type pouch production returns success" "True" "$PROD2_OK"

if [ -n "$PROD2_ID" ] && [ "$PROD2_ID" != "None" ]; then
    CREATED_TXN_IDS+=("$PROD2_ID")
    P12_QTY2=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROD2_ID AND product_id=$POUCH_PRODUCT_ID")
    assert_eq "Product 12 aggregated: 156.00 (13 crates × 12)" "156.00" "$P12_QTY2"
fi

# ══════════════════════════════════════════════════════════════
# TEST 3: Stock report includes product 12
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 3. Stock report shows product 12 ──"

STOCK_RES=$(api_get "/v4/stock?location_id=$TEST_LOC&from=$TEST_DATE&to=$TEST_DATE")
STOCK_OK=$(json_val "$STOCK_RES" "d.get('success', False)")
assert_eq "GET /v4/stock returns success" "True" "$STOCK_OK"

# Check product 12 is in the products list
HAS_P12=$(json_val "$STOCK_RES" "any(p['id']=='12' or p['id']==12 for p in d.get('data',{}).get('products',[]))")
assert_eq "Stock report includes product 12" "True" "$HAS_P12"

# Check stock flow report
FLOW_RES=$(api_get "/v4/stock-flow?location_id=$TEST_LOC&from=$TEST_DATE&to=$TEST_DATE")
FLOW_OK=$(json_val "$FLOW_RES" "d.get('success', False)")
assert_eq "GET /v4/stock-flow returns success" "True" "$FLOW_OK"

# Check product 12 has inward flow on test date
P12_IN=$(echo "$FLOW_RES" | python3 -c "import sys,json;d=json.load(sys.stdin);dates=d.get('data',{}).get('dates',[]);day=next((x for x in dates if x['date']=='$TEST_DATE'),None);flows=day.get('flows',{}) if day else {};p12=flows.get('12',flows.get(12,{}));print(p12.get('in',0))")
assert_eq "Stock flow shows product 12 IN = 276 (120+156)" "276" "$P12_IN"

# ══════════════════════════════════════════════════════════════
# TEST 4: Challan with pouch lines
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 4. Challan with pouch lines ──"

RES=$(api_post "/v4/challan" "{
    \"location_id\": $TEST_LOC,
    \"party_id\": $TEST_CUSTOMER_ID,
    \"challan_date\": \"$TEST_DATE\",
    \"delivery_address\": \"Test Address\",
    \"notes\": \"test pouch challan\",
    \"lines\": [{\"pouch_product_id\": $POUCH_TYPE_ID, \"qty\": 7, \"rate\": 100}]
}")
CH_OK=$(json_val "$RES" "d.get('success', False)")
CH_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
CH_NUM=$(json_val "$RES" "d.get('data',{}).get('challan_number','')")
assert_eq "Create pouch challan returns success" "True" "$CH_OK"
assert_neq "Challan has an ID" "" "$CH_ID"

if [ -n "$CH_ID" ] && [ "$CH_ID" != "None" ]; then
    CREATED_CHALLAN_IDS+=("$CH_ID")
    echo "  Created challan DC-$CH_NUM (id=$CH_ID)"

    # Verify challan line
    CL_POUCH=$(sql "SELECT pouch_product_id FROM wp_mf_4_challan_lines WHERE challan_id=$CH_ID LIMIT 1")
    assert_eq "Challan line has pouch_product_id=$POUCH_TYPE_ID" "$POUCH_TYPE_ID" "$CL_POUCH"

    CL_QTY=$(sql "SELECT qty FROM wp_mf_4_challan_lines WHERE challan_id=$CH_ID LIMIT 1")
    assert_eq "Challan line qty=7.00 crates" "7.00" "$CL_QTY"
fi

# ══════════════════════════════════════════════════════════════
# TEST 5: Invoice from pouch challan → stock OUT
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 5. Invoice from pouch challan → stock OUT ──"

RES=$(api_post "/v4/invoice" "{
    \"location_id\": $TEST_LOC,
    \"party_id\": $TEST_CUSTOMER_ID,
    \"invoice_date\": \"$TEST_DATE\",
    \"challan_ids\": [$CH_ID],
    \"notes\": \"test pouch invoice\"
}")
INV_OK=$(json_val "$RES" "d.get('success', False)")
INV_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
INV_NUM=$(json_val "$RES" "d.get('data',{}).get('invoice_number','')")
assert_eq "Create invoice returns success" "True" "$INV_OK"
assert_neq "Invoice has an ID" "" "$INV_ID"

if [ -n "$INV_ID" ] && [ "$INV_ID" != "None" ]; then
    CREATED_INVOICE_IDS+=("$INV_ID")
    echo "  Created invoice INV-$INV_NUM (id=$INV_ID)"

    # Verify challan marked as invoiced
    CH_STATUS=$(sql "SELECT status FROM wp_mf_4_challans WHERE id=$CH_ID")
    assert_eq "Challan status = invoiced" "invoiced" "$CH_STATUS"

    # Verify auto-created sale transaction for product 12
    SALE_TXN_ID=$(sql "SELECT id FROM wp_mf_4_transactions WHERE transaction_type='sale' AND notes LIKE '%invoice_id%$INV_ID%' AND location_id=$TEST_LOC AND transaction_date='$TEST_DATE' LIMIT 1")
    assert_neq "Sale transaction auto-created" "" "$SALE_TXN_ID"

    if [ -n "$SALE_TXN_ID" ]; then
        # Verify product 12 line with negative qty = -(7 crates * 12) = -84
        SALE_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$SALE_TXN_ID AND product_id=$POUCH_PRODUCT_ID")
        assert_eq "Sale line product 12 qty = -84.00 (7 crates × 12, negative)" "-84.00" "$SALE_QTY"

        # Verify sale is linked to correct customer
        SALE_PARTY=$(sql "SELECT party_id FROM wp_mf_4_transactions WHERE id=$SALE_TXN_ID")
        assert_eq "Sale transaction party_id = test customer" "$TEST_CUSTOMER_ID" "$SALE_PARTY"

        # Verify sale date matches invoice date
        SALE_DATE=$(sql "SELECT transaction_date FROM wp_mf_4_transactions WHERE id=$SALE_TXN_ID")
        assert_eq "Sale transaction date = $TEST_DATE" "$TEST_DATE" "$SALE_DATE"
    fi

    # Check stock flow shows the OUT
    FLOW_RES2=$(api_get "/v4/stock-flow?location_id=$TEST_LOC&from=$TEST_DATE&to=$TEST_DATE")
    P12_OUT=$(echo "$FLOW_RES2" | python3 -c "import sys,json;d=json.load(sys.stdin);dates=d.get('data',{}).get('dates',[]);day=next((x for x in dates if x['date']=='$TEST_DATE'),None);flows=day.get('flows',{}) if day else {};p12=flows.get('12',flows.get(12,{}));print(p12.get('out',0))")
    assert_eq "Stock flow shows product 12 OUT = 84" "84" "$P12_OUT"
fi

# ══════════════════════════════════════════════════════════════
# TEST 6: Delete invoice → sale transaction removed, stock restored
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 6. Delete invoice → stock restored ──"

if [ -n "$INV_ID" ] && [ "$INV_ID" != "None" ]; then
    # Record sale txn ID before deleting invoice
    SALE_TXN_BEFORE=$(sql "SELECT id FROM wp_mf_4_transactions WHERE transaction_type='sale' AND notes LIKE '%invoice_id%$INV_ID%' AND location_id=$TEST_LOC AND transaction_date='$TEST_DATE' LIMIT 1")

    DEL_RES=$(api_delete "/v4/invoice/$INV_ID")
    DEL_OK=$(json_val "$DEL_RES" "d.get('success', False)")
    assert_eq "DELETE invoice returns success" "True" "$DEL_OK"

    # Verify sale transaction is gone
    if [ -n "$SALE_TXN_BEFORE" ]; then
        SALE_GONE=$(sql "SELECT COUNT(*) FROM wp_mf_4_transactions WHERE id=$SALE_TXN_BEFORE")
        assert_eq "Sale transaction $SALE_TXN_BEFORE deleted" "0" "$SALE_GONE"

        SALE_LINES_GONE=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$SALE_TXN_BEFORE")
        assert_eq "Sale transaction lines deleted" "0" "$SALE_LINES_GONE"
    fi

    # Verify challan reverted to pending
    CH_STATUS2=$(sql "SELECT status FROM wp_mf_4_challans WHERE id=$CH_ID")
    assert_eq "Challan reverted to pending" "pending" "$CH_STATUS2"

    # Remove from cleanup since already deleted
    CREATED_INVOICE_IDS=()
fi

# ══════════════════════════════════════════════════════════════
# TEST 7: Pouch type CRUD
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 7. Pouch type CRUD ──"

# Create
RES=$(api_post "/pouch-products" "{
    \"name\": \"TEST_POUCH_TYPE_999\",
    \"milk_per_pouch\": 0.5,
    \"pouches_per_crate\": 20,
    \"crate_rate\": 450.00
}")
PT_OK=$(json_val "$RES" "d.get('success', False)")
PT_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "Create pouch type returns success" "True" "$PT_OK"
assert_neq "Pouch type has an ID" "" "$PT_ID"

if [ -n "$PT_ID" ] && [ "$PT_ID" != "None" ]; then
    # Verify saved correctly
    PT_RATE=$(sql "SELECT crate_rate FROM wp_mf_3_dp_pouch_products WHERE id=$PT_ID")
    assert_eq "Crate rate saved = 450.00" "450.00" "$PT_RATE"

    PT_PPC=$(sql "SELECT pouches_per_crate FROM wp_mf_3_dp_pouch_products WHERE id=$PT_ID")
    assert_eq "Pouches per crate = 20" "20" "$PT_PPC"

    PT_MILK=$(sql "SELECT milk_per_pouch FROM wp_mf_3_dp_pouch_products WHERE id=$PT_ID")
    assert_eq "Milk per pouch = 0.50" "0.50" "$PT_MILK"

    # Update
    RES=$(api_post "/pouch-products/$PT_ID" "{
        \"crate_rate\": 500.00,
        \"is_active\": 0
    }")
    UPD_OK=$(json_val "$RES" "d.get('success', False)")
    assert_eq "Update pouch type returns success" "True" "$UPD_OK"

    PT_RATE2=$(sql "SELECT crate_rate FROM wp_mf_3_dp_pouch_products WHERE id=$PT_ID")
    assert_eq "Updated crate rate = 500.00" "500.00" "$PT_RATE2"

    PT_ACTIVE=$(sql "SELECT is_active FROM wp_mf_3_dp_pouch_products WHERE id=$PT_ID")
    assert_eq "Deactivated (is_active=0)" "0" "$PT_ACTIVE"
fi

# ══════════════════════════════════════════════════════════════
# TEST 8: Company settings endpoint
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 8. Company settings ──"

CS_RES=$(api_get "/company-settings")
CS_OK=$(json_val "$CS_RES" "d.get('success', False)")
assert_eq "GET /company-settings returns success" "True" "$CS_OK"

CS_NAME=$(json_val "$CS_RES" "d.get('data',{}).get('company_name','')")
assert_neq "Company name is not empty" "" "$CS_NAME"

# ══════════════════════════════════════════════════════════════
# CLEANUP
# ══════════════════════════════════════════════════════════════

echo ""
echo "── Cleanup ──"

# Delete test challan lines and challans
for CID in "${CREATED_CHALLAN_IDS[@]}"; do
    if [ -n "$CID" ] && [ "$CID" != "None" ]; then
        sql "DELETE FROM wp_mf_4_challan_lines WHERE challan_id=$CID"
        sql "DELETE FROM wp_mf_4_challans WHERE id=$CID"
    fi
done
echo "  Cleaned ${#CREATED_CHALLAN_IDS[@]} challans"

# Delete test invoices (and their auto-created sale txns)
for IID in "${CREATED_INVOICE_IDS[@]}"; do
    if [ -n "$IID" ] && [ "$IID" != "None" ]; then
        # Find and delete auto-created sale transactions
        STIDS=$(sql "SELECT id FROM wp_mf_4_transactions WHERE transaction_type='sale' AND notes LIKE '%\"invoice_id\":$IID%'")
        for STID in $STIDS; do
            sql "DELETE FROM wp_mf_4_transaction_lines WHERE transaction_id=$STID"
            sql "DELETE FROM wp_mf_4_transactions WHERE id=$STID"
        done
        sql "DELETE FROM wp_mf_4_invoices WHERE id=$IID"
    fi
done
echo "  Cleaned ${#CREATED_INVOICE_IDS[@]} invoices"

# Delete test transactions
for TID in "${CREATED_TXN_IDS[@]}"; do
    if [ -n "$TID" ] && [ "$TID" != "None" ]; then
        sql "DELETE FROM wp_mf_4_transaction_lines WHERE transaction_id=$TID"
        sql "DELETE FROM wp_mf_4_transactions WHERE id=$TID"
    fi
done
echo "  Cleaned ${#CREATED_TXN_IDS[@]} transactions"

# Delete test pouch type
if [ -n "$PT_ID" ] && [ "$PT_ID" != "None" ]; then
    sql "DELETE FROM wp_mf_3_dp_pouch_products WHERE id=$PT_ID"
    echo "  Cleaned test pouch type id=$PT_ID"
fi

# Delete test parties
sql "DELETE FROM wp_mf_3_dp_customer_products WHERE party_id IN (SELECT id FROM wp_mf_4_parties WHERE name IN ('TEST_POUCH_VENDOR','TEST_POUCH_CUSTOMER'))"
sql "DELETE FROM wp_mf_4_parties WHERE name IN ('TEST_POUCH_VENDOR','TEST_POUCH_CUSTOMER')"
echo "  Cleaned test parties"

# ══════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════"
echo "  TOTAL: $TOTAL"
echo "  PASS:  $PASS"
echo "  FAIL:  $FAIL"
echo "═══════════════════════════════"

[ $FAIL -eq 0 ] && exit 0 || exit 1
