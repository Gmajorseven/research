# =============================================================================
# 02-connect-peers.ps1 — Connect nodes and open channels
# =============================================================================
# Builds the network topology:
#
#   Alice ──[500k sat]──► Bob ──[500k sat]──► Carol
#
# Alice opens a channel TO Bob (Alice is funder).
# Bob opens a channel TO Carol (Bob is funder).
# Both channels are announced so routing tables are populated.
#
# Usage:
#   pwsh scripts/windows/02-connect-peers.ps1
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers.ps1"

$CHANNEL_SIZE = 500000         # 500k sats per channel
$PUSH_AMOUNT = 100000          # Push 100k sats to the remote side on open
                               # (so both sides have balance for routing)

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
Write-Host "Alice -> Bob channel ($CHANNEL_SIZE sat, push $PUSH_AMOUNT to Bob)..."
alice openchannel --node_key="$bobPubkey" --local_amt="$CHANNEL_SIZE" --push_amt="$PUSH_AMOUNT"

Write-Host ''
Write-Host "Bob -> Carol channel ($CHANNEL_SIZE sat, push $PUSH_AMOUNT to Carol)..."
bob openchannel --node_key="$carolPubkey" --local_amt="$CHANNEL_SIZE" --push_amt="$PUSH_AMOUNT"

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
