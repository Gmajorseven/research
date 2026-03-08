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

NETWORK="regtest"

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
    -regtest \
    -rpcuser=bitcoinrpc \
    -rpcpassword=research_password \
    "$@"
}

# ---- Mine N blocks ----------------------------------------------------------
mine() {
  local n="${1:-1}"
  local addr
  addr=$(btc getnewaddress)
  btc generatetoaddress "${n}" "${addr}"
  echo "Mined ${n} block(s) to ${addr}"
}

echo "✔ Research helpers loaded."
echo "  Commands: alice, bob, carol, btc, mine"
echo "  Example:  alice getinfo"
echo "            mine 6"
