#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# V4 API Test Suite — Tests REST endpoints end-to-end
# ═══════════════════════════════════════════════════════════════
#
# Tests the V4 transaction API via HTTP calls against the live server.
# Uses the TEST location (id=3) to avoid polluting real data.
# All test transactions are cleaned up at the end.
#
# Usage: bash test/v4_api_test.sh

set -e

# ── Config ────────────────────────────────────────────────────
BASE="https://www.nkp45fd.fanol.xyz/wp-json"
APP_USER="a1p1"
APP_PASS='DpFT$56%Def'
PEM="/Users/abhayapat/git-repos/pem/awsls001.pem"
HOST="bitnami@www.nkp45fd.fanol.xyz"
DB_USER="bn_wordpress"
DB_PASS="51c25c040d0193219ba3e75e53badb316eb957e023efe3811c72234969c70014"
DB="bitnami_wordpress"

TEST_LOC=3      # TEST location
TEST_DATE="2099-12-31"  # Far future date, easy to clean up
CREATED_IDS=()  # Track transaction IDs for cleanup

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

assert_contains() {
    TOTAL=$((TOTAL + 1))
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

# ── Auth ──────────────────────────────────────────────────────

echo "═══ V4 API Test Suite ═══"
echo ""
echo "── Authenticating ──"

TOKEN=$(curl -s -X POST "$BASE/jwt-auth/v1/token" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$APP_USER\",\"password\":\"$APP_PASS\"}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")

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

# ── Ensure test vendor exists in V4 parties ───────────────────

echo ""
echo "── Setup ──"

TEST_VENDOR_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_API_VENDOR' AND party_type='vendor' LIMIT 1")
if [ -z "$TEST_VENDOR_ID" ]; then
    sql "INSERT INTO wp_mf_4_parties (name, party_type, is_active) VALUES ('TEST_API_VENDOR', 'vendor', 1)"
    TEST_VENDOR_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_API_VENDOR' AND party_type='vendor' LIMIT 1")
fi
echo "  Test vendor party_id=$TEST_VENDOR_ID"

TEST_CUSTOMER_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_API_CUSTOMER' AND party_type='customer' LIMIT 1")
if [ -z "$TEST_CUSTOMER_ID" ]; then
    sql "INSERT INTO wp_mf_4_parties (name, party_type, is_active) VALUES ('TEST_API_CUSTOMER', 'customer', 1)"
    TEST_CUSTOMER_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_API_CUSTOMER' AND party_type='customer' LIMIT 1")
fi
echo "  Test customer party_id=$TEST_CUSTOMER_ID"

# ══════════════════════════════════════════════════════════════
# TEST GROUP 1: Products endpoint
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 1. Products ──"

PRODUCTS=$(api_get "/products")
PROD_SUCCESS=$(json_val "$PRODUCTS" "d.get('success', False)")
assert_eq "GET /products returns success" "True" "$PROD_SUCCESS"

# Products 7, 8, 9 should NOT be in the active list
PROD_NAMES=$(json_val "$PRODUCTS" "','.join([p['name'] for p in d.get('data',[])])")
TOTAL=$((TOTAL + 1))
if echo "$PROD_NAMES" | grep -qE "SMP|Protein|Culture"; then
    echo "  FAIL: Deactivated products (SMP/Protein/Culture) should not appear"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: Deactivated products excluded"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 2: V4 Parties endpoint
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 2. V4 Parties ──"

PARTIES=$(api_get "/v4/parties?party_type=vendor")
PARTIES_OK=$(json_val "$PARTIES" "d.get('success', False)")
assert_eq "GET /v4/parties returns success" "True" "$PARTIES_OK"

PARTY_COUNT=$(json_val "$PARTIES" "len(d.get('data',[]))")
TOTAL=$((TOTAL + 1))
if [ "$PARTY_COUNT" -gt 0 ] 2>/dev/null; then
    echo "  PASS: Got $PARTY_COUNT vendor parties"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No vendor parties returned"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 3: FF Milk Purchase (positive qty)
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 3. FF Milk Purchase (positive qty) ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"purchase\",
    \"party_id\": $TEST_VENDOR_ID,
    \"lines\": [{\"product_id\": 1, \"qty\": 100, \"rate\": 45.50, \"snf\": 8.5, \"fat\": 6.2}]
}")
PURCHASE_OK=$(json_val "$RES" "d.get('success', False)")
PURCHASE_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "POST purchase returns success" "True" "$PURCHASE_OK"
assert_neq "POST purchase returns an ID" "" "$PURCHASE_ID"

if [ -n "$PURCHASE_ID" ] && [ "$PURCHASE_ID" != "None" ]; then
    CREATED_IDS+=("$PURCHASE_ID")
    # Verify in DB
    DB_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$PURCHASE_ID LIMIT 1")
    assert_eq "Purchase line stored with qty=100.00" "100.00" "$DB_QTY"

    DB_RATE=$(sql "SELECT rate FROM wp_mf_4_transaction_lines WHERE transaction_id=$PURCHASE_ID LIMIT 1")
    assert_eq "Purchase line rate=45.50" "45.50" "$DB_RATE"

    DB_SNF=$(sql "SELECT snf FROM wp_mf_4_transaction_lines WHERE transaction_id=$PURCHASE_ID LIMIT 1")
    assert_eq "Purchase line snf=8.5" "8.5" "$DB_SNF"
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 4: FF Milk Purchase (NEGATIVE qty — reversal)
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 4. FF Milk Purchase (negative qty — reversal) ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"purchase\",
    \"party_id\": $TEST_VENDOR_ID,
    \"lines\": [{\"product_id\": 1, \"qty\": -100, \"rate\": 45.50, \"snf\": 8.5, \"fat\": 6.2}]
}")
REV_OK=$(json_val "$RES" "d.get('success', False)")
REV_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "POST negative purchase returns success" "True" "$REV_OK"
assert_neq "POST negative purchase returns an ID" "" "$REV_ID"

if [ -n "$REV_ID" ] && [ "$REV_ID" != "None" ]; then
    CREATED_IDS+=("$REV_ID")
    DB_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$REV_ID LIMIT 1")
    assert_eq "Reversal line stored with qty=-100.00" "-100.00" "$DB_QTY"
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 5: Sale (positive qty, stored as negative)
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 5. Sale (positive qty → stored negative) ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"sale\",
    \"party_id\": $TEST_CUSTOMER_ID,
    \"lines\": [{\"product_id\": 2, \"qty\": 50, \"rate\": 30.00}]
}")
SALE_OK=$(json_val "$RES" "d.get('success', False)")
SALE_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "POST sale returns success" "True" "$SALE_OK"
assert_neq "POST sale returns an ID" "" "$SALE_ID"

if [ -n "$SALE_ID" ] && [ "$SALE_ID" != "None" ]; then
    CREATED_IDS+=("$SALE_ID")
    DB_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$SALE_ID LIMIT 1")
    assert_eq "Sale line stored with qty=-50.00 (negative)" "-50.00" "$DB_QTY"
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 6: Sale reversal (negative qty → stored positive)
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 6. Sale reversal (negative qty → stored positive) ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"sale\",
    \"party_id\": $TEST_CUSTOMER_ID,
    \"lines\": [{\"product_id\": 2, \"qty\": -50, \"rate\": 30.00}]
}")
SREV_OK=$(json_val "$RES" "d.get('success', False)")
SREV_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "POST sale reversal returns success" "True" "$SREV_OK"
assert_neq "POST sale reversal returns an ID" "" "$SREV_ID"

if [ -n "$SREV_ID" ] && [ "$SREV_ID" != "None" ]; then
    CREATED_IDS+=("$SREV_ID")
    DB_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$SREV_ID LIMIT 1")
    assert_eq "Sale reversal stored with qty=50.00 (positive)" "50.00" "$DB_QTY"
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 7: Processing (milk_usage + outputs)
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 7. FF Milk Processing ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"processing\",
    \"processing_type\": \"ff_milk_processing\",
    \"milk_usage\": [{\"party_id\": $TEST_VENDOR_ID, \"qty\": 200}],
    \"outputs\": [
        {\"product_id\": 2, \"qty\": 180, \"snf\": 9.0},
        {\"product_id\": 3, \"qty\": 20, \"fat\": 5.5}
    ]
}")
PROC_OK=$(json_val "$RES" "d.get('success', False)")
PROC_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "POST processing returns success" "True" "$PROC_OK"
assert_neq "POST processing returns an ID" "" "$PROC_ID"

if [ -n "$PROC_ID" ] && [ "$PROC_ID" != "None" ]; then
    CREATED_IDS+=("$PROC_ID")
    LINE_COUNT=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROC_ID")
    assert_eq "Processing has 3 lines (1 milk_usage + 2 outputs)" "3" "$LINE_COUNT"

    # milk_usage should be stored as negative
    MILK_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROC_ID AND product_id=1")
    assert_eq "Milk usage stored as -200.00" "-200.00" "$MILK_QTY"

    # outputs should be positive
    SKIM_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROC_ID AND product_id=2")
    assert_eq "Skim milk output stored as 180.00" "180.00" "$SKIM_QTY"
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 8: Processing reversal (negative milk_usage + negative outputs)
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 8. Processing reversal (negative quantities) ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"processing\",
    \"processing_type\": \"ff_milk_processing\",
    \"milk_usage\": [{\"party_id\": $TEST_VENDOR_ID, \"qty\": -200}],
    \"outputs\": [
        {\"product_id\": 2, \"qty\": -180, \"snf\": 9.0},
        {\"product_id\": 3, \"qty\": -20, \"fat\": 5.5}
    ]
}")
PREV_OK=$(json_val "$RES" "d.get('success', False)")
PREV_ID=$(json_val "$RES" "d.get('data',{}).get('id','')")
assert_eq "POST processing reversal returns success" "True" "$PREV_OK"
assert_neq "POST processing reversal returns an ID" "" "$PREV_ID"

if [ -n "$PREV_ID" ] && [ "$PREV_ID" != "None" ]; then
    CREATED_IDS+=("$PREV_ID")
    # milk_usage with -200 → stored as -(-200) = +200 (milk returned to stock)
    MILK_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$PREV_ID AND product_id=1")
    assert_eq "Reversal: milk returned to stock as +200.00" "200.00" "$MILK_QTY"

    # outputs with -180 → stored as -180 (skim milk removed from stock)
    SKIM_QTY=$(sql "SELECT qty FROM wp_mf_4_transaction_lines WHERE transaction_id=$PREV_ID AND product_id=2")
    assert_eq "Reversal: skim milk removed as -180.00" "-180.00" "$SKIM_QTY"
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 9: Zero qty rejected
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 9. Zero qty rejected ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE\",
    \"transaction_type\": \"purchase\",
    \"party_id\": $TEST_VENDOR_ID,
    \"lines\": [{\"product_id\": 1, \"qty\": 0, \"rate\": 45.50}]
}")
ZERO_OK=$(json_val "$RES" "d.get('success', False)")
assert_eq "POST with qty=0 returns failure" "False" "$ZERO_OK"

# ══════════════════════════════════════════════════════════════
# TEST GROUP 10: GET transactions
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 10. GET transactions ──"

TXN_RES=$(api_get "/v4/transactions?location_id=$TEST_LOC&from=$TEST_DATE&to=$TEST_DATE")
TXN_OK=$(json_val "$TXN_RES" "d.get('success', False)")
assert_eq "GET /v4/transactions returns success" "True" "$TXN_OK"

TXN_COUNT=$(json_val "$TXN_RES" "len(d.get('data',{}).get('rows',[]))")
TOTAL=$((TOTAL + 1))
if [ "$TXN_COUNT" -gt 0 ] 2>/dev/null; then
    echo "  PASS: Got $TXN_COUNT transactions for test date"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No transactions returned for test date"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 11: DELETE transaction
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 11. DELETE transaction ──"

if [ ${#CREATED_IDS[@]} -gt 0 ]; then
    DEL_ID=${CREATED_IDS[0]}
    DEL_RES=$(api_delete "/v4/transaction/$DEL_ID")
    DEL_OK=$(json_val "$DEL_RES" "d.get('success', False)")
    assert_eq "DELETE /v4/transaction/$DEL_ID returns success" "True" "$DEL_OK"

    # Verify gone from DB
    DEL_CHECK=$(sql "SELECT COUNT(*) FROM wp_mf_4_transactions WHERE id=$DEL_ID")
    assert_eq "Transaction $DEL_ID removed from DB" "0" "$DEL_CHECK"

    DEL_LINES=$(sql "SELECT COUNT(*) FROM wp_mf_4_transaction_lines WHERE transaction_id=$DEL_ID")
    assert_eq "Transaction lines also removed" "0" "$DEL_LINES"

    # Remove from cleanup list since already deleted
    CREATED_IDS=("${CREATED_IDS[@]:1}")
fi

# ══════════════════════════════════════════════════════════════
# TEST GROUP 12: V4 Stock
# ══════════════════════════════════════════════════════════════

echo ""
echo "── 12. V4 Stock ──"

STOCK_RES=$(api_get "/v4/stock?location_id=$TEST_LOC")
STOCK_OK=$(json_val "$STOCK_RES" "d.get('success', False)")
assert_eq "GET /v4/stock returns success" "True" "$STOCK_OK"

# ══════════════════════════════════════════════════════════════
# CLEANUP
# ══════════════════════════════════════════════════════════════

echo ""
echo "── Cleanup ──"

for TID in "${CREATED_IDS[@]}"; do
    if [ -n "$TID" ] && [ "$TID" != "None" ]; then
        sql "DELETE FROM wp_mf_4_transaction_lines WHERE transaction_id=$TID"
        sql "DELETE FROM wp_mf_4_transactions WHERE id=$TID"
    fi
done

# Clean up test parties
sql "DELETE FROM wp_mf_4_parties WHERE name IN ('TEST_API_VENDOR','TEST_API_CUSTOMER')"

echo "  Cleaned up ${#CREATED_IDS[@]} test transactions + test parties"

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
