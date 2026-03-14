#!/usr/bin/env bash
# =============================================================================
# 02-connect-peers.sh — Connect nodes and open channels
# =============================================================================
# Builds the network topology:
#
#   Alice ──[500k sat]──► Bob ──[500k sat]──► Carol
#
# Alice opens a channel TO Bob (Alice is funder).
# Bob opens a channel TO Carol (Bob is funder).
# Both channels are announced so routing tables are populated.
#
# Usage:
#   bash research/scripts/02-connect-peers.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CHANNEL_SIZE=500000         # 500k sats per channel
PUSH_AMOUNT=100000          # Push 100k sats to the remote side on open
                            # (so both sides have balance for routing)

echo "=== Step 1: Get node pubkeys ========================================"
ALICE_PUBKEY=$(alice getinfo | jq -r '.identity_pubkey')
BOB_PUBKEY=$(bob   getinfo | jq -r '.identity_pubkey')
CAROL_PUBKEY=$(carol getinfo | jq -r '.identity_pubkey')

echo "Alice pubkey: ${ALICE_PUBKEY}"
echo "Bob pubkey  : ${BOB_PUBKEY}"
echo "Carol pubkey: ${CAROL_PUBKEY}"

echo ""
echo "=== Step 2: Connect peers ==========================================="
# Alice <-> Bob
echo "Connecting Alice -> Bob..."
alice connect "${BOB_PUBKEY}@lnd-bob:9735" 2>/dev/null || echo "  (already connected)"

# Bob <-> Carol
echo "Connecting Bob -> Carol..."
bob connect "${CAROL_PUBKEY}@lnd-carol:9735" 2>/dev/null || echo "  (already connected)"

echo ""
echo "=== Step 3: Open channels ==========================================="
echo "Alice -> Bob channel (${CHANNEL_SIZE} sat, push ${PUSH_AMOUNT} to Bob)..."
alice openchannel \
  --node_key="${BOB_PUBKEY}" \
  --local_amt="${CHANNEL_SIZE}" \
  --push_amt="${PUSH_AMOUNT}"

echo ""
echo "Bob -> Carol channel (${CHANNEL_SIZE} sat, push ${PUSH_AMOUNT} to Carol)..."
bob openchannel \
  --node_key="${CAROL_PUBKEY}" \
  --local_amt="${CHANNEL_SIZE}" \
  --push_amt="${PUSH_AMOUNT}"

echo ""
echo "=== Step 4: Mine 6 blocks to confirm channel funding txs ==========="
mine 6

echo ""
echo "=== Channel status =================================================="
echo "--- Alice channels ---"
alice listchannels | jq '[.channels[] | {remote_pubkey, capacity, local_balance, remote_balance, active}]'

echo ""
echo "--- Bob channels ---"
bob listchannels | jq '[.channels[] | {remote_pubkey, capacity, local_balance, remote_balance, active}]'

echo ""
echo "Next: bash research/scripts/03-payment-routing.sh"
