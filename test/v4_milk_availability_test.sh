#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# V4 Milk Availability + Source Transaction ID Test
# ═══════════════════════════════════════════════════════════════
# Tests in TEST location (id=3). Creates purchases, checks
# availability, creates processing, verifies source_transaction_id
# and updated availability. Cleans up at end.

set -e

BASE="https://www.nkp45fd.fanol.xyz/wp-json"
PEM="/Users/abhayapat/git-repos/pem/awsls001.pem"
HOST="bitnami@www.nkp45fd.fanol.xyz"
DB_USER="bn_wordpress"
DB_PASS="51c25c040d0193219ba3e75e53badb316eb957e023efe3811c72234969c70014"
DB="bitnami_wordpress"

TEST_LOC=3
TEST_DATE_1="2099-11-01"
TEST_DATE_2="2099-11-02"
TEST_DATE_3="2099-11-03"
CREATED_IDS=()

PASS=0; FAIL=0; TOTAL=0

sql() { ssh -i "$PEM" "$HOST" "mysql -u $DB_USER -p'$DB_PASS' $DB -N -e \"$1\"" 2>/dev/null; }

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

echo "═══ Milk Availability + Source Transaction Test ═══"
echo ""

# ── Auth ──
echo "── Auth ──"
AUTH_RES=$(curl -s -X POST "$BASE/dairy/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"a1p1","password":"DpFT$56%Def"}')
TOKEN=$(echo "$AUTH_RES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('token',''))" 2>/dev/null)
if [ -z "$TOKEN" ]; then
    echo "FATAL: Auth failed. Response: $AUTH_RES"
    exit 1
fi
echo "  Authenticated"

api_get() { curl -s -H "Authorization: Bearer $TOKEN" "$BASE/dairy/v1$1"; }
api_post() { curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$2" "$BASE/dairy/v1$1"; }
jv() { echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print($2)" 2>/dev/null; }

# ── Setup: ensure test vendor ──
echo ""
echo "── Setup ──"
TV_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_MILK_VENDOR' AND party_type='vendor' LIMIT 1")
if [ -z "$TV_ID" ]; then
    sql "INSERT INTO wp_mf_4_parties (name, party_type, is_active) VALUES ('TEST_MILK_VENDOR', 'vendor', 1)"
    TV_ID=$(sql "SELECT id FROM wp_mf_4_parties WHERE name='TEST_MILK_VENDOR' AND party_type='vendor' LIMIT 1")
fi
echo "  Test vendor party_id=$TV_ID"

# ══════════════════════════════════════════════════════════════
# TEST 1: Purchase 500 KG on Nov 1
# ══════════════════════════════════════════════════════════════
echo ""
echo "── 1. Purchase 500 KG FF Milk on $TEST_DATE_1 ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE_1\",
    \"transaction_type\": \"purchase\",
    \"party_id\": $TV_ID,
    \"lines\": [{\"product_id\": 1, \"qty\": 500, \"rate\": 40.00, \"snf\": 8.5, \"fat\": 6.0}]
}")
P1_OK=$(jv "$RES" "d.get('success', False)")
P1_ID=$(jv "$RES" "d.get('data',{}).get('id','')")
assert_eq "Purchase 1 success" "True" "$P1_OK"
echo "  Purchase 1 txn_id=$P1_ID"
[ "$P1_ID" != "None" ] && [ -n "$P1_ID" ] && CREATED_IDS+=("$P1_ID")

# ══════════════════════════════════════════════════════════════
# TEST 2: Purchase 300 KG on Nov 2
# ══════════════════════════════════════════════════════════════
echo ""
echo "── 2. Purchase 300 KG FF Milk on $TEST_DATE_2 ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE_2\",
    \"transaction_type\": \"purchase\",
    \"party_id\": $TV_ID,
    \"lines\": [{\"product_id\": 1, \"qty\": 300, \"rate\": 42.00, \"snf\": 8.6, \"fat\": 6.1}]
}")
P2_OK=$(jv "$RES" "d.get('success', False)")
P2_ID=$(jv "$RES" "d.get('data',{}).get('id','')")
assert_eq "Purchase 2 success" "True" "$P2_OK"
echo "  Purchase 2 txn_id=$P2_ID"
[ "$P2_ID" != "None" ] && [ -n "$P2_ID" ] && CREATED_IDS+=("$P2_ID")

# ══════════════════════════════════════════════════════════════
# TEST 3: Check availability as of Nov 2 — should be 800 KG
# ══════════════════════════════════════════════════════════════
echo ""
echo "── 3. Availability as of $TEST_DATE_2 (before processing) ──"

AVAIL=$(api_get "/v4/milk-availability?location_id=$TEST_LOC&as_of=$TEST_DATE_2")
AVAIL_OK=$(jv "$AVAIL" "d.get('success', False)")
assert_eq "Availability endpoint success" "True" "$AVAIL_OK"

AVAIL_KG=$(jv "$AVAIL" "[r for r in d.get('data',[]) if str(r.get('party_id'))==str($TV_ID)][0]['available_kg'] if any(str(r.get('party_id'))==str($TV_ID) for r in d.get('data',[])) else 0")
assert_eq "Available = 800 KG (500 + 300)" "800" "$AVAIL_KG"

# ══════════════════════════════════════════════════════════════
# TEST 4: Check availability as of Nov 1 — should be 500 KG only
# ══════════════════════════════════════════════════════════════
echo ""
echo "── 4. Availability as of $TEST_DATE_1 (only first purchase) ──"

AVAIL1=$(api_get "/v4/milk-availability?location_id=$TEST_LOC&as_of=$TEST_DATE_1")
AVAIL1_KG=$(jv "$AVAIL1" "[r for r in d.get('data',[]) if str(r.get('party_id'))==str($TV_ID)][0]['available_kg'] if any(str(r.get('party_id'))==str($TV_ID) for r in d.get('data',[])) else 0")
assert_eq "Available as of Nov 1 = 500 KG" "500" "$AVAIL1_KG"

# ══════════════════════════════════════════════════════════════
# TEST 5: Process 200 KG on Nov 2 — should link to Purchase 1 (FIFO)
# ══════════════════════════════════════════════════════════════
echo ""
echo "── 5. Process 200 KG on $TEST_DATE_2 (should FIFO to purchase 1) ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE_2\",
    \"transaction_type\": \"processing\",
    \"processing_type\": \"ff_milk_processing\",
    \"milk_usage\": [{\"party_id\": $TV_ID, \"qty\": 200}],
    \"outputs\": [
        {\"product_id\": 2, \"qty\": 185, \"snf\": 9.0},
        {\"product_id\": 3, \"qty\": 15, \"fat\": 5.5}
    ]
}")
PROC_OK=$(jv "$RES" "d.get('success', False)")
PROC_ID=$(jv "$RES" "d.get('data',{}).get('id','')")
assert_eq "Processing success" "True" "$PROC_OK"
echo "  Processing txn_id=$PROC_ID"
[ "$PROC_ID" != "None" ] && [ -n "$PROC_ID" ] && CREATED_IDS+=("$PROC_ID")

# Verify source_transaction_id points to Purchase 1
if [ -n "$PROC_ID" ] && [ "$PROC_ID" != "None" ]; then
    SRC_ID=$(sql "SELECT source_transaction_id FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROC_ID AND product_id=1")
    assert_eq "source_transaction_id = Purchase 1 ($P1_ID)" "$P1_ID" "$SRC_ID"
fi

# ══════════════════════════════════════════════════════════════
# TEST 6: Availability after processing — should be 600 KG (800-200)
# ══════════════════════════════════════════════════════════════
echo ""
echo "── 6. Availability after processing ──"

AVAIL2=$(api_get "/v4/milk-availability?location_id=$TEST_LOC&as_of=$TEST_DATE_2")
AVAIL2_KG=$(jv "$AVAIL2" "[r for r in d.get('data',[]) if str(r.get('party_id'))==str($TV_ID)][0]['available_kg'] if any(str(r.get('party_id'))==str($TV_ID) for r in d.get('data',[])) else 0")
assert_eq "Available after processing = 600 KG (800 - 200)" "600" "$AVAIL2_KG"

# ══════════════════════════════════════════════════════════════
# TEST 7: Process 400 KG more — should still FIFO (300 left in P1, then P2)
# ══════════════════════════════════════════════════════════════
echo ""
echo "── 7. Process 400 KG on $TEST_DATE_3 (exhausts P1, dips into P2) ──"

RES=$(api_post "/v4/transaction" "{
    \"location_id\": $TEST_LOC,
    \"transaction_date\": \"$TEST_DATE_3\",
    \"transaction_type\": \"processing\",
    \"processing_type\": \"ff_milk_processing\",
    \"milk_usage\": [{\"party_id\": $TV_ID, \"qty\": 400}],
    \"outputs\": [
        {\"product_id\": 2, \"qty\": 370, \"snf\": 9.0},
        {\"product_id\": 3, \"qty\": 30, \"fat\": 5.5}
    ]
}")
PROC2_OK=$(jv "$RES" "d.get('success', False)")
PROC2_ID=$(jv "$RES" "d.get('data',{}).get('id','')")
assert_eq "Processing 2 success" "True" "$PROC2_OK"
echo "  Processing 2 txn_id=$PROC2_ID"
[ "$PROC2_ID" != "None" ] && [ -n "$PROC2_ID" ] && CREATED_IDS+=("$PROC2_ID")

# Source should be P1 (still has 300 remaining before this consumption)
if [ -n "$PROC2_ID" ] && [ "$PROC2_ID" != "None" ]; then
    SRC2_ID=$(sql "SELECT source_transaction_id FROM wp_mf_4_transaction_lines WHERE transaction_id=$PROC2_ID AND product_id=1")
    assert_eq "source_transaction_id = P1 ($P1_ID) (300 remaining in P1)" "$P1_ID" "$SRC2_ID"
fi

# ══════════════════════════════════════════════════════════════
# TEST 8: Availability after second processing — should be 200 KG
# ══════════════════════════════════════════════════════════════
echo ""
echo "── 8. Availability after second processing ──"

AVAIL3=$(api_get "/v4/milk-availability?location_id=$TEST_LOC&as_of=$TEST_DATE_3")
AVAIL3_KG=$(jv "$AVAIL3" "[r for r in d.get('data',[]) if str(r.get('party_id'))==str($TV_ID)][0]['available_kg'] if any(str(r.get('party_id'))==str($TV_ID) for r in d.get('data',[])) else 0")
assert_eq "Available after 2nd processing = 200 KG (800 - 200 - 400)" "200" "$AVAIL3_KG"

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
sql "DELETE FROM wp_mf_4_parties WHERE name='TEST_MILK_VENDOR'"
echo "  Cleaned up ${#CREATED_IDS[@]} transactions + test vendor"

# ══════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════"
echo "  TOTAL: $TOTAL"
echo "  PASS:  $PASS"
echo "  FAIL:  $FAIL"
echo "═══════════════════════════════"

[ $FAIL -eq 0 ] && exit 0 || exit 1
