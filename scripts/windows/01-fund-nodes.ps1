Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers.ps1"

btc_wallet_ready

alice walletbalance *> $null
$aliceOk = $LASTEXITCODE -eq 0
bob walletbalance *> $null
$bobOk = $LASTEXITCODE -eq 0
carol walletbalance *> $null
$carolOk = $LASTEXITCODE -eq 0

if (-not ($aliceOk -and $bobOk -and $carolOk)) {
    Write-Host 'ERROR: One or more LND wallets are locked or not initialized.'
    Write-Host 'Run: pwsh scripts/windows/00-setup-gui.ps1'
    Write-Host 'Then retry: pwsh scripts/windows/01-fund-nodes.ps1'
    exit 1
}

Write-Host '=== Step 1: Mine 101 blocks (coinbase maturity) ====================='
$mineAddr = (btc getnewaddress).Trim()
btc generatetoaddress 101 "$mineAddr" | Select-Object -Last 1
Write-Host '101 blocks mined. Bitcoin balance available.'

Write-Host ''
Write-Host '=== Step 2: Get deposit addresses ==================================='
$aliceAddr = (alice newaddress p2wkh | jq -r '.address').Trim()
$bobAddr = (bob newaddress p2wkh | jq -r '.address').Trim()
$carolAddr = (carol newaddress p2wkh | jq -r '.address').Trim()

Write-Host "Alice address : $aliceAddr"
Write-Host "Bob address   : $bobAddr"
Write-Host "Carol address : $carolAddr"

Write-Host ''
Write-Host '=== Step 3: Send 2 BTC to each node ================================='
btc sendtoaddress "$aliceAddr" 2
btc sendtoaddress "$bobAddr" 2
btc sendtoaddress "$carolAddr" 2

Write-Host ''
Write-Host '=== Step 4: Mine 6 more blocks to confirm ==========================='
mine 6

Write-Host ''
Write-Host '=== Balances ========================================================='
Write-Host -NoNewline 'Alice on-chain: '
alice walletbalance | jq '.confirmed_balance'
Write-Host -NoNewline 'Bob on-chain  : '
bob walletbalance | jq '.confirmed_balance'
Write-Host -NoNewline 'Carol on-chain: '
carol walletbalance | jq '.confirmed_balance'

Write-Host ''
Write-Host 'Next: pwsh scripts/windows/02-connect-peers.ps1'
