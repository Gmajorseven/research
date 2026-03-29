#!/usr/bin/env bash
# =============================================================================
# 08-cleanup-data.sh — Clean up data directories for all nodes
# =============================================================================
# This script removes the blockchain data, LND data, and other runtime state
# for all nodes (alice, bob, carol, dave, eifel), allowing for a fresh start.
#
# WARNING: This will delete all channel data, macaroons, blockchain state,
# and logs for ALL nodes (alice, bob, carol, dave, eifel).
# Ensure you have backups if needed.
#
# Usage:
#   bash scripts/08-cleanup-data.sh
#   bash scripts/08-cleanup-data.sh --keep-logs    # Keep logs but remove other data
#   bash scripts/08-cleanup-data.sh --dry-run      # Show what would be deleted
#   bash scripts/08-cleanup-data.sh --force        # Use sudo to force permissions and cleanup
#
# =============================================================================
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"

NODES=("alice" "bob" "carol" "dave" "eifel")
KEEP_LOGS=false
DRY_RUN=false
FORCE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---- Helper functions (permissions) -----------------------------------------
fix_permissions() {
  local node=$1
  local node_path="${DATA_DIR}/${node}"

  if [[ ! -d "${node_path}" ]]; then
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    echo "  [DRY-RUN] Would fix permissions for: ${node_path}"
  else
    sudo find "${node_path}" -type f -exec chmod 644 {} + 2>/dev/null || true
    sudo find "${node_path}" -type d -exec chmod 755 {} + 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Fixed permissions for ${node}"
  fi
}

fix_bitcoin_permissions() {
  local bitcoin_path="${DATA_DIR}/bitcoin"

  if [[ ! -d "${bitcoin_path}" ]]; then
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    echo "  [DRY-RUN] Would fix permissions for: ${bitcoin_path}"
  else
    sudo find "${bitcoin_path}" -type f -exec chmod 644 {} + 2>/dev/null || true
    sudo find "${bitcoin_path}" -type d -exec chmod 755 {} + 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Fixed permissions for Bitcoin"
  fi
}
while [[ $# -gt 0 ]]; do
  case $1 in
    --keep-logs)
      KEEP_LOGS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --help)
      grep '^#' "$0" | tail -n +2
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---- Helper functions -------------------------------------------------------
cleanup_node() {
  local node=$1
  local node_path="${DATA_DIR}/${node}"

  if [[ ! -d "${node_path}" ]]; then
    echo -e "${YELLOW}⚠ Node directory not found: ${node_path}${NC}"
    return 0
  fi

  echo -e "${YELLOW}Cleaning up ${node}...${NC}"

  # Remove LND data (chain, graph, watchtower)
  local lnd_data_path="${node_path}/data"
  if [[ -d "${lnd_data_path}" ]]; then
    if [[ "${DRY_RUN}" == true ]]; then
      echo "  [DRY-RUN] Would remove: ${lnd_data_path}"
    else
      if [[ "${FORCE}" == true ]]; then
        sudo rm -rf "${lnd_data_path}"
      else
        rm -rf "${lnd_data_path}"
      fi
      echo -e "  ${GREEN}✓${NC} Removed LND data"
    fi
  fi

  # Remove logs if not keeping them
  if [[ "${KEEP_LOGS}" == false ]]; then
    local logs_path="${node_path}/logs"
    if [[ -d "${logs_path}" ]]; then
      if [[ "${DRY_RUN}" == true ]]; then
        echo "  [DRY-RUN] Would remove: ${logs_path}"
      else
        if [[ "${FORCE}" == true ]]; then
          sudo rm -rf "${logs_path}"
        else
          rm -rf "${logs_path}"
        fi
        echo -e "  ${GREEN}✓${NC} Removed logs"
      fi
    fi
  fi

  # Remove letsencrypt (SSL certs)
  local le_path="${node_path}/letsencrypt"
  if [[ -d "${le_path}" ]]; then
    if [[ "${DRY_RUN}" == true ]]; then
      echo "  [DRY-RUN] Would remove: ${le_path}"
    else
      if [[ "${FORCE}" == true ]]; then
        sudo rm -rf "${le_path}"
      else
        rm -rf "${le_path}"
      fi
      echo -e "  ${GREEN}✓${NC} Removed letsencrypt certs"
    fi
  fi
}

cleanup_bitcoin() {
  local bitcoin_path="${DATA_DIR}/bitcoin"

  if [[ ! -d "${bitcoin_path}" ]]; then
    echo -e "${YELLOW}⚠ Bitcoin directory not found: ${bitcoin_path}${NC}"
    return 0
  fi

  echo -e "${YELLOW}Cleaning up Bitcoin...${NC}"

  # Remove regtest blockchain data
  local regtest_path="${bitcoin_path}/regtest"
  if [[ -d "${regtest_path}" ]]; then
    if [[ "${DRY_RUN}" == true ]]; then
      echo "  [DRY-RUN] Would remove: ${regtest_path}"
    else
      if [[ "${FORCE}" == true ]]; then
        sudo rm -rf "${regtest_path}"
      else
        rm -rf "${regtest_path}"
      fi
      echo -e "  ${GREEN}✓${NC} Removed regtest blockchain data"
    fi
  fi
}

# ---- Main -------------------------------------------------------------------
main() {
  echo ""
  echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║ Data Cleanup Script                                        ║${NC}"
  echo -e "${RED}║ This will delete all runtime data for all nodes            ║${NC}"
  echo -e "${RED}║ (alice, bob, carol, dave, eifel)                          ║${NC}"
  echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  if [[ "${DRY_RUN}" == true ]]; then
    echo -e "${YELLOW}DRY-RUN MODE: No files will be deleted${NC}"
    echo ""
  fi

  if [[ "${KEEP_LOGS}" == true ]]; then
    echo "Keeping logs (only removing data and certs)"
    echo ""
  fi

  # Fix permissions if --force is specified
  if [[ "${FORCE}" == true ]]; then
    echo -e "${YELLOW}Fixing permissions for directories...${NC}"
    for node in "${NODES[@]}"; do
      fix_permissions "${node}"
    done
    fix_bitcoin_permissions
    echo ""
  fi

  # Cleanup individual nodes
  for node in "${NODES[@]}"; do
    cleanup_node "${node}"
  done

  # Cleanup Bitcoin directory
  cleanup_bitcoin

  echo ""
  if [[ "${DRY_RUN}" == true ]]; then
    echo -e "${YELLOW}DRY-RUN complete. Run without --dry-run to actually delete.${NC}"
  else
    echo -e "${GREEN}✓ Cleanup complete!${NC}"
    echo "Run '00-setup-gui.sh' to reinitialize everything fresh."
  fi
  echo ""
}

# Run main function
main
