# Rloko — Release Readiness Audit (2026-06-14)

Synthesis of a read-only end-to-end audit across backend (Go), web (React), mobile (Flutter), and infra.

**Verdict:** The purchase funnel is genuinely implemented end-to-end on all three clients (real Stripe, real Shippo/Shiprocket, server-side repricing — no stubs/fake tracking). It is **not release-ready**. The **US + card** path is the only one close to shippable. India is server-gated off (`coming_soon`), and there are blocker-class money/inventory/config gaps. Severity = impact on real money, inventory, or completing/fulfilling an order.

Owner key: **[CFG]** = config/dashboard/ops · **[CODE]** = code change required.

---

## ✅ Status update (2026-06-15) — code blockers fixed (uncommitted, local only)

All **[CODE]** blockers/bugs I can own are done, reviewed, and (most) live-verified:
- **#2 Fulfillment requires payment** (COD exempt) — live-verified.
- **#4 Guest checkout idempotency** (per-guest email namespace) — live-verified.
- **#11 Atomic/idempotent re-fulfill** (no double-buy) — live-verified.
- **#3 Abandoned-order sweeper** (release stock on unpaid timeout; late-payment refund guard) — live-verified.
- **#13 IN→Shiprocket routing** (`CountryLooksIndia` instead of `== "IN"`).
- **#10 Shippo webhook auth** — now supports a `?token=SECRET` URL query (which Shippo can actually send), so `SHIPPO_WEBHOOK_SECRET` can finally be enabled; Shiprocket already had header-token auth.
- **COD normalization** at the write point + robust `isCODPaymentMethod` everywhere.

**Deferred (flagged):** #12 India INR mixed-currency total (India is gated off; invasive — do before India launch); **H1** sweeper graceful-shutdown drain (conservative failure mode — under-restores stock, never oversells).

**Everything below that is still [CFG] is the remaining work and is yours** (I have no dashboard/server access). To enable `SHIPPO_WEBHOOK_SECRET`: set it in `.env` AND change the Shippo dashboard URL to `…/api/webhooks/shippo?token=THESECRET`.

---

## BLOCKERS (will lose money, corrupt inventory, or prevent real orders)

1. **[CFG] Card orders never become `paid` without the Stripe webhook.** Requires `STRIPE_WEBHOOK_SECRET` set + the `/api/webhooks/stripe` endpoint registered in Stripe. No reconciliation/poller exists — if the webhook never arrives, the customer is charged but the order stays `pending` forever. (backend `payment_service.go:273`)
2. **[CODE] Fulfillment ships UNPAID orders.** `FulfillOrder` only blocks shipped/delivered/cancelled/returned — an admin can buy a real label for a `pending`/unpaid card order. Must gate on `PaymentStatus == "paid"` (non-COD). (`order_service.go:554`)
3. **[CODE] Stock is decremented at order CREATE, before payment, with no release for abandoned/unpaid orders.** No TTL/sweeper. Every abandoned card checkout permanently consumes stock → silent oversell-via-attrition / phantom out-of-stock. (`order_service.go:280`)
4. **[CODE] Guest checkout has no idempotency.** Double-submit creates two COD orders + double-decrements stock. (`order_handler.go:415`)
5. **[CFG] Stripe Tax (US) misconfig.** The `line_items[0][tax_code]` 400 blocks US checkout until a tax code is set (dashboard default or `STRIPE_TAX_PRODUCT_CODE=txcd_30011000`). Worse: on tax-calc failure the code **silently charges a made-up flat 8%** instead of failing. (`stripe_us_tax.go`, `order_service.go:226`)
6. **[CFG] Uploads broken in prod.** `STORAGE_TYPE` defaults to `local`: files land on the ephemeral container layer, there's **no `/uploads` route** to serve them, and no volume mounted. Product images 404 in prod. Must set `STORAGE_TYPE=s3` + R2/S3 creds. (`config.go:141`, `storage_service.go`)
7. **[CFG] No prod web image / ambiguous prod target.** The only web-image CI workflow hardcodes `VITE_API_URL=https://dev.rloko.com`; there's no prod web build. Both App Platform (`app.yaml`) and the droplet claim `rloko.com`, while `rloko.com` is currently a parked GoDaddy page and `dev.rloko.com` is the live droplet. Decide ONE prod target and build its web image. (`publish-droplet-images.yml:24`, `app.yaml`)
8. **[CFG] Mobile prod secrets are placeholders.** `mobile-app/assets/env/app.prod.env` ships `pk_live_YOUR_KEY_HERE` and `API_BASE_URL=https://rloko.com/api`. With the placeholder key, mobile silently falls back to COD-only. CI must inject the real `pk_live_…` + prod API URL.
9. **[CFG/SECURITY] Committed JWT secret.** `app.yaml:23` has a real-looking `JWT_SECRET` in git (and baked into the image). Rotate it and remove from source.

---

## HIGH

10. **[CODE] Shippo/Shiprocket webhooks accept UNSIGNED requests** when their secrets are empty (anyone can forge tracking → flip orders to delivered + send emails). BUT setting `SHIPPO_WEBHOOK_SECRET` currently 401s real Shippo webhooks because the handler's HMAC `Shippo-Webhook-Signature` scheme doesn't match what Shippo sends. **Needs a code fix** to verify Shippo's actual signature, then enable. (`shipping_webhook_handler.go:77,135`)
11. **[CODE] Label purchase is not atomic with the DB write.** A failure after buying the label orphans it; re-fulfill double-buys (Shippo) / duplicates (Shiprocket). Make re-fulfill idempotent. (`order_service.go:559`)
12. **[CODE] India INR total is mixed-currency.** Order total built from INR prices but parts normalized as USD; email formats `$`, reward points credit `int64(total)`. Charged vs displayed vs points can disagree. Validate a real INR order before enabling India. (backend; web forwards it)
13. **[CODE] IN routing may misfire.** Orders store country `"India"` but `shipping_service.go:57` compares `== "IN"` → could misroute IN orders to Shippo (un-fulfillable). Verify.
14. **[CFG] Shipping silently falls back to flat $15** if `SHIPPO_API_KEY`/`SHIPPO_FROM_*` unset — customers charged wrong shipping; international fulfillment un-buyable. (`shipping_service.go:88`)
15. **[CFG] Email silently disabled** without `RESEND_API_KEY` + `SMTP_FROM` (+ verified domain). Order confirmations, password reset, email verification just never send.
16. **[CFG] Dangerous defaults:** `MONGODB_URI` defaults to localhost; `ENV` unset = dev mode (no rate limiting, debug). Must explicitly set `ENV=production` + real Mongo URI everywhere.
17. **[CFG] No Mongo backups** — especially the droplet container DB (no mongodump/snapshot). Establish + test restore.
18. **[CODE/CFG] iOS prod build readiness:** prod scheme's Run uses Debug config; confirm CI injects `APP_FLAVOR`/`API_BASE_URL` and Release for archive. (`ios/.../prod.xcscheme`)
19. **[CODE] Refunds are Stripe-only** — COD/other refunds error. (`payment_service.go:381`)

---

## MEDIUM / LOW

- [CODE] Payment-failed webhook doesn't release reserved stock; order stays `pending` (no `failed` status).
- [CODE] COD spelling mismatch: `"cod"` vs `"cash_on_delivery"` checked inconsistently.
- [CODE] Returns don't require delivery; multiple partial returns can over-refund; no guest-order returns.
- [CODE] Shiprocket ignores real order weight (fixed 0.5 kg).
- [CFG] No runtime error monitoring/alerting (no Sentry/Prometheus); only deploy/domain alerts.
- [CODE] Web + mobile each carry a **dead duplicate checkout** implementation (`PaymentPage.tsx`/`AddressSelectionPage.tsx`; mobile `CheckoutBloc`) — delete to avoid auditing the wrong code.
- [CODE] No client-side stock/availability check in either live checkout; OOS only fails at order POST with a generic error.
- [CODE] Mobile `getById` omits `?market=` (deep-link visibility inconsistency).
- [CFG] Coupon "invalid" shows a generic error (backend signals invalid via 400, not `valid:false`).
- [CODE] Hardcoded 75 INR/USD display rate vs backend `ORDER_INR_PER_USD`.
- [CFG] Real test keys committed in `frontend/.env`; `rloco` vs `rloko` in sender email / `APP_BASE_URL` defaults.
- [CFG] Web has no guest checkout (auth-required); mobile does (COD).

---

## Minimum to prove ONE real US order end-to-end

**Config (do first):**
1. Live `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET`; register `/api/webhooks/stripe` on the live host (dev.rloko.com today).
2. Stripe Tax: set default tax code (`txcd_30011000`) or `STRIPE_TAX_PRODUCT_CODE`; enable US Tax.
3. `SHIPPO_API_KEY` + all `SHIPPO_FROM_*` (test mode is fine for the dry run).
4. `STORAGE_TYPE=s3` + creds (so product images resolve).
5. `RESEND_API_KEY` + verified `SMTP_FROM` (to see confirmation/shipping emails).
6. `ENV=production`, real `MONGODB_URI`, `CORS_ALLOWED_ORIGINS`, rotated `JWT_SECRET`.

**Code fixes before real money (recommended):**
7. Gate `FulfillOrder` on paid (#2).
8. Release stock on abandoned/unpaid orders + guest idempotency (#3, #4).
9. Make re-fulfill idempotent (#11).

**Then:** place a US test order on web → pay (Stripe test card) → confirm `paid` via webhook → admin fulfill → Shippo label → tracking webhook → delivered → emails. That's the real proof.

India remains dark until #12/#13 are fixed and the IN region is enabled.
