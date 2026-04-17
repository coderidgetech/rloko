#!/usr/bin/env bash
# Smoke-test phone OTP auth against a running API (curl-only, macOS/Linux).
#
# Twilio Verify must be configured on the server. There is no fixed dev OTP.
# This script only checks HTTP behavior (send OK, wrong code rejected, validation errors).
# Full signup/login with a real SMS code: test in the app or use curl manually after each send.
#
# Usage:
#   ./scripts/test-auth-otp-api.sh
#   BASE_URL=https://api.example.com ./scripts/test-auth-otp-api.sh
#
# Optional TEST_PHONE=919876543210 — use a number that can receive SMS if you rely on Twilio
# delivery for the initial send (smoke still only asserts status codes, not inbox).
#
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
API="$BASE_URL/api"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required"

BASE=$(( $(date +%s) % 900000000 + 100000000 ))
PHONE="${TEST_PHONE:-8${BASE}}"
EMAIL="apitest_${BASE}@example.com"

BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT

post_json() {
  local path="$1"
  local data="$2"
  curl -sS -o "$BODY" -w "%{http_code}" -X POST "${API}${path}" \
    -H 'Content-Type: application/json' \
    -d "$data"
}

echo "=========================================="
echo "Auth OTP API smoke test"
echo "BASE_URL=$BASE_URL"
echo "PHONE=$PHONE"
echo "=========================================="

c=$(curl -sS -o /dev/null -w "%{http_code}" "$BASE_URL/health") || true
[[ "$c" == "200" ]] || die "GET /health expected 200, got $c (is the backend up?)"

c=$(post_json "/auth/register-otp/send" "{\"phone\":\"${PHONE}\"}")
[[ "$c" == "200" ]] || die "register-otp/send expected 200, got $c body=$(cat "$BODY")"

c=$(post_json "/auth/register-otp/complete" "{\"phone\":\"${PHONE}\",\"code\":\"000000\",\"email\":\"${EMAIL}\",\"password\":\"testpass12\",\"name\":\"API Test\"}")
[[ "$c" == "400" ]] || die "register-otp/complete with wrong code expected 400, got $c body=$(cat "$BODY")"

c=$(post_json "/auth/login-otp/send" '{"phone":"8000000000"}')
[[ "$c" == "400" ]] || die "login-otp/send unknown phone expected 400, got $c"

c=$(post_json "/auth/login-otp/send" '{}')
[[ "$c" == "400" ]] || die "login-otp missing phone expected 400, got $c"

echo "=========================================="
echo "All smoke checks passed."
echo "=========================================="
