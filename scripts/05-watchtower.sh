#!/usr/bin/env bash
# =============================================================================
# 05-watchtower.sh — Configure and verify the Watchtower (fraud prevention)
# =============================================================================
# The LND Watchtower is a key fraud-prevention mechanism in the Lightning
# Network. This script:
#
#   1. Retrieves Alice's watchtower URI (she runs the tower server)
#   2. Registers Bob and Carol as watchtower clients
#   3. Verifies tower sessions are established
#   4. Explains how the justice (penalty) transaction mechanism works
#
# Watchtower workflow:
#   - Every time channel state advances (payment made), LND automatically
#     encrypts a "breach remedy transaction" (justice tx) and uploads it
#     to the tower.
#   - If a channel counterparty goes offline and an old state is broadcast,
#     the tower detects it on-chain and broadcasts the justice tx, which
#     sends ALL channel funds to the honest party as a penalty.
#
# Usage:
#   bash research/scripts/05-watchtower.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

echo "=== Watchtower Configuration ========================================"
echo ""

echo "--- Alice's Watchtower Server info ----------------------------------"
alice tower info 2>/dev/null || \
  docker exec lnd-alice lncli \
    --network=testnet4 --rpcserver=localhost:10009 \
    --tlscertpath=/home/lnd/.lnd/tls.cert \
    --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/testnet4/admin.macaroon \
    tower info

echo ""
echo "--- Getting Alice's tower URI ---------------------------------------"
TOWER_URI=$(docker exec lnd-alice lncli \
  --network=testnet4 --rpcserver=localhost:10009 \
  --tlscertpath=/home/lnd/.lnd/tls.cert \
  --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/testnet4/admin.macaroon \
  tower info | jq -r '.uris[0]')

echo "Tower URI: ${TOWER_URI}"

if [[ -z "${TOWER_URI}" || "${TOWER_URI}" == "null" ]]; then
  echo ""
  echo "WARNING: Tower URI not available yet."
  echo "         Make sure Alice's lnd.conf has [Watchtower] watchtower.active=true"
  echo "         and restart Alice: docker compose -f docker-compose.research.yml restart lnd-alice"
  exit 1
fi

echo ""
echo "--- Registering Bob as a watchtower client --------------------------"
echo "Bob adding tower ${TOWER_URI}..."
docker exec lnd-bob lncli \
  --network=testnet4 --rpcserver=localhost:10009 \
  --tlscertpath=/home/lnd/.lnd/tls.cert \
  --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/testnet4/admin.macaroon \
  wtclient add "${TOWER_URI}"

echo ""
echo "--- Registering Carol as a watchtower client ------------------------"
echo "Carol adding tower ${TOWER_URI}..."
docker exec lnd-carol lncli \
  --network=testnet4 --rpcserver=localhost:10009 \
  --tlscertpath=/home/lnd/.lnd/tls.cert \
  --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/testnet4/admin.macaroon \
  wtclient add "${TOWER_URI}"

echo ""
echo "--- Verify Bob's tower sessions -------------------------------------"
docker exec lnd-bob lncli \
  --network=testnet4 --rpcserver=localhost:10009 \
  --tlscertpath=/home/lnd/.lnd/tls.cert \
  --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/testnet4/admin.macaroon \
  wtclient towers | jq '[.towers[] | {pubkey, active_session_candidate, num_sessions}]'

echo ""
echo "--- Verify Carol's tower sessions -----------------------------------"
docker exec lnd-carol lncli \
  --network=testnet4 --rpcserver=localhost:10009 \
  --tlscertpath=/home/lnd/.lnd/tls.cert \
  --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/testnet4/admin.macaroon \
  wtclient towers | jq '[.towers[] | {pubkey, active_session_candidate, num_sessions}]'

echo ""
echo "--- Tower Statistics (Alice) ----------------------------------------"
docker exec lnd-alice lncli \
  --network=testnet4 --rpcserver=localhost:10009 \
  --tlscertpath=/home/lnd/.lnd/tls.cert \
  --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/testnet4/admin.macaroon \
  tower stats 2>/dev/null || echo "(tower stats not available in this LND version)"

echo ""
cat <<'INFO'
=== How Fraud Prevention Works (Justice Transaction Mechanism) =============

1. CHANNEL STATE MACHINE
   Each payment in a channel advances the state: State 0 → 1 → 2 → N
   The parties exchange "revocation keys" to invalidate old states.
   
2. COMMITMENT TRANSACTIONS
   Each state has a commitment tx signed by both parties.
   Old states are "revoked" — broadcasting them is a protocol violation.

3. BREACH REMEDY (JUSTICE) TRANSACTION
   For every state update, LND pre-computes a justice tx that spends
   ALL channel funds to the honest party if an old state is broadcast.
   
4. WATCHTOWER ROLE
   - Bob/Carol encrypt the justice tx and send it to Alice's tower.
   - The encryption key is derived from the txid of the revoked state,
     so the tower cannot spy on channel activity.
   - The tower monitors the blockchain 24/7.
   - If a revoked commitment tx appears on-chain, the tower decrypts
     the justice tx and broadcasts it within the CSV delay window.

5. PENALTY
   The cheating party loses ALL their funds in the channel.
   This economic disincentive is the core fraud prevention mechanism.

=== Key lncli commands for monitoring ======================================

  # Check tower client status
  bob wtclient towers
  bob wtclient sessions <tower_pubkey>

  # Check for any pending force-close / breach attempts
  bob pendingchannels
  alice pendingchannels

  # Watch LND logs for "BREACH" events
  docker logs lnd-alice --follow | grep -i "breach\|justice\|revok"
  docker logs lnd-bob   --follow | grep -i "breach\|justice\|revok"

INFO

echo "Watchtower setup complete."
echo "Next: bash research/scripts/06-channel-states.sh"
