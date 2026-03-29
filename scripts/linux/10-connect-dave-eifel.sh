#!/usr/bin/env bash
# =============================================================================
# 10-connect-dave-eifel.sh — Connect Dave and Eifel to existing network
# =============================================================================
# Extends the existing network topology by adding Dave and Eifel nodes:
#
# EXISTING:    Alice ──[500k sat]──► Bob ──[500k sat]──► Carol
#
# ADDED:       Carol ──[500k sat]──► Alice
#              Dave  ──[500k sat]──► Alice
#              Eifel ──[500k sat]──► Bob
#
# This creates a mesh topology with Alice and Bob as hubs for multi-hop routing.
#
# Prerequisites:
#   - Run: bash scripts/01-fund-nodes.sh       (fund Alice, Bob, Carol)
#   - Run: bash scripts/02-connect-peers.sh    (create initial topology)
#   - Run: bash scripts/08-setup-dave-eifel.sh (set up Dave and Eifel)
#   - Run: bash scripts/09-fund-dave-eifel.sh  (fund Dave and Eifel)
#
# Usage:
#   bash scripts/10-connect-dave-eifel.sh
#
# Optional environment variables:
#   CHANNEL_SIZE=500000    Channel capacity in satoshis (default: 500000)
#   PUSH_AMOUNT=100000     Push amount to remote side (default: 100000)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CHANNEL_SIZE="${CHANNEL_SIZE:-500000}"         # 500k sats per channel
PUSH_AMOUNT="${PUSH_AMOUNT:-100000}"           # Push 100k sats to each side

echo "=== Dave & Eifel Network Connection Script ========================"
echo ""

echo "=== Step 1: Get all node pubkeys ==================================="
ALICE_PUBKEY=$(alice getinfo | jq -r '.identity_pubkey')
BOB_PUBKEY=$(bob   getinfo | jq -r '.identity_pubkey')
CAROL_PUBKEY=$(carol getinfo | jq -r '.identity_pubkey')
DAVE_PUBKEY=$(dave   getinfo | jq -r '.identity_pubkey')
EIFEL_PUBKEY=$(eifel getinfo | jq -r '.identity_pubkey')

echo "Alice pubkey: ${ALICE_PUBKEY}"
echo "Bob pubkey  : ${BOB_PUBKEY}"
echo "Carol pubkey: ${CAROL_PUBKEY}"
echo "Dave pubkey : ${DAVE_PUBKEY}"
echo "Eifel pubkey: ${EIFEL_PUBKEY}"

echo ""
echo "=== Step 2: Connect peers =========================================="

# Carol to Alice (if not already connected)
echo "Connecting Carol -> Alice..."
carol connect "${ALICE_PUBKEY}@lnd-alice:9735" 2>/dev/null || echo "  (already connected)"

# Dave to Alice (if not already connected)
echo "Connecting Dave -> Alice..."
dave connect "${ALICE_PUBKEY}@lnd-alice:9735" 2>/dev/null || echo "  (already connected)"

# Eifel to Bob (if not already connected)
echo "Connecting Eifel -> Bob..."
eifel connect "${BOB_PUBKEY}@lnd-bob:9735" 2>/dev/null || echo "  (already connected)"

# Alice to Dave (if not already connected)
echo "Connecting Alice -> Dave..."
alice connect "${DAVE_PUBKEY}@lnd-dave:9735" 2>/dev/null || echo "  (already connected)"

# Alice to Carol (if not already connected)
echo "Connecting Alice -> Carol..."
alice connect "${CAROL_PUBKEY}@lnd-carol:9735" 2>/dev/null || echo "  (already connected)"

# Bob to Eifel (if not already connected)
echo "Connecting Bob -> Eifel..."
bob connect "${EIFEL_PUBKEY}@lnd-eifel:9735" 2>/dev/null || echo "  (already connected)"

echo ""
echo "=== Step 3: Open new channels ====================================="

echo ""
echo "Carol -> Alice channel (${CHANNEL_SIZE} sat, push ${PUSH_AMOUNT} satoshis)..."
carol openchannel \
  --node_key="${ALICE_PUBKEY}" \
  --local_amt="${CHANNEL_SIZE}" \
  --push_amt="${PUSH_AMOUNT}"

echo ""
echo "Dave -> Alice channel (${CHANNEL_SIZE} sat, push ${PUSH_AMOUNT} satoshis)..."
dave openchannel \
  --node_key="${ALICE_PUBKEY}" \
  --local_amt="${CHANNEL_SIZE}" \
  --push_amt="${PUSH_AMOUNT}"

echo ""
echo "Eifel -> Bob channel (${CHANNEL_SIZE} sat, push ${PUSH_AMOUNT} satoshis)..."
eifel openchannel \
  --node_key="${BOB_PUBKEY}" \
  --local_amt="${CHANNEL_SIZE}" \
  --push_amt="${PUSH_AMOUNT}"

echo ""
echo "=== Step 4: Mine 6 blocks to confirm channel funding txs =========="
mine 6

echo ""
echo "=== Network Topology ================================================"
echo ""
echo "EXISTING CHANNELS:"
echo "  Alice <---> Bob <---> Carol"
echo ""
echo "NEW CHANNELS:"
echo "  Carol <---> Alice"
echo "  Dave  <---> Alice"
echo "  Eifel <---> Bob"
echo ""
echo "RESULTING MESH:"
echo "        Carol"
echo "       /     \\"
echo "  Dave-Alice--Bob-Eifel"
echo ""

echo "=== Channel status =================================================="
echo ""
echo "--- Alice channels ---"
alice listchannels | jq -r '.channels[] | 
  "Channel with \(.remote_pubkey[0:16])... capacity: \(.capacity) sats, local: \(.local_balance), remote: \(.remote_balance), active: \(.active)"'

echo ""
echo "--- Bob channels ---"
bob listchannels | jq -r '.channels[] | 
  "Channel with \(.remote_pubkey[0:16])... capacity: \(.capacity) sats, local: \(.local_balance), remote: \(.remote_balance), active: \(.active)"'

echo ""
echo "--- Carol channels ---"
carol listchannels | jq -r '.channels[] | 
  "Channel with \(.remote_pubkey[0:16])... capacity: \(.capacity) sats, local: \(.local_balance), remote: \(.remote_balance), active: \(.active)"'

echo ""
echo "--- Dave channels ---"
dave listchannels | jq -r '.channels[] | 
  "Channel with \(.remote_pubkey[0:16])... capacity: \(.capacity) sats, local: \(.local_balance), remote: \(.remote_balance), active: \(.active)"'

echo ""
echo "--- Eifel channels ---"
eifel listchannels | jq -r '.channels[] | 
  "Channel with \(.remote_pubkey[0:16])... capacity: \(.capacity) sats, local: \(.local_balance), remote: \(.remote_balance), active: \(.active)"'

echo ""
echo "✓ Network topology update complete!"
echo ""