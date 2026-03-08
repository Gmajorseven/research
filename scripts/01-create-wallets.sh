#!/usr/bin/env bash
# =============================================================================
# 01-create-wallets.sh — Create wallets for Alice, Bob, and Carol
# =============================================================================
# Creates wallets non-interactively using `lncli create` with --noseedbackup.
# Only run this ONCE after the first `docker compose up`.
#
# Usage:
#   bash research/scripts/01-create-wallets.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

NETWORK="regtest"
PASSWORD="research_wallet_password"  # Use a stronger password for real work

create_wallet() {
  local node="$1"
  echo "-------------------------------------------------------------------"
  echo "Creating wallet for ${node}..."
  docker exec -i "lnd-${node}" lncli \
    --network="${NETWORK}" \
    --rpcserver=localhost:10009 \
    --tlscertpath=/home/lnd/.lnd/tls.cert \
    create <<EOF
${PASSWORD}
${PASSWORD}
n

EOF
  echo "Wallet created for ${node}."
}

create_wallet alice
create_wallet bob
create_wallet carol

echo ""
echo "All wallets created."
echo "Next: bash research/scripts/02-fund-nodes.sh"
