#!/usr/bin/env bash
# =============================================================================
# 04-payment-routing.sh — Simulate multi-hop payment routing
# =============================================================================
# Demonstrates HTLC-based payment routing along the path:
#
#   Alice ──[HTLC]──► Bob (routing node) ──[HTLC]──► Carol
#
# Research observations:
#   - Each hop locks funds in an HTLC with a hash lock + time lock
#   - Bob earns a routing fee (set by his channel policy)
#   - Payment succeeds only when Carol reveals the preimage
#   - All state transitions are logged so you can study channel balances
#
# Usage:
#   bash research/scripts/04-payment-routing.sh [amount_sat]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

AMOUNT="${1:-50000}"   # Default: 50,000 satoshis

echo "=== Payment Routing Simulation ======================================"
echo "Path  : Alice -> Bob -> Carol"
echo "Amount: ${AMOUNT} satoshis"
echo ""

echo "--- Pre-payment balances ---"
echo "Alice channels:"
alice listchannels | jq '[.channels[] | {local_balance, remote_balance}]'
echo "Bob channels:"
bob listchannels | jq '[.channels[] | {local_balance, remote_balance}]'
echo "Carol channels:"
carol listchannels | jq '[.channels[] | {local_balance, remote_balance}]'

echo ""
echo "=== Step 1: Carol generates a payment invoice ======================="
INVOICE=$(carol addinvoice --amt "${AMOUNT}" --memo "Research payment ${AMOUNT} sat")
PAYMENT_REQUEST=$(echo "${INVOICE}" | jq -r '.payment_request')
PAYMENT_HASH=$(echo "${INVOICE}" | jq -r '.r_hash')

echo "Invoice (BOLT-11):"
echo "${PAYMENT_REQUEST}"
echo ""
echo "Payment hash (hash lock): ${PAYMENT_HASH}"

echo ""
echo "=== Step 2: Alice decodes the invoice (inspect the route) ==========="
alice decodepayreq "${PAYMENT_REQUEST}" | jq '{
  destination,
  num_satoshis,
  description,
  cltv_expiry,
  payment_hash
}'

echo ""
echo "=== Step 3: Alice finds the route to Carol =========================="
CAROL_PUBKEY=$(carol getinfo | jq -r '.identity_pubkey')
alice queryroutes \
  --dest="${CAROL_PUBKEY}" \
  --amt="${AMOUNT}" | jq '{
    routes: [.routes[] | {
      total_fees_msat,
      hops: [.hops[] | {
        chan_id,
        pub_key,
        amt_to_forward_msat,
        fee_msat,
        expiry
      }]
    }]
  }'

echo ""
echo "=== Step 4: Alice sends the payment ================================="
alice sendpayment \
  --pay_req="${PAYMENT_REQUEST}" \
  --timeout=60 \
  --fee_limit=1000

echo ""
echo "--- Post-payment balances ---"
echo "Alice (sent ${AMOUNT} sat + fees):"
alice listchannels | jq '[.channels[] | {local_balance, remote_balance}]'
echo "Bob (collected routing fee):"
bob listchannels | jq '[.channels[] | {local_balance, remote_balance}]'
echo "Carol (received ${AMOUNT} sat):"
carol listchannels | jq '[.channels[] | {local_balance, remote_balance}]'

echo ""
echo "=== Step 5: Verify payment on Carol's side =========================="
carol listpayments 2>/dev/null || carol listinvoices | jq '[.invoices[-3:] | .[] | {settled, value, memo}]'

echo ""
echo "Routing simulation complete."
echo "Next: bash research/scripts/05-watchtower.sh"
