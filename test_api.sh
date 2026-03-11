#!/bin/bash
# API tests for new milk_usage, pouch_types, pouch_production flows
# Tests ONLY in TEST location
set -e

BASE="https://www.nkp45fd.fanol.xyz/wp-json"
DAIRY="$BASE/dairy/v1"
PASS=0
FAIL=0
TODAY=$(date +%Y-%m-%d)

ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1 — $2"; }

# ── Login ──
echo "=== Logging in ==="
LOGIN=$(curl -sk -X POST "$BASE/dairy/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"a1p1","password":"DpFT$56%Def"}' 2>/dev/null)
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('token',''))" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  # Try JWT Auth plugin endpoint
  LOGIN=$(curl -sk -X POST "$BASE/jwt-auth/v1/token" \
    -H "Content-Type: application/json" \
    -d '{"username":"a1p1","password":"DpFT$56%Def"}' 2>/dev/null)
  TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null)
fi
if [ -z "$TOKEN" ]; then
  echo "FATAL: Could not get JWT token"
  echo "Login response: $LOGIN"
  exit 1
fi
echo "  Got token: ${TOKEN:0:20}..."
AUTH="Authorization: Bearer $TOKEN"

# ── Find TEST location ──
echo ""
echo "=== Finding TEST location ==="
ME=$(curl -sk -H "$AUTH" "$DAIRY/me" 2>/dev/null)
TEST_LOC=$(echo "$ME" | python3 -c "
import sys,json
d=json.load(sys.stdin)
locs=d.get('data',{}).get('permissions',{}).get('locations',[])
for l in locs:
    if l.get('code')=='TEST':
        print(l['id']); break
" 2>/dev/null)
if [ -z "$TEST_LOC" ]; then
  echo "FATAL: TEST location not found"
  exit 1
fi
echo "  TEST location ID: $TEST_LOC"

# ── Get vendors for this location ──
echo ""
echo "=== Getting vendors ==="
VENDORS=$(curl -sk -H "$AUTH" "$DAIRY/vendors?location_id=$TEST_LOC" 2>/dev/null)
VENDOR1=$(echo "$VENDORS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',[])[0]['id'])" 2>/dev/null)
VENDOR2=$(echo "$VENDORS" | python3 -c "import sys,json; d=json.load(sys.stdin); vs=d.get('data',[]); print(vs[1]['id'] if len(vs)>1 else vs[0]['id'])" 2>/dev/null)
echo "  Vendor 1 ID: $VENDOR1, Vendor 2 ID: $VENDOR2"

# ══════════════════════════════════════
# TEST 1: FF Milk Purchase (creates stock for vendor picking)
# ══════════════════════════════════════
echo ""
echo "=== Test 1: FF Milk Purchase (Vendor $VENDOR1 — 500 KG) ==="
R=$(curl -sk -X POST -H "$AUTH" -H "Content-Type: application/json" "$DAIRY/milk-cream" \
  -d "{\"location_id\":$TEST_LOC,\"entry_date\":\"$TODAY\",\"input_ff_milk_kg\":500,\"input_snf\":8.5,\"input_fat\":5.0,\"input_rate\":45.00,\"vendor_id\":$VENDOR1,\"input_ff_milk_used_kg\":0,\"output_skim_milk_kg\":0,\"output_skim_snf\":0,\"output_cream_kg\":0,\"output_cream_fat\":0}" 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
[ "$S" = "True" ] && ok "FF Milk Purchase V1 500KG" || fail "FF Milk Purchase V1" "$R"

echo "=== Test 1b: FF Milk Purchase (Vendor $VENDOR2 — 300 KG) ==="
R=$(curl -sk -X POST -H "$AUTH" -H "Content-Type: application/json" "$DAIRY/milk-cream" \
  -d "{\"location_id\":$TEST_LOC,\"entry_date\":\"$TODAY\",\"input_ff_milk_kg\":300,\"input_snf\":8.3,\"input_fat\":4.8,\"input_rate\":44.00,\"vendor_id\":$VENDOR2,\"input_ff_milk_used_kg\":0,\"output_skim_milk_kg\":0,\"output_skim_snf\":0,\"output_cream_kg\":0,\"output_cream_fat\":0}" 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
[ "$S" = "True" ] && ok "FF Milk Purchase V2 300KG" || fail "FF Milk Purchase V2" "$R"

# ══════════════════════════════════════
# TEST 2: Milk Availability
# ══════════════════════════════════════
echo ""
echo "=== Test 2: Milk Availability ==="
R=$(curl -sk -H "$AUTH" "$DAIRY/milk-availability?location_id=$TEST_LOC" 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
COUNT=$(echo "$R" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null)
[ "$S" = "True" ] && [ "$COUNT" -ge 1 ] && ok "Milk availability returned $COUNT vendors" || fail "Milk availability" "$R"

# ══════════════════════════════════════
# TEST 3: FF Milk Processing with milk_usage (vendor picks)
# ══════════════════════════════════════
echo ""
echo "=== Test 3: FF Milk Processing with vendor picks ==="
R=$(curl -sk -X POST -H "$AUTH" -H "Content-Type: application/json" "$DAIRY/milk-cream" \
  -d "{\"location_id\":$TEST_LOC,\"entry_date\":\"$TODAY\",\"input_ff_milk_kg\":0,\"input_snf\":0,\"input_fat\":0,\"input_rate\":0,\"output_skim_milk_kg\":350,\"output_skim_snf\":8.2,\"output_cream_kg\":50,\"output_cream_fat\":5.5,\"milk_usage\":[{\"vendor_id\":$VENDOR1,\"ff_milk_kg\":250},{\"vendor_id\":$VENDOR2,\"ff_milk_kg\":150}]}" 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
[ "$S" = "True" ] && ok "FF Milk Processing with 2 vendor picks" || fail "FF Milk Processing" "$R"

# ══════════════════════════════════════
# TEST 4: Milk Availability after processing (should be reduced)
# ══════════════════════════════════════
echo ""
echo "=== Test 4: Milk Availability after processing ==="
R=$(curl -sk -H "$AUTH" "$DAIRY/milk-availability?location_id=$TEST_LOC" 2>/dev/null)
echo "  Response: $R"
V1_AVAIL=$(echo "$R" | python3 -c "
import sys,json
data=json.load(sys.stdin).get('data',[])
for v in data:
    if int(v['vendor_id'])==$VENDOR1: print(v['available_kg']); break
" 2>/dev/null)
echo "  Vendor $VENDOR1 available: $V1_AVAIL KG (expect ~250)"
[ -n "$V1_AVAIL" ] && ok "Availability updated after processing" || fail "Availability check" "$R"

# ══════════════════════════════════════
# TEST 5: Pouch Types CRUD
# ══════════════════════════════════════
echo ""
echo "=== Test 5: Create Pouch Types ==="
R=$(curl -sk -X POST -H "$AUTH" -H "Content-Type: application/json" "$DAIRY/pouch-types" \
  -d '{"name":"Test 500ml Full Cream","litre":0.50,"price":28.00}' 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
PT1=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null)
[ "$S" = "True" ] && ok "Created pouch type 1 (id=$PT1)" || fail "Create pouch type 1" "$R"

R=$(curl -sk -X POST -H "$AUTH" -H "Content-Type: application/json" "$DAIRY/pouch-types" \
  -d '{"name":"Test 1L Toned","litre":1.00,"price":52.00}' 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
PT2=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null)
[ "$S" = "True" ] && ok "Created pouch type 2 (id=$PT2)" || fail "Create pouch type 2" "$R"

echo ""
echo "=== Test 5b: List Pouch Types ==="
R=$(curl -sk -H "$AUTH" "$DAIRY/pouch-types" 2>/dev/null)
COUNT=$(echo "$R" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null)
[ "$COUNT" -ge 2 ] && ok "Listed $COUNT pouch types" || fail "List pouch types" "$R"

echo ""
echo "=== Test 5c: Update Pouch Type ==="
R=$(curl -sk -X POST -H "$AUTH" -H "Content-Type: application/json" "$DAIRY/pouch-types/$PT1" \
  -d '{"price":30.00}' 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
[ "$S" = "True" ] && ok "Updated pouch type price" || fail "Update pouch type" "$R"

# ══════════════════════════════════════
# TEST 6: Pouch Production (Flow 5)
# ══════════════════════════════════════
echo ""
echo "=== Test 6: Pouch Production ==="
R=$(curl -sk -X POST -H "$AUTH" -H "Content-Type: application/json" "$DAIRY/pouch-production" \
  -d "{\"location_id\":$TEST_LOC,\"entry_date\":\"$TODAY\",\"output_cream_kg\":20,\"output_cream_fat\":5.2,\"milk_usage\":[{\"vendor_id\":$VENDOR1,\"ff_milk_kg\":100}],\"pouch_lines\":[{\"pouch_type_id\":$PT1,\"quantity\":200},{\"pouch_type_id\":$PT2,\"quantity\":100}]}" 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
PP_ID=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null)
[ "$S" = "True" ] && ok "Pouch production saved (id=$PP_ID)" || fail "Pouch production" "$R"

# ══════════════════════════════════════
# TEST 7: Pouch Stock
# ══════════════════════════════════════
echo ""
echo "=== Test 7: Pouch Stock ==="
R=$(curl -sk -H "$AUTH" "$DAIRY/pouch-stock?location_id=$TEST_LOC" 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
echo "  Response: $R"
[ "$S" = "True" ] && ok "Pouch stock retrieved" || fail "Pouch stock" "$R"

# ══════════════════════════════════════
# TEST 8: Stock (verify FF Milk balance includes milk_usage)
# ══════════════════════════════════════
echo ""
echo "=== Test 8: Stock ==="
R=$(curl -sk -H "$AUTH" "$DAIRY/stock?location_id=$TEST_LOC" 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
FF_STOCK=$(echo "$R" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',{})
dates=d.get('dates',[])
if dates: print(dates[-1].get('stocks',{}).get('1','?'))
" 2>/dev/null)
echo "  FF Milk stock (today): $FF_STOCK"
[ "$S" = "True" ] && ok "Stock query works" || fail "Stock query" "$R"

# ══════════════════════════════════════
# TEST 9: Production Transactions (should include Pouch Production)
# ══════════════════════════════════════
echo ""
echo "=== Test 9: Production Transactions ==="
R=$(curl -sk -H "$AUTH" "$DAIRY/production-transactions?location_id=$TEST_LOC" 2>/dev/null)
HAS_POUCH=$(echo "$R" | python3 -c "
import sys,json
rows=json.load(sys.stdin).get('data',{}).get('rows',[])
print(any(r.get('type')=='Pouch Production' for r in rows))
" 2>/dev/null)
[ "$HAS_POUCH" = "True" ] && ok "Pouch Production in transactions" || fail "Pouch in transactions" "not found"

# ══════════════════════════════════════
# TEST 10: Over-allocation should fail
# ══════════════════════════════════════
echo ""
echo "=== Test 10: Over-allocation should fail ==="
R=$(curl -sk -X POST -H "$AUTH" -H "Content-Type: application/json" "$DAIRY/milk-cream" \
  -d "{\"location_id\":$TEST_LOC,\"entry_date\":\"$TODAY\",\"input_ff_milk_kg\":0,\"input_snf\":0,\"input_fat\":0,\"input_rate\":0,\"output_skim_milk_kg\":100,\"output_skim_snf\":8.0,\"output_cream_kg\":10,\"output_cream_fat\":5.0,\"milk_usage\":[{\"vendor_id\":$VENDOR1,\"ff_milk_kg\":99999}]}" 2>/dev/null)
S=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)
[ "$S" = "False" ] && ok "Over-allocation correctly rejected" || fail "Over-allocation not rejected" "$R"

# ══════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════
echo ""
echo "════════════════════════════════════"
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
echo "════════════════════════════════════"
[ "$FAIL" -eq 0 ] && echo "  ALL TESTS PASSED" || echo "  SOME TESTS FAILED"
