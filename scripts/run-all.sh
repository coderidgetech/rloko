#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${REPO_DIR}/backend"
FRONTEND_DIR="${REPO_DIR}/frontend"
BACKEND_DOCKER_DIR="${BACKEND_DIR}/docker"
DOCKER_RUN_SCRIPT="${REPO_DIR}/docker-run.sh"

START_DEPS=false
FORCE=false
PACKAGE_MANAGER=""
COMPOSE_CMD=""
PIDS=()

print_info() {
  printf '[info] %s\n' "$1"
}

print_error() {
  printf '[error] %s\n' "$1" >&2
}

print_warning() {
  printf '[warn] %s\n' "$1"
}

usage() {
  cat <<'EOF'
Usage: bash run-all.sh [--with-deps] [--force]

Options:
  --with-deps   Start MongoDB and MinIO with Docker before starting the apps
  --force       Kill whatever is using required ports (8080, 5173) and stop any Docker backend bound to 8080

What it starts:
  - Backend:  http://localhost:8080
  - Frontend: http://localhost:5173
EOF
}

cleanup() {
  print_info "Stopping app processes..."
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}

is_port_in_use() {
  local port="$1"
  lsof -tiTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local name="$3"
  local retries="${4:-60}"
  local delay_s="${5:-1}"

  for _ in $(seq 1 "${retries}"); do
    if (echo >/dev/tcp/"${host}"/"${port}") >/dev/null 2>&1; then
      return 0
    fi
    sleep "${delay_s}"
  done

  print_error "Timed out waiting for ${name} at ${host}:${port}"
  return 1
}

kill_port_listeners() {
  local port="$1"
  local pids=""
  pids="$(lsof -tiTCP:"${port}" -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' || true)"
  if [ -z "${pids}" ]; then
    return
  fi
  print_warning "Port ${port} is in use; killing listener PID(s): ${pids}"
  # "At any cost": hard kill listeners so Docker/app can bind.
  kill -9 ${pids} 2>/dev/null || true
}

stop_docker_backend_if_running() {
  if [ -z "${COMPOSE_CMD}" ]; then
    return
  fi

  if docker ps --format '{{.Names}}' | rg -x "rloco-backend" >/dev/null 2>&1; then
    print_warning "Stopping Docker backend container on port 8080..."
    (
      cd "${BACKEND_DOCKER_DIR}"
      ${COMPOSE_CMD} stop backend >/dev/null
    )
  fi
}

trap cleanup EXIT INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-deps)
      START_DEPS=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if ! command -v go >/dev/null 2>&1; then
  print_error "Go is not installed."
  exit 1
fi

if command -v pnpm >/dev/null 2>&1 && [ -f "${FRONTEND_DIR}/pnpm-lock.yaml" ]; then
  PACKAGE_MANAGER="pnpm"
elif command -v npm >/dev/null 2>&1; then
  PACKAGE_MANAGER="npm"
else
  print_error "Neither pnpm nor npm is installed."
  exit 1
fi

if [ "$START_DEPS" = true ]; then
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  else
    print_error "Docker Compose is not available."
    exit 1
  fi

  print_info "Starting MongoDB and MinIO..."
  (
    cd "${BACKEND_DOCKER_DIR}"
    ${COMPOSE_CMD} up -d mongodb minio
  )

  stop_docker_backend_if_running

  # Backend must connect to Docker-exposed port and use Docker MongoDB auth
  export MONGODB_URI="mongodb://admin:password@127.0.0.1:28017/rloco?authSource=admin"
  print_info "Waiting for MongoDB to accept connections on 127.0.0.1:28017 ..."
  wait_for_port "127.0.0.1" "28017" "mongodb"
fi

if [ "$FORCE" = true ]; then
  if [ "$START_DEPS" = true ]; then
    # If docker compose is managing a backend container bound to 8080, stop it first.
    stop_docker_backend_if_running
  fi
  kill_port_listeners 8080
  kill_port_listeners 5173
else
  if is_port_in_use 8080; then
    print_error "Port 8080 is already in use. Re-run with --force to kill the process, or stop it manually."
    exit 1
  fi
  if is_port_in_use 5173; then
    print_error "Port 5173 is already in use. Re-run with --force to kill the process, or stop it manually."
    exit 1
  fi
fi

if [ ! -d "${FRONTEND_DIR}/node_modules" ] || [ ! -x "${FRONTEND_DIR}/node_modules/.bin/vite" ]; then
  print_info "Installing frontend dependencies with ${PACKAGE_MANAGER}..."
  (
    cd "${FRONTEND_DIR}"
    ${PACKAGE_MANAGER} install
  )
fi

print_info "Downloading backend dependencies..."
(
  cd "${BACKEND_DIR}"
  go mod download
)

print_info "Starting backend on http://localhost:8080 ..."
(
  cd "${BACKEND_DIR}"
  go run ./cmd/server/main.go 2>&1 | sed 's/^/[backend] /'
) &
PIDS+=("$!")

print_info "Starting frontend on http://localhost:5173 ..."
(
  cd "${FRONTEND_DIR}"
  ${PACKAGE_MANAGER} dev 2>&1 | sed 's/^/[frontend] /'
) &
PIDS+=("$!")

print_info "Apps are starting. Press Ctrl+C to stop both."
wait
