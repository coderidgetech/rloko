#!/usr/bin/env bash
# End-to-end user creation checks (curl). Run from repo root.
#
#   bash scripts/test-user-creation-e2e.sh
#
# Env:
#   BASE_URL=http://localhost:8080   (default)
#   VERIFIED_PHONE=919866873530      optional: digits only; if set, tests phone OTP *send*
#       (must be a number Twilio can message — trial: add in Verified Caller IDs)
#
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:8080}"
API="$BASE_URL/api"
BASE=$(( $(date +%s) % 900000000 + 100000000 ))
EMAIL="e2e_user_${BASE}@example.com"
NAME="E2E User ${BASE}"

die() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

command -v curl >/dev/null || die "curl required"

echo "=========================================="
echo "User creation E2E"
echo "BASE_URL=$BASE_URL"
echo "=========================================="

c=$(curl -sS -o /dev/null -w "%{http_code}" "$BASE_URL/health") || true
[[ "$c" == "200" ]] || die "GET /health expected 200, got $c"

echo ""
echo "--- 1) Email + password register (no Twilio) ---"
REG=$(curl -sS -w "\n%{http_code}" -X POST "$API/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"testpass12\",\"name\":\"${NAME}\"}")
CODE=$(echo "$REG" | tail -n1)
BODY=$(echo "$REG" | sed '$d')
[[ "$CODE" == "201" ]] || die "POST /auth/register expected 201, got $CODE body=$BODY"
echo "$BODY" | grep -q '"token"' || die "register response missing token"
ok "register 201 + token"

echo ""
echo "--- 2) Email login ---"
LOG=$(curl -sS -w "\n%{http_code}" -X POST "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"testpass12\"}")
CODE=$(echo "$LOG" | tail -n1)
BODY=$(echo "$LOG" | sed '$d')
[[ "$CODE" == "200" ]] || die "POST /auth/login expected 200, got $CODE body=$BODY"
ok "login 200"

echo ""
echo "--- 3) Phone OTP send (optional) ---"
if [[ -n "${VERIFIED_PHONE:-}" ]]; then
  SEND=$(curl -sS -w "\n%{http_code}" -X POST "$API/auth/register-otp/send" \
    -H 'Content-Type: application/json' \
    -d "{\"phone\":\"${VERIFIED_PHONE}\"}")
  CODE=$(echo "$SEND" | tail -n1)
  BODY=$(echo "$SEND" | sed '$d')
  if [[ "$CODE" == "200" ]]; then
    ok "register-otp/send 200 (check SMS on $VERIFIED_PHONE)"
    echo "    Next: POST /auth/register-otp/complete with real code from SMS"
  else
    echo "register-otp/send got HTTP $CODE — body: $BODY"
    echo "    Common: Twilio trial 21608 → verify this number in Twilio Console or use a paid account."
  fi
else
  echo "SKIP: set VERIFIED_PHONE=9198xxxxxxx (digits) to test SMS send against your Twilio account."
  RAND="8${BASE}"
  SEND=$(curl -sS -w "\n%{http_code}" -X POST "$API/auth/register-otp/send" \
    -H 'Content-Type: application/json' \
    -d "{\"phone\":\"${RAND}\"}")
  CODE=$(echo "$SEND" | tail -n1)
  BODY=$(echo "$SEND" | sed '$d')
  if [[ "$CODE" == "200" ]]; then
    ok "random phone send 200 (Twilio accepted)"
  else
    echo "random phone send HTTP $CODE (expected on trial): $BODY"
  fi
fi

echo ""
echo "--- 4) Validation: bad payloads ---"
c=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$API/auth/register-otp/send" \
  -H 'Content-Type: application/json' -d '{}')
[[ "$c" == "400" ]] || die "register-otp/send {} expected 400, got $c"
ok "register-otp/send missing phone → 400"

echo ""
echo "=========================================="
echo "Summary: email signup path works if steps 1–2 passed."
echo "Phone signup needs Twilio + (trial) verified recipient number."
echo "=========================================="
