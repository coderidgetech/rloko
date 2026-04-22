#!/usr/bin/env bash
# Deploy to DigitalOcean App Platform using app.yaml at the repository root.
# Prereq: doctl auth init   (or export DIGITALOCEAN_ACCESS_TOKEN)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${ROOT}/app.yaml"
cd "$ROOT"

if ! command -v doctl >/dev/null; then
  echo "Install doctl: https://docs.digitalocean.com/reference/doctl/how-to/install/"
  exit 1
fi
if ! doctl account get >/dev/null 2>&1; then
  echo "Authenticate first:"
  echo "  doctl auth init"
  echo "or:  export DIGITALOCEAN_ACCESS_TOKEN=your_token"
  exit 1
fi

if [[ -n "${DO_APP_ID:-}" ]]; then
  echo "Updating app ${DO_APP_ID} from ${SPEC}"
  doctl apps update "$DO_APP_ID" --spec "$SPEC"
else
  echo "Creating app from ${SPEC}"
  doctl apps create --spec "$SPEC"
fi
