#!/bin/bash
set -e

# Drop privileges from root to the lnd user
if [ "$(id -u)" = "0" ]; then
    chown -R lnd:lnd "${LND_DATA:-/home/lnd/.lnd}"
    exec gosu lnd "$0" "$@"
fi

exec "$@"
