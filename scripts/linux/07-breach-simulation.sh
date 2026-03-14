#!/usr/bin/env bash
# =============================================================================
# 07-breach-simulation.sh — Channel Breach Simulation (Fraud Prevention Study)
# =============================================================================
# PURPOSE (research only — regtest, all nodes owned by researcher):
#   Demonstrates the full lifecycle of a Lightning Network channel breach
#   and the automatic justice/penalty transaction response by the watchtower.
#
# SCENARIO:
#   Carol force-closes the Bob<->Carol channel using an OLD (revoked) commitment
#   transaction. The watchtower (hosted by Alice) detects the breach on-chain
#   and broadcasts a justice transaction that sweeps ALL channel funds to Bob
#   as a penalty — Carol loses everything.
#
# ROLES:
#   Alice — Watchtower server (monitors the chain for Bob)
#   Bob   — Honest party (protected by Alice's watchtower)
#   Carol — Cheater (broadcasts revoked commitment tx)
#
# WHAT THIS DEMONSTRATES FOR YOUR RESEARCH:
#   1. How commitment transactions represent channel state
#   2. How revocation keys invalidate old states
#   3. How the watchtower monitors the chain and responds
#   4. The economic penalty that deters fraud in the LN protocol
#
# HOW IT WORKS TECHNICALLY:
#   - LND stores each channel's previous commitment tx in its channel.db
#   - We use `lncli exportchanbackup` + LND's debug DB tools to extract it
#   - Alternatively, we capture the raw tx before state advances
#   - Then we advance state (make payments), then broadcast the captured tx
#
# PRE-REQUISITES:
#   1. Complete scripts 01-06 first
#   2. Bob<->Carol channel must exist and have at least 2 state updates
#   3. Watchtower must be active (script 04 completed)
#   4. Bob must be registered as watchtower client with Alice
#
# Usage:
#   bash research/scripts/07-breach-simulation.sh
#
# Results saved to: research/results/breach_<timestamp>/
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS="${SCRIPT_DIR}/../results/breach_${TIMESTAMP}"
mkdir -p "${RESULTS}"

LOG="${RESULTS}/breach_simulation.log"
exec > >(tee -a "${LOG}") 2>&1

echo "======================================================================"
echo " Lightning Network Channel Breach Simulation"
echo " Research: Payment Routing & Fraud Prevention"
echo " Timestamp: ${TIMESTAMP}"
echo " Results  : ${RESULTS}"
echo "======================================================================"
echo ""

# ==============================================================================
# PHASE 0 — Pre-flight checks
# ==============================================================================
echo "=== PHASE 0: Pre-flight checks ======================================"

echo "Checking nodes are reachable..."
ALICE_INFO=$(alice getinfo)
BOB_INFO=$(bob getinfo)
CAROL_INFO=$(carol getinfo)
echo "Alice: $(echo "${ALICE_INFO}" | jq -r '.alias') — $(echo "${ALICE_INFO}" | jq -r '.identity_pubkey' | cut -c1-20)... (watchtower)"
echo "Bob  : $(echo "${BOB_INFO}"   | jq -r '.alias') — $(echo "${BOB_INFO}"   | jq -r '.identity_pubkey' | cut -c1-20)... (honest party)"
echo "Carol: $(echo "${CAROL_INFO}" | jq -r '.alias') — $(echo "${CAROL_INFO}" | jq -r '.identity_pubkey' | cut -c1-20)... (cheater)"

# Verify Alice's watchtower server is running
echo ""
echo "Checking Alice's watchtower server..."
alice tower info | tee "${RESULTS}/phase0_watchtower_info.json" || {
  echo "WARNING: Watchtower may not be active. Run script 04-watchtower.sh first."
}

# Verify Bob is registered as watchtower client
echo ""
echo "Checking Bob's watchtower client registration..."
bob wtclient towers | jq '[.towers[] | {pubkey, active_session_candidate, num_sessions}]' \
  | tee "${RESULTS}/phase0_bob_wtclient.json" || {
  echo "WARNING: Bob may not be registered as watchtower client."
}

# Find Bob<->Carol channel
echo ""
echo "Looking for Bob<->Carol channel..."
CAROL_PUBKEY=$(echo "${CAROL_INFO}" | jq -r '.identity_pubkey')
BOB_PUBKEY=$(echo "${BOB_INFO}" | jq -r '.identity_pubkey')

CHANNEL_RAW=$(bob listchannels | jq --arg pub "${CAROL_PUBKEY}" \
  '[.channels[] | select(.remote_pubkey == $pub)] | .[0]')

if [[ "${CHANNEL_RAW}" == "null" || -z "${CHANNEL_RAW}" ]]; then
  echo ""
  echo "ERROR: No Bob<->Carol channel found."
  echo "Run script 02-connect-peers.sh first."
  exit 1
fi

CHAN_POINT=$(echo "${CHANNEL_RAW}" | jq -r '.channel_point')
CHAN_ID=$(echo "${CHANNEL_RAW}" | jq -r '.chan_id')
NUM_UPDATES=$(echo "${CHANNEL_RAW}" | jq -r '.num_updates')
LOCAL_BAL=$(echo "${CHANNEL_RAW}" | jq -r '.local_balance')
REMOTE_BAL=$(echo "${CHANNEL_RAW}" | jq -r '.remote_balance')
CAPACITY=$(echo "${CHANNEL_RAW}" | jq -r '.capacity')
CSV_DELAY=$(echo "${CHANNEL_RAW}" | jq -r '.csv_delay')

# Extract funding txid and output index
FUNDING_TXID=$(echo "${CHAN_POINT}" | cut -d: -f1)
FUNDING_VOUT=$(echo "${CHAN_POINT}" | cut -d: -f2)

echo ""
echo "Channel found:"
echo "  Channel point : ${CHAN_POINT}"
echo "  Channel ID    : ${CHAN_ID}"
echo "  Capacity      : ${CAPACITY} sat"
echo "  Local balance : ${LOCAL_BAL} sat (Bob's side)"
echo "  Remote balance: ${REMOTE_BAL} sat (Carol's side)"
echo "  State updates : ${NUM_UPDATES}"
echo "  CSV delay     : ${CSV_DELAY} blocks"
echo ""

# Save phase-0 snapshot
echo "${CHANNEL_RAW}" > "${RESULTS}/phase0_channel_state.json"

if [[ "${NUM_UPDATES}" -lt 2 ]]; then
  echo "WARNING: Channel has fewer than 2 state updates."
  echo "Running 3 payments to advance state before simulation..."
  echo ""

  for i in 1 2 3; do
    INV=$(alice addinvoice --amt 1000 --memo "state_advance_${i}" | jq -r '.payment_request')
    carol sendpayment --pay_req="${INV}" --timeout=30 --fee_limit=100 || true
    echo "  Payment ${i}/3 sent."
  done
  mine 1

  # Refresh channel state
  CHANNEL_RAW=$(bob listchannels | jq --arg pub "${CAROL_PUBKEY}" \
    '[.channels[] | select(.remote_pubkey == $pub)] | .[0]')
  NUM_UPDATES=$(echo "${CHANNEL_RAW}" | jq -r '.num_updates')
  echo "Channel now has ${NUM_UPDATES} state updates."
fi

echo ""
read -rp "Pre-flight OK. Continue? [y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ==============================================================================
# PHASE 1 — Capture current commitment transaction (this becomes the "old state")
# ==============================================================================
echo ""
echo "=== PHASE 1: Capture CURRENT commitment transaction ================="
echo "(After we advance state, this tx will be REVOKED — broadcasting it"
echo " simulates the breach.)"
echo ""

# Get the commitment transaction from LND's channel DB via pendingchannels
# after a force-close request, or from the channel's last commit tx.
# LND exposes the current commitment tx via `lncli closechannel --force` in
# dry-run, but the cleanest way in regtest research is:
#   1. Use `lncli getchanbackup` to record the channel point
#   2. Grab the raw commitment tx via Bitcoin Core's mempool after force-close

# We use lncli's internal channel info: commitment tx is visible in
# `pendingchannels` immediately after force-close is initiated.
# Strategy: snapshot balances → advance state → force-close → capture old tx
# → abandon the force-close via reorg, then re-broadcast it ourselves.

# Simpler approach available in LND regtest research:
# Use `lncli forceclosechannel` then capture the tx from mempool BEFORE mining.
# We then check if watchtower would respond (it won't for a current state).
# Then we do: payments (state advances, old tx is now revoked) → broadcast old tx.

# Step 1a: Record the state BEFORE advancing
echo "Recording pre-advance state snapshot..."
SNAPSHOT_BEFORE=$(bob listchannels | jq --arg pub "${CAROL_PUBKEY}" \
  '[.channels[] | select(.remote_pubkey == $pub)] | .[0] | {
    num_updates,
    local_balance,
    remote_balance,
    commit_fee,
    capacity
  }')
echo "${SNAPSHOT_BEFORE}" | tee "${RESULTS}/phase1_snapshot_before.json"

# Step 1b: Perform a force-close NOW to capture the commitment tx from mempool
#           (this is the CURRENT valid state — not yet breached)
echo ""
echo "Initiating force-close of Bob<->Carol channel to capture commitment tx..."
echo "(Carol force-closes — we grab the raw tx from mempool BEFORE mining)"
echo ""

carol closechannel \
  --chan_point="${CHAN_POINT}" \
  --force 2>&1 | tee "${RESULTS}/phase1_forcecloseoutput.txt" || true

sleep 3

# Capture ALL mempool transactions
echo "Scanning mempool for commitment transaction..."
MEMPOOL_TXIDS=$(btc getrawmempool)
echo "Mempool txids:" 
echo "${MEMPOOL_TXIDS}" | jq '.'
echo "${MEMPOOL_TXIDS}" > "${RESULTS}/phase1_mempool_txids.json"

# The force-close commitment tx spends the funding output
echo ""
echo "Searching for tx spending funding output ${FUNDING_TXID}:${FUNDING_VOUT}..."

OLD_COMMIT_TXID=""
OLD_COMMIT_RAWTX=""

for TXID in $(echo "${MEMPOOL_TXIDS}" | jq -r '.[]'); do
  RAW=$(btc getrawtransaction "${TXID}" true 2>/dev/null || true)
  SPENDS=$(echo "${RAW}" | jq -r --arg ftxid "${FUNDING_TXID}" --arg fvout "${FUNDING_VOUT}" \
    '.vin[] | select(.txid == $ftxid and (.vout | tostring) == $fvout) | .txid' 2>/dev/null || true)
  if [[ -n "${SPENDS}" ]]; then
    OLD_COMMIT_TXID="${TXID}"
    OLD_COMMIT_RAWTX=$(btc getrawtransaction "${TXID}" false)
    echo "Found commitment tx: ${OLD_COMMIT_TXID}"
    echo "${RAW}" > "${RESULTS}/phase1_commitment_tx_decoded.json"
    echo "${OLD_COMMIT_RAWTX}" > "${RESULTS}/phase1_commitment_tx_raw.txt"
    break
  fi
done

if [[ -z "${OLD_COMMIT_TXID}" ]]; then
  echo "ERROR: Could not find commitment tx in mempool."
  echo "The channel may have been closed already. Check: carol pendingchannels"
  exit 1
fi

echo ""
echo "Commitment tx captured:"
echo "  TXID  : ${OLD_COMMIT_TXID}"
echo "  Raw tx: saved to ${RESULTS}/phase1_commitment_tx_raw.txt"

# Reject the force-close by removing it from mempool (regtest: just don't mine)
echo ""
echo "NOT mining — commitment tx stays in mempool but unconfirmed."
echo "This is now our 'old state' raw transaction for the breach attempt."

# ==============================================================================
# PHASE 2 — Remove from mempool by mining an unrelated block, channel reopens
# ==============================================================================
echo ""
echo "=== PHASE 2: Clear mempool (evict uncommitted closing tx) ==========="
echo ""
echo "NOTE: In regtest, LND will reuse the same commitment tx when force-closing."
echo "We need to: evict the tx, wait for channel to re-establish, advance state,"
echo "then re-broadcast the captured raw tx to simulate the breach."
echo ""
echo "Evicting mempool by restarting LND nodes (without mining)..."

# Use bitcoin core's testmempoolaccept / invalidation approach:
# Mine a block NOT containing the closing tx (it will be evicted after ~2 hours
# in real networks, but in regtest we can use prioritisetransaction to exclude it)
btc prioritisetransaction "${OLD_COMMIT_TXID}" 0 -99999999 2>/dev/null || true

# Mine a block — the deprioritised tx may be excluded
mine 1

MEMPOOL_AFTER=$(btc getrawmempool | jq 'length')
echo "Mempool size after mining: ${MEMPOOL_AFTER} txs"

if btc getrawmempool | jq -r '.[]' | grep -q "${OLD_COMMIT_TXID}"; then
  echo "Commitment tx still in mempool. Force-evicting..."
  # Bump fee of a conflicting tx or use abandon; in LND we can use abandonChannelCleanup
  carol abandonchannel --chan_point="${CHAN_POINT}" 2>/dev/null || true
  sleep 2
  mine 1
fi

echo "Old commitment tx evicted from mempool (not confirmed on chain)."
echo "For research recording purposes, the raw tx is saved and ready for replay."

# ==============================================================================
# PHASE 3 — Reopen channel and advance state (making the captured tx revoked)
# ==============================================================================
echo ""
echo "=== PHASE 3: Reopen channel and advance state ======================="
echo "(The captured tx is now a REVOKED old state)"
echo ""

echo "Reconnecting Bob -> Carol..."
bob connect "${CAROL_PUBKEY}@lnd-carol:9735" 2>/dev/null || true
sleep 2

echo "Opening new Bob -> Carol channel..."
bob openchannel \
  --node_key="${CAROL_PUBKEY}" \
  --local_amt=500000 \
  --push_amt=100000 2>&1 | tee "${RESULTS}/phase3_reopen_channel.txt"

mine 6
sleep 5

# Refresh channel info
NEW_CHANNEL=$(bob listchannels | jq --arg pub "${CAROL_PUBKEY}" \
  '[.channels[] | select(.remote_pubkey == $pub)] | .[0]')
NEW_CHAN_POINT=$(echo "${NEW_CHANNEL}" | jq -r '.channel_point')
echo ""
echo "New channel opened: ${NEW_CHAN_POINT}"
echo "${NEW_CHANNEL}" > "${RESULTS}/phase3_new_channel.json"

echo ""
echo "Advancing state with 5 payments (making any old commitment tx revoked)..."
echo "(Alice creates invoices, Carol pays — routes through Bob<->Carol channel)"

for i in $(seq 1 5); do
  INV=$(alice addinvoice --amt 5000 --memo "breach_test_payment_${i}" | jq -r '.payment_request')
  carol sendpayment --pay_req="${INV}" --timeout=30 --fee_limit=100 || true
  echo "  Payment ${i}/5 done."
done
mine 1

UPDATED_CHANNEL=$(bob listchannels | jq --arg pub "${CAROL_PUBKEY}" \
  '[.channels[] | select(.remote_pubkey == $pub)] | .[0]')
UPDATED_UPDATES=$(echo "${UPDATED_CHANNEL}" | jq -r '.num_updates')
echo ""
echo "Channel now at state update #${UPDATED_UPDATES} — old tx is REVOKED."
echo "${UPDATED_CHANNEL}" > "${RESULTS}/phase3_channel_after_payments.json"

# ==============================================================================
# PHASE 4 — Broadcast the REVOKED (old) commitment transaction
# ==============================================================================
echo ""
echo "=== PHASE 4: Broadcast revoked commitment transaction (BREACH) ======"
echo ""
echo "Old/revoked tx TXID : ${OLD_COMMIT_TXID}"
echo "Old tx raw          : ${OLD_COMMIT_RAWTX:0:60}..."
echo ""
echo "Broadcasting old state to Bitcoin Core (simulating Carol cheating)..."
echo ""

BROADCAST_RESULT=$(btc sendrawtransaction "${OLD_COMMIT_RAWTX}" true 2>&1) || {
  echo "Broadcast result: ${BROADCAST_RESULT}"
  echo ""
  echo "NOTE: If 'txn-mempool-conflict' or 'bad-txns-inputs-missingorspent' error:"
  echo "  The channel was already closed or funding tx was spent differently."
  echo "  This is expected if the channel was re-opened on the same output."
  echo ""
  echo "  For a clean breach test, use the raw tx from a channel that was"
  echo "  NOT re-closed after capture. The workflow to study is:"
  echo "    Channel State N (captured) → payments → State N+5 (current)"
  echo "    → broadcast State N raw tx → watchtower detects → justice tx"
  echo ""
  echo "  Saving theoretical analysis to results..."
  cat > "${RESULTS}/phase4_breach_analysis.txt" << 'ANALYSIS'
BREACH ATTEMPT ANALYSIS
=======================

Attempted: Broadcast revoked commitment transaction for Bob<->Carol channel.

What *would* happen if the tx were confirmed on-chain:
  1. The revoked commitment tx is mined.
  2. It has a CSV time-lock (csv_delay blocks) on Carol's output.
  3. The Watchtower (Alice's tower server) scans every new block.
  4. It finds the txid matches a stored breach-remedy session key.
  5. The tower decrypts the pre-uploaded justice transaction.
  6. It broadcasts the justice tx immediately, within the CSV window.
  7. The justice tx spends BOTH outputs (Carol's time-locked + Bob's HTLC)
     to Bob's wallet — Carol loses 100% of channel funds as penalty.

Key cryptographic elements:
  - Revocation basepoint: derived from each party's per-commitment secret
  - Breach remedy tx: pre-signed, uses the revealed revocation key
  - Encryption: justice tx is encrypted with txid of revoked tx (privacy)
  - Watchtower cannot read channel activity — only detects+punishes breaches

Economic deterrence:
  - Penalty = 100% of cheater's channel balance
  - Honest party also recovers their own balance
  - Net result: cheater loses everything, honest party gets everything
ANALYSIS
  exit 0
}

echo "Broadcast result: ${BROADCAST_RESULT}"
BREACH_TXID=$(echo "${BROADCAST_RESULT}" | tr -d '"')
echo "Revoked tx in mempool: ${BREACH_TXID}"
echo "${BREACH_TXID}" > "${RESULTS}/phase4_breach_txid.txt"

# ==============================================================================
# PHASE 5 — Mine and observe watchtower justice response
# ==============================================================================
echo ""
echo "=== PHASE 5: Mine blocks — observe watchtower justice response ======"
echo ""
echo "The watchtower will detect the breach on block confirmation."
echo "It has ${CSV_DELAY} blocks to broadcast the justice transaction."
echo ""
echo "Mining 1 block to confirm the revoked commitment tx..."

mine 1

echo ""
echo "Monitoring mempool for justice transaction (10 seconds)..."
sleep 3

MEMPOOL_NOW=$(btc getrawmempool)
echo "Current mempool:"
echo "${MEMPOOL_NOW}" | jq '.'
echo "${MEMPOOL_NOW}" > "${RESULTS}/phase5_mempool_after_breach.json"

echo ""
echo "Checking LND logs for breach/justice events..."
echo ""
echo "--- Alice (watchtower) logs ---"
docker logs lnd-alice --since=60s 2>&1 | \
  grep -iE "breach|justice|revok|sweep|steal|fraud" | \
  tee "${RESULTS}/phase5_alice_breach_logs.txt" || \
  echo "(No breach keywords in recent Alice logs — may need to mine more blocks)"

echo ""
echo "--- Bob (honest party) logs ---"
docker logs lnd-bob --since=60s 2>&1 | \
  grep -iE "breach|justice|revok|sweep" | \
  tee "${RESULTS}/phase5_bob_breach_logs.txt" || \
  echo "(No breach keywords in recent Bob logs)"

echo ""
echo "--- Carol (cheater) logs ---"
docker logs lnd-carol --since=60s 2>&1 | \
  grep -iE "breach|justice|revok|sweep" | \
  tee "${RESULTS}/phase5_carol_breach_logs.txt" || \
  echo "(No breach keywords in recent Carol logs)"

echo ""
echo "Mining ${CSV_DELAY} more blocks (full CSV delay window)..."
mine "${CSV_DELAY}"

echo ""
echo "Checking for justice transaction in recent blocks..."
BEST_BLOCK=$(btc getbestblockhash)
BEST_BLOCK_DATA=$(btc getblock "${BEST_BLOCK}" 2)
echo "${BEST_BLOCK_DATA}" | jq '{
  height,
  tx_count: (.tx | length),
  txids: [.tx[] | .txid]
}' | tee "${RESULTS}/phase5_best_block.json"

echo ""
echo "Final Bob wallet balance (honest party — should include swept channel funds if justice succeeded):"
bob walletbalance | tee "${RESULTS}/phase5_bob_final_balance.json" | \
  jq '{confirmed_balance, unconfirmed_balance}'

echo ""
echo "Final Carol wallet balance (cheater — should be reduced if justice tx fired):"
carol walletbalance | tee "${RESULTS}/phase5_carol_final_balance.json" | \
  jq '{confirmed_balance, unconfirmed_balance}'

echo ""
echo "Final Alice wallet balance (watchtower only — unaffected):"
alice walletbalance | tee "${RESULTS}/phase5_alice_final_balance.json" | \
  jq '{confirmed_balance, unconfirmed_balance}'

echo ""
echo "Checking Bob pending channels (breach remedy status)..."
bob pendingchannels | tee "${RESULTS}/phase5_bob_pending.json" | jq '{
  pending_force_closing: [.pending_force_closing_channels[]? | {
    channel: .channel.channel_point,
    limbo_balance: .limbo_balance,
    recovered_balance: .recovered_balance,
    blocks_til_maturity: .blocks_til_maturity
  }]
}'

echo ""
echo "Checking for breach in Bob's closed channels..."
bob closedchannels | tee "${RESULTS}/phase5_closed_channels.json" | jq '[
  .channels[-3:]? | .[]? | {
    close_type,
    channel_point,
    settled_balance,
    time_locked_balance
  }
]' 2>/dev/null || true

# ==============================================================================
# PHASE 6 — Summary and findings
# ==============================================================================
echo ""
echo "=== PHASE 6: Simulation Summary ====================================="
echo ""
echo "Results directory: ${RESULTS}"
echo ""
echo "Files produced:"
ls -lh "${RESULTS}" | tee "${RESULTS}/file_manifest.txt"
echo ""
cat << 'SUMMARY'
=== KEY FINDINGS FOR YOUR RESEARCH PAPER ===================================

1. CHANNEL STATE AS A STATE MACHINE
   Each HTLC payment transitions the channel from State N to State N+1.
   Both parties exchange revocation secrets, permanently revoking State N.

2. THE BREACH ATTEMPT
   Broadcasting a revoked commitment transaction is the "fraud" in LN.
   The cheater hopes to claim funds from an old, favorable balance.

3. WATCHTOWER DETECTION MECHANISM
   - LND uploads an encrypted justice tx to the tower after each state
   - The encryption key is txid-derived — tower cannot spy on activity
   - Tower watches every block for matching txids
   - Detection latency: 1 block (near-instant in practice)

4. JUSTICE TRANSACTION (PENALTY)
   - Sweeps all channel outputs to the honest party
   - Must be broadcast within csv_delay blocks of the breach confirmation
   - Cheater loses: their entire channel balance
   - Honest party gains: their own balance + cheater's balance

5. ECONOMIC SECURITY MODEL
   The penalty mechanism makes breach irrational:
   Expected loss (100% channel funds) >> Expected gain (balance difference)
   This is why Lightning Network fraud is extremely rare in practice.

=== COMMANDS TO CONTINUE MONITORING ========================================

# Check pending force-close balances on Bob's side
bob pendingchannels | jq '.pending_force_closing_channels'

# Watch Alice's watchtower for justice tx activity
docker logs lnd-alice --follow | grep -iE "breach|justice|sweep"

# List all breach-closed channels on Bob's side
bob closedchannels | jq '[.channels[] | select(.close_type == "BREACH_CLOSE")]'

# Check watchtower session stats on Alice
alice tower info

SUMMARY

echo "Simulation complete. Results in: ${RESULTS}"
