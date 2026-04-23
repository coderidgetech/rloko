# Deploy on a DigitalOcean Droplet

Stack: **MongoDB** (container) + **api** (Go) + **web** (Nginx + Vite build) + **Caddy** (TLS + reverse proxy). Same path routing as App Platform: `/api`, `/health`, `/ready` → API; everything else → SPA.

## 1. Create a Droplet

- Ubuntu 22.04+, **1–2 GB RAM** minimum (add RAM if you self-host Mongo and expect traffic).  
- Open **SSH**; add **ports 80 and 443** in the **firewall** (Droplet or cloud firewall).

## 2. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
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

- **`VITE_API_URL`**: e.g. `https://rloko.com/api` (your real domain, HTTPS). Rebuild `web` after any change: `docker compose up -d --build web`  
- **`MONGODB_URI`**: for the bundled Mongo, keep it aligned with `MONGO_ROOT_PASSWORD` in `.env.example` pattern.  
- **Managed MongoDB (Atlas / DO):** remove the `mongo` service from `docker-compose.yml`, remove `depends_on: mongo` from `api`, set `MONGODB_URI` to the provider’s URI.

## 5. Start

```bash
docker compose up -d --build
```

Check: `curl -sS http://127.0.0.1/health` and open `http://<droplet-ip>/` in a browser.

## 6. DNS and HTTPS

- Point **A** (and **AAAA** if IPv6) for `rloko.com` / `www` to the Droplet’s public IP.  
- For **Let’s Encrypt**, change `Caddyfile` first line from `:80` to your domain, e.g. `rloko.com, www.rloko.com {` — Caddy will request certificates on port 443. Reload: `docker compose restart caddy`.

## 7. Firewalls (UFW example)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## 8. Updates

```bash
cd ~/rloko && git pull
cd deploy/droplet && docker compose up -d --build
```
