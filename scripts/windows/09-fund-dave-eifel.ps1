# =============================================================================
# 09-fund-dave-eifel.ps1 — Fund Dave and Eifel nodes with on-chain Bitcoin
# =============================================================================
# This script funds the Dave and Eifel nodes with regtest Bitcoin so they
# can open Lightning channels.
#
# Prerequisites:
#   - Both Dave and Eifel LND nodes must be running and initialized
#   - Run: pwsh scripts/windows/08-setup-dave-eifel.ps1
#
# Usage:
#   pwsh scripts/windows/09-fund-dave-eifel.ps1
#
# Optional parameters:
#   -FundAmount <int>    Amount in BTC to send to each node (default: 2)
# =============================================================================

param(
    [int]$FundAmount = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
Set-Location $Root

# Source helpers
. (Join-Path $ScriptDir 'helpers.ps1')

Write-Host ""
Write-Host "=== Dave & Eifel Node Funding Script ============================"
Write-Host ""

# Ensure Bitcoin wallet is ready
btc_wallet_ready

# Check that dave and eifel wallets are initialized
try {
    $null = dave walletbalance 2>$null
} catch {
    Write-Error "Dave wallet not initialized or locked. Run: pwsh scripts/windows/08-setup-dave-eifel.ps1"
    exit 1
}

try {
    $null = eifel walletbalance 2>$null
} catch {
    Write-Error "Eifel wallet not initialized or locked. Run: pwsh scripts/windows/08-setup-dave-eifel.ps1"
    exit 1
}

Write-Host "=== Step 1: Check Bitcoin balance ==============================="
$btcBalance = (btc getbalance | ConvertFrom-Json)
Write-Host "Bitcoin on-chain balance: $btcBalance BTC"

if ($btcBalance -lt 5) {
    Write-Host ""
    Write-Host "WARNING: Low Bitcoin balance (need at least 5 BTC to fund both nodes)"
    Write-Host "Mining additional blocks to generate coins..."
    mine 50
}

Write-Host ""
Write-Host "=== Step 2: Get deposit addresses ==============================="
$daveAddr = (dave newaddress p2wkh | ConvertFrom-Json).address
$eifelAddr = (eifel newaddress p2wkh | ConvertFrom-Json).address

Write-Host "Dave address  : $daveAddr"
Write-Host "Eifel address : $eifelAddr"

Write-Host ""
Write-Host "=== Step 3: Send $FundAmount BTC to each node ===================="
btc sendtoaddress $daveAddr $FundAmount | Out-Null
btc sendtoaddress $eifelAddr $FundAmount | Out-Null
Write-Host "Transactions sent..."

Write-Host ""
Write-Host "=== Step 4: Mine 6 blocks to confirm ============================"
mine 6

Write-Host ""
Write-Host "=== Balances ===================================================="
$daveBalance = (dave walletbalance | ConvertFrom-Json).confirmed_balance
$eifelBalance = (eifel walletbalance | ConvertFrom-Json).confirmed_balance

Write-Host "Dave on-chain  : $daveBalance satoshis"
Write-Host "Eifel on-chain : $eifelBalance satoshis"

Write-Host ""
Write-Host "✓ Dave and Eifel funding complete!"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Connect Dave/Eifel to the network:"
Write-Host "     pwsh scripts/windows/09-connect-dave-eifel.ps1"
Write-Host "     (or open channels manually)"
