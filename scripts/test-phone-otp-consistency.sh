#!/usr/bin/env bash
# Phone OTP normalization smoke test (same logical number → same server-side key).
#
# Run (make executable once if needed):
#   chmod +x scripts/test-phone-otp-consistency.sh
#   ./scripts/test-phone-otp-consistency.sh
#
# Or:  bash scripts/test-phone-otp-consistency.sh
#
# Requires: API up, e.g. BASE_URL=http://localhost:8080
#
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:8080}"
API="$BASE_URL/api"

echo "=========================================="
echo "Phone OTP consistency (normalized key)"
echo "BASE_URL=$BASE_URL"
echo "=========================================="
echo ""

echo "=== 1) register-otp/send 9866873530 ==="
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$API/auth/register-otp/send" \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9866873530"}'
echo ""

echo "=== 2) register-otp/send 09866873530 (leading 0) ==="
echo "    If step 1 just succeeded: EXPECT HTTP 400 + \"please wait before requesting another code\"."
echo "    That means 09866873530 normalizes to the SAME key as 9866873530 (good)."
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$API/auth/register-otp/send" \
  -H 'Content-Type: application/json' \
  -d '{"phone":"09866873530"}'
echo ""

echo "=== 3) login-otp/send 9866873530 ==="
echo "    EXPECT \"no account found\" until register-otp/COMPLETE succeeds (SMS code)."
echo "    Sending OTP alone does not create a user — only /complete does."
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$API/auth/login-otp/send" \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9866873530"}'
echo ""

echo "=========================================="
echo "How to read this"
echo "  • Step 2 rate-limit  = same identity as step 1 (normalization OK)."
echo "  • Step 3 no account  = normal if you never finished signup with that number."
echo "  • After full signup: step 3 should return 200 (login OTP sent)."
echo "=========================================="
