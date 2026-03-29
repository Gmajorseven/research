# =============================================================================
# 10-connect-dave-eifel.ps1 — Connect Dave and Eifel to existing network
# =============================================================================
# Extends the existing network topology by adding Dave and Eifel nodes:
#
# EXISTING:    Alice ──[500k sat]──► Bob ──[500k sat]──► Carol
#
# ADDED:       Carol ──[500k sat]──► Alice
#              Dave  ──[500k sat]──► Alice
#              Eifel ──[500k sat]──► Bob
#
# This creates a mesh topology with Alice and Bob as hubs for multi-hop routing.
#
# Prerequisites:
#   - Run: pwsh scripts/windows/01-fund-nodes.ps1       (fund Alice, Bob, Carol)
#   - Run: pwsh scripts/windows/02-connect-peers.ps1    (create initial topology)
#   - Run: pwsh scripts/windows/08-setup-dave-eifel.ps1 (set up Dave and Eifel)
#   - Run: pwsh scripts/windows/09-fund-dave-eifel.ps1  (fund Dave and Eifel)
#
# Usage:
#   pwsh scripts/windows/10-connect-dave-eifel.ps1
#
# Optional parameters:
#   -ChannelSize <int>    Channel capacity in satoshis (default: 500000)
#   -PushAmount <int>     Push amount to remote side (default: 100000)
# =============================================================================

param(
    [int]$ChannelSize = 500000,
    [int]$PushAmount = 100000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
Set-Location $Root

# Source helpers
. (Join-Path $ScriptDir 'helpers.ps1')

Write-Host ""
Write-Host "=== Dave & Eifel Network Connection Script ====================="
Write-Host ""

Write-Host "=== Step 1: Get all node pubkeys ==============================="
$alicePubkey = (alice getinfo | ConvertFrom-Json).identity_pubkey
$bobPubkey = (bob getinfo | ConvertFrom-Json).identity_pubkey
$carolPubkey = (carol getinfo | ConvertFrom-Json).identity_pubkey
$davePubkey = (dave getinfo | ConvertFrom-Json).identity_pubkey
$eifelPubkey = (eifel getinfo | ConvertFrom-Json).identity_pubkey

Write-Host "Alice pubkey: $alicePubkey"
Write-Host "Bob pubkey  : $bobPubkey"
Write-Host "Carol pubkey: $carolPubkey"
Write-Host "Dave pubkey : $davePubkey"
Write-Host "Eifel pubkey: $eifelPubkey"

Write-Host ""
Write-Host "=== Step 2: Connect peers ========================================"

# Carol to Alice
Write-Host "Connecting Carol -> Alice..."
try {
    carol connect "$($alicePubkey)@lnd-alice:9735" 2>$null
} catch {
    Write-Host "  (already connected)"
}

# Dave to Alice
Write-Host "Connecting Dave -> Alice..."
try {
    dave connect "$($alicePubkey)@lnd-alice:9735" 2>$null
} catch {
    Write-Host "  (already connected)"
}

# Eifel to Bob
Write-Host "Connecting Eifel -> Bob..."
try {
    eifel connect "$($bobPubkey)@lnd-bob:9735" 2>$null
} catch {
    Write-Host "  (already connected)"
}

# Alice to Dave
Write-Host "Connecting Alice -> Dave..."
try {
    alice connect "$($davePubkey)@lnd-dave:9735" 2>$null
} catch {
    Write-Host "  (already connected)"
}

# Alice to Carol
Write-Host "Connecting Alice -> Carol..."
try {
    alice connect "$($carolPubkey)@lnd-carol:9735" 2>$null
} catch {
    Write-Host "  (already connected)"
}

# Bob to Eifel
Write-Host "Connecting Bob -> Eifel..."
try {
    bob connect "$($eifelPubkey)@lnd-eifel:9735" 2>$null
} catch {
    Write-Host "  (already connected)"
}

Write-Host ""
Write-Host "=== Step 3: Open new channels ==================================="

Write-Host ""
Write-Host "Carol -> Alice channel ($ChannelSize sat, push $PushAmount satoshis)..."
carol openchannel `
    --node_key="$alicePubkey" `
    --local_amt=$ChannelSize `
    --push_amt=$PushAmount | Out-Null

Write-Host ""
Write-Host "Dave -> Alice channel ($ChannelSize sat, push $PushAmount satoshis)..."
dave openchannel `
    --node_key="$alicePubkey" `
    --local_amt=$ChannelSize `
    --push_amt=$PushAmount | Out-Null

Write-Host ""
Write-Host "Eifel -> Bob channel ($ChannelSize sat, push $PushAmount satoshis)..."
eifel openchannel `
    --node_key="$bobPubkey" `
    --local_amt=$ChannelSize `
    --push_amt=$PushAmount | Out-Null

Write-Host ""
Write-Host "=== Step 4: Mine 6 blocks to confirm channel funding txs ========"
mine 6

Write-Host ""
Write-Host "=== Network Topology =============================================="
Write-Host ""
Write-Host "EXISTING CHANNELS:"
Write-Host "  Alice <---> Bob <---> Carol"
Write-Host ""
Write-Host "NEW CHANNELS:"
Write-Host "  Carol <---> Alice"
Write-Host "  Dave  <---> Alice"
Write-Host "  Eifel <---> Bob"
Write-Host ""
Write-Host "RESULTING MESH:"
Write-Host "        Carol"
Write-Host "       /     \"
Write-Host "  Dave-Alice--Bob-Eifel"
Write-Host ""

Write-Host "=== Channel status ================================================"
Write-Host ""
Write-Host "--- Alice channels ---"
$aliceChannels = alice listchannels | ConvertFrom-Json
foreach ($ch in $aliceChannels.channels) {
    $remotePubkey = $ch.remote_pubkey.Substring(0, 16)
    Write-Host "Channel with $remotePubkey... capacity: $($ch.capacity) sats, local: $($ch.local_balance), remote: $($ch.remote_balance), active: $($ch.active)"
}

Write-Host ""
Write-Host "--- Bob channels ---"
$bobChannels = bob listchannels | ConvertFrom-Json
foreach ($ch in $bobChannels.channels) {
    $remotePubkey = $ch.remote_pubkey.Substring(0, 16)
    Write-Host "Channel with $remotePubkey... capacity: $($ch.capacity) sats, local: $($ch.local_balance), remote: $($ch.remote_balance), active: $($ch.active)"
}

Write-Host ""
Write-Host "--- Carol channels ---"
$carolChannels = carol listchannels | ConvertFrom-Json
foreach ($ch in $carolChannels.channels) {
    $remotePubkey = $ch.remote_pubkey.Substring(0, 16)
    Write-Host "Channel with $remotePubkey... capacity: $($ch.capacity) sats, local: $($ch.local_balance), remote: $($ch.remote_balance), active: $($ch.active)"
}

Write-Host ""
Write-Host "--- Dave channels ---"
$daveChannels = dave listchannels | ConvertFrom-Json
foreach ($ch in $daveChannels.channels) {
    $remotePubkey = $ch.remote_pubkey.Substring(0, 16)
    Write-Host "Channel with $remotePubkey... capacity: $($ch.capacity) sats, local: $($ch.local_balance), remote: $($ch.remote_balance), active: $($ch.active)"
}

Write-Host ""
Write-Host "--- Eifel channels ---"
$eifelChannels = eifel listchannels | ConvertFrom-Json
foreach ($ch in $eifelChannels.channels) {
    $remotePubkey = $ch.remote_pubkey.Substring(0, 16)
    Write-Host "Channel with $remotePubkey... capacity: $($ch.capacity) sats, local: $($ch.local_balance), remote: $($ch.remote_balance), active: $($ch.active)"
}

Write-Host ""
Write-Host "✓ Network topology update complete!"
Write-Host ""
