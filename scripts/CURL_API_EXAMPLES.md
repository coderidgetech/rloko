# curl examples — Rloco API

Default base: `http://localhost:8080` (Docker backend). JSON API lives under **`/api`**.

```bash
export BASE=http://localhost:8080
export API=$BASE/api
```

## Health

```bash
curl -sS "$BASE/health"
```

## Public catalog

```bash
curl -sS "$API/products?limit=5"
curl -sS "$API/products/featured"
curl -sS "$API/categories"
curl -sS "$API/config"
```

## Email auth

```bash
curl -sS -X POST "$API/auth/register" \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"secret12","name":"Test User"}'

curl -sS -X POST "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"secret12"}'
```

Login/register set an **`auth_token`** cookie if you use `-c` / `-b`:

```bash
curl -sS -c cookies.txt -X POST "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"secret12"}'

curl -sS -b cookies.txt "$API/auth/me"
```

Or **Bearer** token (if the response JSON includes `token`):

```bash
TOKEN="paste_jwt_here"
curl -sS "$API/auth/me" -H "Authorization: Bearer $TOKEN"
```

## Phone OTP (Twilio Verify)

Send triggers a **real SMS** (no fixed dev code).

```bash
# 1) Send signup OTP (digits; server may normalize e.g. 10-digit India → +91)
curl -sS -X POST "$API/auth/register-otp/send" \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9876543210"}'

# 2) Complete signup — use the 6-digit code from SMS
curl -sS -X POST "$API/auth/register-otp/complete" \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9876543210","code":"123456","email":"new@example.com","password":"secret12","name":"New User"}'
```

```bash
# Login OTP (user must already exist with that phone)
curl -sS -X POST "$API/auth/login-otp/send" \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9876543210"}'

curl -sS -X POST "$API/auth/login-otp/complete" \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9876543210","code":"123456"}'
```

## Automated smoke (no SMS code needed)

Runs health + OTP send + wrong-code + validation checks:

```bash
./scripts/test-auth-otp-api.sh
BASE_URL=https://your-host ./scripts/test-auth-otp-api.sh
```

## Pretty-print JSON (optional)

```bash
curl -sS "$API/categories" | python3 -m json.tool
# or: brew install jq  →  curl -sS ... | jq .
```
