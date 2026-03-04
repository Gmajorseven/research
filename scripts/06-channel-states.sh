#!/usr/bin/env bash
# =============================================================================
# 06-channel-states.sh — Inspect channel state machine and revocation data
# =============================================================================
# This script collects and displays the data structures that underpin
# the fraud prevention mechanism — for research documentation purposes.
#
# Observations you can record for your paper:
#   - Commitment transaction IDs per state
#   - HTLC counts and time-lock values
#   - Channel capacity distribution over time
#   - Watchtower session statistics
#
# Usage:
#   bash research/scripts/06-channel-states.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="${SCRIPT_DIR}/../results/${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"

echo "=== Channel State Inspection ========================================"
echo "Results will be saved to: ${OUTPUT_DIR}"
echo ""

# ---- Alice ------------------------------------------------------------------
echo "--- Alice: Channel details ------------------------------------------"
alice listchannels | tee "${OUTPUT_DIR}/alice_channels.json" | \
  jq '[.channels[] | {
    chan_id,
    capacity,
    local_balance,
    remote_balance,
    commit_fee,
    num_updates,
    total_satoshis_sent,
    total_satoshis_received,
    commitment_type,
    csv_delay,
    initiator,
    active
  }]'

echo ""
echo "--- Alice: Forwarding history (routing fees earned) -----------------"
alice fwdinghistory --start_time="-1d" | tee "${OUTPUT_DIR}/alice_forwarding.json" | \
  jq '{
    last_offset_index: .last_offset_index,
    num_events: (.forwarding_events | length),
    total_fee_msat: ([.forwarding_events[].fee_msat | tonumber] | add // 0),
    events: [.forwarding_events[-5:] | .[] | {
      timestamp,
      chan_id_in,
      chan_id_out,
      amt_in_msat,
      amt_out_msat,
      fee_msat
    }]
  }'

echo ""
echo "--- Bob: Channel details (routing node) -----------------------------"
bob listchannels | tee "${OUTPUT_DIR}/bob_channels.json" | \
  jq '[.channels[] | {
    chan_id,
    capacity,
    local_balance,
    remote_balance,
    num_updates,
    commitment_type,
    csv_delay,
    initiator,
    active
  }]'

echo ""
echo "--- Carol: Channel details ------------------------------------------"
carol listchannels | tee "${OUTPUT_DIR}/carol_channels.json" | \
  jq '[.channels[] | {
    chan_id,
    capacity,
    local_balance,
    remote_balance,
    num_updates,
    commitment_type,
    csv_delay,
    active
  }]'

echo ""
echo "=== Pending Channels (force-close / breach monitoring) =============="
echo "--- Alice ---"
alice pendingchannels | tee "${OUTPUT_DIR}/alice_pending.json" | jq '{
  waiting_close_channels: (.waiting_close_channels | length),
  pending_force_closing_channels: (.pending_force_closing_channels | length),
  pending_open_channels: (.pending_open_channels | length)
}'

echo "--- Bob ---"
bob pendingchannels | tee "${OUTPUT_DIR}/bob_pending.json" | jq '{
  waiting_close_channels: (.waiting_close_channels | length),
  pending_force_closing_channels: (.pending_force_closing_channels | length)
}'

echo "--- Carol ---"
carol pendingchannels | tee "${OUTPUT_DIR}/carol_pending.json" | jq '{
  waiting_close_channels: (.waiting_close_channels | length),
  pending_force_closing_channels: (.pending_force_closing_channels | length)
}'

echo ""
echo "=== Network Graph snapshot =========================================="
alice describegraph | tee "${OUTPUT_DIR}/network_graph.json" | jq '{
  num_nodes: (.nodes | length),
  num_edges: (.edges | length),
  nodes: [.nodes[] | {pub_key, alias, color}],
  edges: [.edges[] | {
    channel_id,
    node1_pub,
    node2_pub,
    capacity
  }]
}'

echo ""
echo "=== Blockchain state ================================================"
btc getblockchaininfo | tee "${OUTPUT_DIR}/blockchain_info.json" | jq '{
  chain,
  blocks,
  bestblockhash,
  difficulty,
  mempool_size: .size_on_disk
}'

echo ""
echo "=== Results saved to ${OUTPUT_DIR} =================================="
ls -lh "${OUTPUT_DIR}"

echo ""
echo "To run more payments and re-observe state changes:"
echo "  bash research/scripts/04-payment-routing.sh 10000"
echo "  bash research/scripts/06-channel-states.sh"
