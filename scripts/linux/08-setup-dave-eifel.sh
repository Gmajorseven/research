#!/usr/bin/env bash
# =============================================================================
# 08-setup-dave-eifel.sh — Set up Dave and Eifel nodes (additional LND + ThunderHub)
# =============================================================================
# This script adds Dave and Eifel nodes to the research environment.
# It will:
#   1. Start Dave and Eifel LND containers
#   2. Create/unlock their wallets
#   3. Start their ThunderHub instances
#   4. Verify the new GUI ports respond
#
# Usage:
#   bash scripts/08-setup-dave-eifel.sh
#   bash scripts/08-setup-dave-eifel.sh --build
#
# Optional environment variables:
#   WALLET_PASSWORD=research_wallet_password
#   SETUP_TIMEOUT=180
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT}"

WALLET_PASSWORD="${WALLET_PASSWORD:-research_wallet_password}"
SETUP_TIMEOUT="${SETUP_TIMEOUT:-180}"
LND_UID="${LND_UID:-1001}"
BUILD_IMAGES=0

for arg in "$@"; do
  case "${arg}" in
    --build)
      BUILD_IMAGES=1
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      echo "Usage: bash scripts/08-setup-dave-eifel.sh [--build]" >&2
      exit 1
      ;;
  esac
done

COMPOSE=(docker compose)
NEW_NODES=(dave eifel)
NEW_GUI_PORTS=(3003 3004)

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

container_status() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo "missing"
}

wait_for_container() {
  local container="$1"
  local wanted="$2"
  local elapsed=0
  local status

  while (( elapsed < SETUP_TIMEOUT )); do
    status="$(container_status "${container}")"

    case "${wanted}" in
      healthy)
        [[ "${status}" == "healthy" ]] && return 0
        ;;
      running)
        [[ "${status}" == "running" || "${status}" == "healthy" ]] && return 0
        ;;
      *)
        die "Unknown wait state: ${wanted}"
        ;;
    esac

    sleep 2
    elapsed=$((elapsed + 2))
  done

  die "Container ${container} did not become ${wanted} (last status: ${status})"
}

wait_for_http() {
  local url="$1"
  local elapsed=0

  while (( elapsed < SETUP_TIMEOUT )); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  die "Timed out waiting for ${url}"
}

node_tls_cert() {
  printf '%s/data/%s/tls.cert' "${ROOT}" "$1"
}

node_admin_macaroon_path() {
  printf '/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon'
}

node_has_admin_macaroon() {
  docker exec "lnd-$1" sh -lc "[ -f $(node_admin_macaroon_path) ]" >/dev/null 2>&1
}

node_state() {
  docker exec "lnd-$1" lncli \
    --network=regtest \
    --rpcserver=localhost:10009 \
    --tlscertpath=/home/lnd/.lnd/tls.cert \
    state 2>/dev/null | sed -n 's/.*"state":[[:space:]]*"\([^"]*\)".*/\1/p'
}

wait_for_node_rpc() {
  local node="$1"
  local elapsed=0

  while (( elapsed < SETUP_TIMEOUT )); do
    if docker exec "lnd-${node}" lncli \
      --network=regtest \
      --rpcserver=localhost:10009 \
      --tlscertpath=/home/lnd/.lnd/tls.cert \
      --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon \
      getinfo >/dev/null 2>&1; then
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  die "Timed out waiting for lnd-${node} RPC readiness"
}

ensure_tls_cert() {
  local node="$1"
  local cert

  cert="$(node_tls_cert "${node}")"

  if [[ -f "${cert}" ]] && openssl x509 -in "${cert}" -noout -text 2>/dev/null | grep -q "DNS:lnd-${node}"; then
    return 0
  fi

  log "Generating TLS cert for ${node} with Docker hostname SAN"

  "${COMPOSE[@]}" stop "thunderhub-${node}" "lnd-${node}" >/dev/null 2>&1 || true

  docker run --rm -v "${ROOT}/data/${node}:/mnt" alpine sh -lc "
    apk add --no-cache openssl >/dev/null &&
    rm -f /mnt/tls.cert /mnt/tls.key &&
    cat > /tmp/openssl.cnf <<EOF
[req]
distinguished_name=req_distinguished_name
x509_extensions=v3_req
prompt=no
[req_distinguished_name]
CN=lnd-${node}
[v3_req]
subjectAltName=@alt_names
[alt_names]
DNS.1=localhost
DNS.2=lnd-${node}
IP.1=127.0.0.1
EOF
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout /mnt/tls.key \
      -out /mnt/tls.cert \
      -config /tmp/openssl.cnf \
      -extensions v3_req >/dev/null 2>&1 &&
    chown ${LND_UID}:${LND_UID} /mnt/tls.cert /mnt/tls.key &&
    chmod 644 /mnt/tls.cert &&
    chmod 600 /mnt/tls.key
  " >/dev/null

  local up_args=(up -d)
  (( BUILD_IMAGES == 1 )) && up_args+=(--build)
  "${COMPOSE[@]}" "${up_args[@]}" "lnd-${node}" >/dev/null
  wait_for_container "lnd-${node}" healthy
}


create_wallet() {
  local node="$1"
  local log_file

  log_file="$(mktemp)"
  log "Creating wallet for ${node}"

  if ! printf '%s\n%s\nn\n\n' "${WALLET_PASSWORD}" "${WALLET_PASSWORD}" | \
      script -qefc "docker exec -it lnd-${node} lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert create" /dev/null \
      >"${log_file}" 2>&1; then
    cat "${log_file}" >&2
    rm -f "${log_file}"
    die "Wallet creation failed for ${node}"
  fi

  rm -f "${log_file}"
  node_has_admin_macaroon "${node}" || die "admin.macaroon was not created for ${node}"
}

unlock_wallet() {
  local node="$1"

  log "Unlocking wallet for ${node}"

  if ! printf '%s\n' "${WALLET_PASSWORD}" | docker exec -i "lnd-${node}" lncli \
      --network=regtest \
      --rpcserver=localhost:10009 \
      --tlscertpath=/home/lnd/.lnd/tls.cert \
      unlock --stdin >/dev/null 2>&1; then
    die "Wallet unlock failed for ${node}"
  fi
}

ensure_wallet_ready() {
  local node="$1"
  local state

  state="$(node_state "${node}")"

  if node_has_admin_macaroon "${node}"; then
    if [[ "${state}" == "LOCKED" ]]; then
      unlock_wallet "${node}"
    else
      log "Wallet for ${node} already initialized (${state:-unknown state})"
    fi
  else
    create_wallet "${node}"
  fi

  wait_for_node_rpc "${node}"
}

wait_for_thunderhub_connection() {
  local node="$1"
  local elapsed=0

  while (( elapsed < SETUP_TIMEOUT )); do
    if docker logs "thunderhub-${node}" 2>&1 | grep -q "Connected to"; then
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  warn "ThunderHub ${node} did not report a node connection within timeout"
  docker logs "thunderhub-${node}" 2>&1 | tail -20 >&2 || true
  return 1
}

initialize_node_wallet() {
  local node="$1"
  # This function is now replaced by create_wallet/unlock_wallet/ensure_wallet_ready
  # Kept for backward compatibility
  ensure_wallet_ready "${node}"
}

log "=== Dave & Eifel Extended Node Setup =================================="

require_cmd docker
require_cmd script
require_cmd openssl
require_cmd curl

if [[ ${BUILD_IMAGES} -eq 1 ]]; then
  log "Building Docker images (--build)..."
  "${COMPOSE[@]}" build --no-cache lnd thunderhub
fi

log ""
log "Step 1: Start Dave & Eifel LND containers =============================="

"${COMPOSE[@]}" up -d lnd-dave lnd-eifel >/dev/null

log ""
log "Step 2: Wait for LND containers to be healthy =========================="

for node in "${NEW_NODES[@]}"; do
  log "Waiting for lnd-${node} to be healthy..."
  wait_for_container "lnd-${node}" "healthy"
done

log ""
log "Step 3: Ensure TLS certs contain service names ========================="

for node in "${NEW_NODES[@]}"; do
  ensure_tls_cert "${node}"
done

log ""
log "Step 4: Initialize/unlock wallets ======================================"

for node in "${NEW_NODES[@]}"; do
  ensure_wallet_ready "${node}"
done

log ""
log "Step 5: Start ThunderHub instances ====================================="

"${COMPOSE[@]}" up -d --force-recreate thunderhub-dave thunderhub-eifel >/dev/null

log ""
log "Step 6: Wait for ThunderHub services to be ready ======================="

for node in "${NEW_NODES[@]}"; do
  log "Waiting for thunderhub-${node} to be running..."
  wait_for_container "thunderhub-${node}" "running"
done

for port in "${NEW_GUI_PORTS[@]}"; do
  log "Waiting for http://localhost:${port}"
  wait_for_http "http://localhost:${port}"
done

log ""
log "Step 7: Verify ThunderHub node connections ============================="

wait_for_thunderhub_connection dave || true
wait_for_thunderhub_connection eifel || true

log ""
log "▶▶▶ SUCCESS ▶▶▶ Dave and Eifel nodes are ready! =================================================="
log ""

for i in "${!NEW_NODES[@]}"; do
  node="${NEW_NODES[$i]}"
  port="${NEW_GUI_PORTS[$i]}"
  lnd_uname=$(echo "${node}" | tr '[:lower:]' '[:upper:]')
  echo "${lnd_uname} ThunderHub:  http://localhost:${port}"
done

log ""
log "You can now use the nodes in scripts:"
log "  source scripts/linux/helpers.sh"
log "  dave getinfo"
log "  eifel getinfo"
log ""
log "To fund the new nodes, run:"
log "  bash scripts/linux/09-fund-dave-eifel.sh"
log ""
log "To connect them to the network, run:"
log "  bash scripts/linux/10-connect-dave-eifel.sh"
log ""
