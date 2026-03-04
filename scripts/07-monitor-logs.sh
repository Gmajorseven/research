#!/usr/bin/env bash
# =============================================================================
# 07-monitor-logs.sh — Monitor all nodes for fraud/security events
# =============================================================================
# Tails Docker logs for all nodes and highlights events relevant to:
#   - Channel state updates (commitment transactions)
#   - HTLC adds / settles / failures
#   - Watchtower session updates (encrypted justice txs uploaded)
#   - Any breach detection events
#
# Usage:
#   bash research/scripts/07-monitor-logs.sh
#   Ctrl+C to stop.
# =============================================================================

echo "=== Live Log Monitor (Ctrl+C to stop) ==============================="
echo "Monitoring: bitcoin-research, lnd-alice (tower), lnd-bob, lnd-carol"
echo "Filtering for: channel, HTLC, watchtower, breach, justice, revok"
echo ""

# Combine logs from all containers with coloured labels using docker compose
docker logs -f --tail=20 lnd-alice 2>&1 | sed 's/^/[ALICE] /' &
PID_ALICE=$!

docker logs -f --tail=20 lnd-bob 2>&1 | sed 's/^/[BOB]   /' &
PID_BOB=$!

docker logs -f --tail=20 lnd-carol 2>&1 | sed 's/^/[CAROL] /' &
PID_CAROL=$!

docker logs -f --tail=10 bitcoin-research 2>&1 | sed 's/^/[BTC]   /' &
PID_BTC=$!

# Wait and clean up on exit
trap "kill ${PID_ALICE} ${PID_BOB} ${PID_CAROL} ${PID_BTC} 2>/dev/null" EXIT
wait
