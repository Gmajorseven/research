Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers.ps1"

$ChannelSize = 500000
$PushAmount = 100000

Write-Host '=== Step 1: Get node pubkeys ========================================'
$alicePubkey = (alice getinfo | jq -r '.identity_pubkey').Trim()
$bobPubkey = (bob getinfo | jq -r '.identity_pubkey').Trim()
$carolPubkey = (carol getinfo | jq -r '.identity_pubkey').Trim()

Write-Host "Alice pubkey: $alicePubkey"
Write-Host "Bob pubkey  : $bobPubkey"
Write-Host "Carol pubkey: $carolPubkey"

Write-Host ''
Write-Host '=== Step 2: Connect peers ==========================================='
Write-Host 'Connecting Alice -> Bob...'
alice connect "$bobPubkey@lnd-bob:9735" 2> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  (already connected)'
}

Write-Host 'Connecting Bob -> Carol...'
bob connect "$carolPubkey@lnd-carol:9735" 2> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  (already connected)'
}

Write-Host ''
Write-Host '=== Step 3: Open channels ==========================================='
Write-Host "Alice -> Bob channel ($ChannelSize sat, push $PushAmount to Bob)..."
alice openchannel --node_key="$bobPubkey" --local_amt="$ChannelSize" --push_amt="$PushAmount"

Write-Host ''
Write-Host "Bob -> Carol channel ($ChannelSize sat, push $PushAmount to Carol)..."
bob openchannel --node_key="$carolPubkey" --local_amt="$ChannelSize" --push_amt="$PushAmount"

Write-Host ''
Write-Host '=== Step 4: Mine 6 blocks to confirm channel funding txs ==========='
mine 6

Write-Host ''
Write-Host '=== Channel status =================================================='
Write-Host '--- Alice channels ---'
alice listchannels | jq '[.channels[] | {remote_pubkey, capacity, local_balance, remote_balance, active}]'

Write-Host ''
Write-Host '--- Bob channels ---'
bob listchannels | jq '[.channels[] | {remote_pubkey, capacity, local_balance, remote_balance, active}]'

Write-Host ''
Write-Host 'Next: pwsh scripts/windows/03-payment-routing.ps1'
