#!/usr/bin/env bash
# =============================================================================
# 09-fund-dave-eifel.sh — Fund Dave and Eifel nodes with on-chain Bitcoin
# =============================================================================
# This script funds the Dave and Eifel nodes with regtest Bitcoin so they
# can open Lightning channels.
#
# Prerequisites:
#   - Both Dave and Eifel LND nodes must be running and initialized
#   - Run: bash scripts/08-setup-dave-eifel.sh
#
# Usage:
#   bash scripts/09-fund-dave-eifel.sh
#
# Optional environment variables:
#   FUND_AMOUNT=2        # BTC to send to each node (default: 2)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

FUND_AMOUNT="${FUND_AMOUNT:-2}"

echo "=== Dave & Eifel Node Funding Script ================================"
echo ""

btc_wallet_ready

# Check that dave and eifel wallets are initialized
if ! dave walletbalance >/dev/null 2>&1 || ! eifel walletbalance >/dev/null 2>&1; then
	echo "ERROR: Dave or Eifel wallet not initialized or locked."
	echo "Run: bash scripts/08-setup-dave-eifel.sh"
	echo "Then retry: bash scripts/09-fund-dave-eifel.sh"
	exit 1
fi

echo "=== Step 1: Check Bitcoin balance ==================================="
BTC_BALANCE=$(btc getbalance)
echo "Bitcoin on-chain balance: ${BTC_BALANCE} BTC"

if (( $(echo "${BTC_BALANCE} < 5" | bc -l) )); then
	echo ""
	echo "WARNING: Low Bitcoin balance (need at least 5 BTC to fund both nodes)"
	echo "Mining additional blocks to generate coins..."
	mine 50
fi

echo ""
echo "=== Step 2: Get deposit addresses ==================================="
DAVE_ADDR=$(dave newaddress p2wkh | jq -r '.address')
EIFEL_ADDR=$(eifel newaddress p2wkh | jq -r '.address')

echo "Dave address  : ${DAVE_ADDR}"
echo "Eifel address : ${EIFEL_ADDR}"

echo ""
echo "=== Step 3: Send ${FUND_AMOUNT} BTC to each node ========================="
btc sendtoaddress "${DAVE_ADDR}" "${FUND_AMOUNT}"
btc sendtoaddress "${EIFEL_ADDR}" "${FUND_AMOUNT}"

echo ""
echo "=== Step 4: Mine 6 blocks to confirm ================================="
mine 6

echo ""
echo "=== Balances ========================================================="
echo -n "Dave on-chain : "; dave walletbalance | jq '.confirmed_balance'
echo -n "Eifel on-chain: "; eifel walletbalance | jq '.confirmed_balance'

echo ""
echo "✓ Dave and Eifel funding complete!"
echo ""
echo "Next steps:"
echo "     Connect Dave/Eifel to the network:"
echo "     bash scripts/linux/10-connect-dave-eifel.sh"
echo "     (or open channels manually)"
