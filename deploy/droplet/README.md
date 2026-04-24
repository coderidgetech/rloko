# Deploy on a DigitalOcean Droplet

Stack: **MongoDB** (container) + **api** (Go) + **web** (Nginx + Vite build) + **Caddy** (TLS + reverse proxy). Same path routing as App Platform: `/api`, `/health`, `/ready` → API; everything else → SPA.

## 1. Create a Droplet

- Ubuntu 22.04+, **2 GB RAM** minimum for **on-server** `docker compose --build` (1 GB is very slow; use pre-built images in § "Fast deploy" or a larger Droplet).  
- Open **SSH**; add **ports 80 and 443** in the **firewall** (Droplet or cloud firewall).

## 2. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
export DOCKER_BUILDKIT=1
```

Re-login, then: `docker compose version`

## 3. Get the code

On the Droplet, clone the monorepo (with submodules, since `backend` / `frontend` are repos):

```bash
git clone --recurse-submodules https://github.com/coderidgetech/rloko.git
cd rloko/deploy/droplet
```

## 4. Environment

```bash
cp .env.example .env
nano .env   # set MONGO_ROOT_PASSWORD, JWT_SECRET (openssl rand -hex 64), VITE_*, Twilio, APP_BASE_URL, CORS, MONGODB_URI (match mongo password)
```

- **`VITE_API_URL`**: e.g. `https://dev.rloko.com/api` (must match Caddy host + workflow `VITE_API_URL` for GHCR images). Rebuild/republish `web` after a URL change.  
- **Same credentials on dev as production:** set **`ENV=production`** in `.env` (default in `.env.example`) and use the same **`TWILIO_*`**, **`JWT_SECRET`**, and **Mongo** string as you would in prod; only **public URLs** need to be `https://dev.rloko.com` (`APP_BASE_URL`, `CORS_ALLOWED_ORIGINS`, `VITE_API_URL`).  
- **`MONGODB_URI`**: for the bundled Mongo, keep it aligned with `MONGO_ROOT_PASSWORD` in `.env.example` pattern.  
- **Managed MongoDB (Atlas / DO):** remove the `mongo` service from `docker-compose.yml`, remove `depends_on: mongo` from `api`, set `MONGODB_URI` to the provider’s URI.

## 5. Start (build on the Droplet — can be 30–90+ min on 1 vCPU)

```bash
DOCKER_BUILDKIT=1 docker compose up -d --build
```

**Faster (recommended):** do **not** compile on the Droplet — use **pre-built images** (§ below).

Check: `curl -sS http://127.0.0.1/health` and open `http://<droplet-ip>/` in a browser.

## Fast deploy (GitHub pre-builds, pull only on Droplet)

1. In the **rloko** repo, run the GitHub Action **“Publish Droplet images (GHCR)”** (or push to `main` if it’s enabled for `backend/` and `frontend/` changes).  
2. Wait for images: `ghcr.io/<your-github-user-lower>/rloco-api` and `.../rloco-web` (see the workflow for exact tags: `latest` and commit SHA).  
3. On the Droplet, **log in to ghcr** (classic PAT with **read:packages**; for an **org** with **SSO**, open the org → *Settings* → *Personal access tokens* and **authorize** the token):

   ```bash
   echo YOUR_GH_PAT | docker login ghcr.io -u YOUR_GH_USERNAME --password-stdin
   ```

   If you see `denied: denied` on **login** (not pull): the PAT is wrong, expired, missing `read:packages`, or the username is not the **GitHub user** that owns the PAT. Fix the token, then re-login. You can also log in **once** interactively and run `./deploy.sh --skip-login` with `GHCR_PAT` **unset** so the script does not re-run login.

4. In **`.env`**, set (replace with your real GitHub user, lowercase):

   ```env
   API_IMAGE=ghcr.io/yourgithubuser/rloco-api:latest
   WEB_IMAGE=ghcr.io/yourgithubuser/rloco-web:latest
   ```

5. Start **without** building on the server (or use the script in step 5b).

   ```bash
   docker compose -f docker-compose.ghcr.yml up -d
   ```

   **5b. One-command script (recommended):** from `deploy/droplet`, after `.env` is configured and GitHub has published images:

   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

   - Pulls the monorepo and submodules, `docker compose pull` + `up -d` (GHCR), prints `docker compose ps` and a local `/health` check.  
   - Optional: `export GHCR_PAT=...` and `export GHCR_USER=yourgithubuser` (or `GITHUB_USER`) so the script can `docker login ghcr.io` before pull.  
   - Flags: `./deploy.sh --skip-git` (no `git pull`), `./deploy.sh --no-pull` (recreate only), `./deploy.sh --help`.  
   - On-server compile (slow): `./deploy.sh build`  
   - **502 on `/api/*`:** run `chmod +x diagnose.sh && ./diagnose.sh` and read the **api** logs (usually Mongo URI/password, or `CORS` / `JWT` in production). After **server-side** code changes, re-run **Publish Droplet images (GHCR)** and `./deploy.sh` to pull a new `api` image.

This only **pulls** images (minutes) instead of compiling Go + Vite on a small VM (hours).

## 6. DNS and HTTPS

- **Subdomain in GoDaddy (e.g. `dev.rloko.com`):** add an **A** record: **Name** = `dev`, **Value** = Droplet public IP (not `@` — that’s the apex; `dev` is the subdomain). TTL default is fine.  
- **Let’s Encrypt:** the committed `Caddyfile` uses `dev.rloko.com` — Caddy requests certs on 443 once DNS points here. Reload after edits: `docker compose -f docker-compose.ghcr.yml restart caddy` (or full path from `deploy/droplet`).  
- For a quick test **before** DNS, you can set Caddy to `:80 {` and use the Droplet IP in a browser; switch back to `dev.rloko.com` for HTTPS.

## 7. Firewalls (UFW example)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## 8. Updates

**Build on Droplet:**

```bash
cd ~/rloko && git pull
cd deploy/droplet && DOCKER_BUILDKIT=1 docker compose up -d --build
```

**Pre-built images:** run the GitHub Action again, then on the Droplet: `cd deploy/droplet && ./deploy.sh` (or `docker compose -f docker-compose.ghcr.yml pull && docker compose -f docker-compose.ghcr.yml up -d`)
