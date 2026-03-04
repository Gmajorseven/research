#!/usr/bin/env bash
# =============================================================================
# 02-fund-nodes.sh — Get deposit addresses and guide testnet4 faucet funding
# =============================================================================
# On testnet4 (public network), coins must come from a faucet — you cannot
# mine blocks yourself. This script:
#   1. Prints the on-chain deposit addresses for Alice, Bob, and Carol
#   2. Prompts you to fund them via a testnet4 faucet
#   3. Waits and checks balances once funding is confirmed
#
# Testnet4 faucets:
#   https://mempool.space/testnet4
#   https://coinfaucet.eu/en/btc-testnet/
#   https://bitcoinfaucet.uo1.net/
#
# Usage:
#   bash research/scripts/02-fund-nodes.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

echo "=== Step 1: Get deposit addresses ==================================="
ALICE_ADDR=$(alice newaddress p2wkh | jq -r '.address')
BOB_ADDR=$(bob   newaddress p2wkh | jq -r '.address')
CAROL_ADDR=$(carol newaddress p2wkh | jq -r '.address')

echo ""
echo "Alice address : ${ALICE_ADDR}"
echo "Bob address   : ${BOB_ADDR}"
echo "Carol address : ${CAROL_ADDR}"

echo ""
echo "=== Step 2: Fund via testnet4 faucet ================================"
echo ""
echo "Send at least 0.002 tBTC to each address using a faucet:"
echo "  https://mempool.space/testnet4"
echo ""
echo "  Alice : ${ALICE_ADDR}"
echo "  Bob   : ${BOB_ADDR}"
echo "  Carol : ${CAROL_ADDR}"
echo ""
read -rp "Press ENTER once you have submitted the faucet requests..."

echo ""
echo "=== Step 3: Wait for confirmations =================================="
echo "Waiting for at least 1 confirmation (testnet4 ~10 min blocks)..."
echo "You can also check progress at: https://mempool.space/testnet4"
echo ""
for i in $(seq 1 60); do
  ALICE_BAL=$(alice walletbalance | jq -r '.confirmed_balance // "0"')
  BOB_BAL=$(bob   walletbalance | jq -r '.confirmed_balance // "0"')
  CAROL_BAL=$(carol walletbalance | jq -r '.confirmed_balance // "0"')

  if [[ "${ALICE_BAL}" != "0" && "${BOB_BAL}" != "0" && "${CAROL_BAL}" != "0" ]]; then
    echo "All nodes funded!"
    break
  fi

  echo "  [${i}/60] Waiting... Alice=${ALICE_BAL} sat | Bob=${BOB_BAL} sat | Carol=${CAROL_BAL} sat"
  sleep 30
done

echo ""
echo "=== Balances ========================================================="
echo -n "Alice on-chain (sat): "; alice walletbalance | jq '.confirmed_balance'
echo -n "Bob on-chain (sat)  : "; bob   walletbalance | jq '.confirmed_balance'
echo -n "Carol on-chain (sat): "; carol walletbalance | jq '.confirmed_balance'

echo ""
echo "Next: bash research/scripts/03-connect-peers.sh"

