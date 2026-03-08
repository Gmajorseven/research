#!/usr/bin/env bash
# =============================================================================
# 02-fund-nodes.sh — Mine regtest blocks and fund Alice, Bob, Carol
# =============================================================================
# In regtest, coins are mined from nothing — no real value.
# We:
#   1. Mine 101 blocks so coins are spendable (coinbase maturity = 100 blocks)
#   2. Give Alice, Bob, and Carol on-chain funds to open channels
#
# Usage:
#   bash research/scripts/02-fund-nodes.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

echo "=== Step 1: Mine 101 blocks (coinbase maturity) ====================="
MINE_ADDR=$(btc getnewaddress)
btc generatetoaddress 101 "${MINE_ADDR}" | tail -1
echo "101 blocks mined. Bitcoin balance available."

echo ""
echo "=== Step 2: Get deposit addresses ==================================="
ALICE_ADDR=$(alice newaddress p2wkh | jq -r '.address')
BOB_ADDR=$(bob   newaddress p2wkh | jq -r '.address')
CAROL_ADDR=$(carol newaddress p2wkh | jq -r '.address')

echo "Alice address : ${ALICE_ADDR}"
echo "Bob address   : ${BOB_ADDR}"
echo "Carol address : ${CAROL_ADDR}"

echo ""
echo "=== Step 3: Send 2 BTC to each node ================================="
btc sendtoaddress "${ALICE_ADDR}" 2
btc sendtoaddress "${BOB_ADDR}"   2
btc sendtoaddress "${CAROL_ADDR}" 2

echo ""
echo "=== Step 4: Mine 6 more blocks to confirm ==========================="
mine 6

echo ""
echo "=== Balances ========================================================="
echo -n "Alice on-chain: "; alice walletbalance | jq '.confirmed_balance'
echo -n "Bob on-chain  : "; bob   walletbalance | jq '.confirmed_balance'
echo -n "Carol on-chain: "; carol walletbalance | jq '.confirmed_balance'

echo ""
echo "Next: bash research/scripts/03-connect-peers.sh"
