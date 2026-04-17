# Rloko production runbook

## Deploy checklist

1. Set environment variables (see `backend/.env.example` and `frontend/.env.example` templates locally; never commit real secrets).
2. **Production required:** `ENV=production`, `JWT_SECRET` (non-default), `MONGODB_URI`, `CORS_ALLOWED_ORIGINS` (comma-separated), Twilio Verify, Stripe keys + webhook secret, `APP_BASE_URL`.
3. Run database migrations / index creation as documented for your environment.
4. Smoke test: `GET /health`, `GET /ready`, storefront login, signup OTP, checkout (Stripe test mode), admin login.

## Rollback

1. Re-deploy previous container/image or revert release tag.
2. If schema changed, restore DB snapshot taken before deploy (if applicable).

## Stripe webhooks

- Endpoint: `POST /api/webhooks/stripe`
- Rotate `STRIPE_WEBHOOK_SECRET` in Stripe Dashboard and in env together.
- After rotation, replay failed events from Dashboard if needed.

## Secrets rotation

- Rotate `JWT_SECRET` only during a maintenance window (invalidates all sessions).
- Rotate DB credentials and update `MONGODB_URI`.
- Run `gitleaks` / GitHub secret scanning on the repo after any accidental commit of keys.

## On-call triage

- **502/503 from API:** check `/ready` (Mongo connectivity), app logs, upstream TLS.
- **Payments stuck pending:** verify Stripe webhook delivery and `STRIPE_WEBHOOK_SECRET`; confirm order `payment_status` in DB.
- **CORS errors in browser:** verify `CORS_ALLOWED_ORIGINS` includes exact scheme+host of the web app.

## Support contact form

- Requires SMTP configured and `ADMIN_EMAIL` (or falls back to `SMTP_FROM`) for `/api/contact` delivery.
