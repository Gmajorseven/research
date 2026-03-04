#!/usr/bin/env bash
# =============================================================================
# helpers.sh — lncli shortcut aliases for the research environment
# =============================================================================
# Source this file in your shell session:
#   source research/scripts/helpers.sh
#
# Then use:
#   alice getinfo
#   bob   listchannels
#   carol addinvoice --amt 1000
# =============================================================================

# ---- lncli wrappers ---------------------------------------------------------
# Each calls lncli inside the correct container with the right flags.

NETWORK="testnet4"

alice() {
  docker exec lnd-alice lncli \
    --network="${NETWORK}" \
    --rpcserver=localhost:10009 \
    --tlscertpath=/home/lnd/.lnd/tls.cert \
    --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/${NETWORK}/admin.macaroon \
    "$@"
}

bob() {
  docker exec lnd-bob lncli \
    --network="${NETWORK}" \
    --rpcserver=localhost:10009 \
    --tlscertpath=/home/lnd/.lnd/tls.cert \
    --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/${NETWORK}/admin.macaroon \
    "$@"
}

carol() {
  docker exec lnd-carol lncli \
    --network="${NETWORK}" \
    --rpcserver=localhost:10009 \
    --tlscertpath=/home/lnd/.lnd/tls.cert \
    --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/${NETWORK}/admin.macaroon \
    "$@"
}

# ---- bitcoin-cli shortcut ---------------------------------------------------
btc() {
  docker exec bitcoin-research bitcoin-cli \
    -testnet4 \
    -rpcuser=bitcoinrpc \
    -rpcpassword=research_password \
    "$@"
}

# ---- Mine N blocks ----------------------------------------------------------
# NOTE: generatetoaddress is not available on testnet4 (public network).
# Blocks are mined by the network. Use a testnet4 faucet to fund wallets.
mine() {
  echo "⚠ mine() is not available on testnet4."
  echo "  Use a testnet4 faucet to fund your wallets:"
  echo "  https://mempool.space/testnet4"
}

echo "✔ Research helpers loaded (testnet4)."
echo "  Commands: alice, bob, carol, btc, mine"
echo "  Example:  alice getinfo"
echo "            btc getblockchaininfo"
