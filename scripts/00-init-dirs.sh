#!/usr/bin/env bash
# =============================================================================
# 00-init-dirs.sh — Create data directories for the research stack
# =============================================================================
# Run once before `docker compose -f docker-compose.research.yml up`
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/../.."

echo "Creating research data directories..."

mkdir -p "${ROOT}/research/data/bitcoin"
mkdir -p "${ROOT}/research/data/alice"
mkdir -p "${ROOT}/research/data/bob"
mkdir -p "${ROOT}/research/data/carol"

# LND needs 0700 on its data dir
chmod 700 "${ROOT}/research/data/alice" \
           "${ROOT}/research/data/bob" \
           "${ROOT}/research/data/carol"

echo "Done. Data directories:"
find "${ROOT}/research/data" -maxdepth 1 -mindepth 1 -type d | sort

echo ""
echo "Next: docker compose -f docker-compose.research.yml up -d"
