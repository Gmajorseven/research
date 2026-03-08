#!/bin/bash
set -e

# Drop privileges from root to the bitcoin user
if [ "$(id -u)" = "0" ]; then
    chown -R bitcoin:bitcoin "${BITCOIN_DATA:-/home/bitcoin/.bitcoin}" 2>/dev/null || true
    exec gosu bitcoin "$0" "$@"
fi

exec "$@"
