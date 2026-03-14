Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers.ps1"

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$results = Join-Path $PSScriptRoot "..\..\results\breach_$timestamp"
New-Item -ItemType Directory -Path $results -Force | Out-Null
$log = Join-Path $results 'breach_simulation.log'

function Log([string]$Message) {
    $line = "$(Get-Date -Format s) $Message"
    $line | Tee-Object -FilePath $log -Append
}

function Save-Json([string]$Path, [string]$Json) {
    $Json | Out-File -FilePath $Path -Encoding utf8
}

Log '======================================================================'
Log 'Lightning Network Channel Breach Simulation'
Log 'Research: Payment Routing and Fraud Prevention'
Log "Timestamp: $timestamp"
Log "Results  : $results"
Log '======================================================================'

Log '=== PHASE 0: Pre-flight checks ======================================'

$aliceInfo = alice getinfo
$bobInfo = bob getinfo
$carolInfo = carol getinfo

$aliceAlias = ($aliceInfo | jq -r '.alias').Trim()
$bobAlias = ($bobInfo | jq -r '.alias').Trim()
$carolAlias = ($carolInfo | jq -r '.alias').Trim()

$alicePub = ($aliceInfo | jq -r '.identity_pubkey').Trim()
$bobPub = ($bobInfo | jq -r '.identity_pubkey').Trim()
$carolPub = ($carolInfo | jq -r '.identity_pubkey').Trim()

Log "Alice: $aliceAlias - $($alicePub.Substring(0, [Math]::Min(20, $alicePub.Length)))... (watchtower)"
Log "Bob  : $bobAlias - $($bobPub.Substring(0, [Math]::Min(20, $bobPub.Length)))... (honest party)"
Log "Carol: $carolAlias - $($carolPub.Substring(0, [Math]::Min(20, $carolPub.Length)))... (cheater)"

Log "Checking Alice's watchtower server..."
alice tower info | Tee-Object -FilePath (Join-Path $results 'phase0_watchtower_info.json')
if ($LASTEXITCODE -ne 0) {
    Log 'WARNING: Watchtower may not be active. Run 04-watchtower.ps1 first.'
}

Log "Checking Bob's watchtower client registration..."
bob wtclient towers | jq '[.towers[] | {pubkey, active_session_candidate, num_sessions}]' | Tee-Object -FilePath (Join-Path $results 'phase0_bob_wtclient.json')
if ($LASTEXITCODE -ne 0) {
    Log 'WARNING: Bob may not be registered as watchtower client.'
}

Log 'Looking for Bob<->Carol channel...'
$channelRaw = bob listchannels | jq --arg pub "$carolPub" '[.channels[] | select(.remote_pubkey == $pub)] | .[0]'
if (($channelRaw.Trim()) -eq 'null' -or [string]::IsNullOrWhiteSpace($channelRaw)) {
    Log 'ERROR: No Bob<->Carol channel found. Run 02-connect-peers.ps1 first.'
    exit 1
}

Save-Json (Join-Path $results 'phase0_channel_state.json') $channelRaw

$chanPoint = ($channelRaw | jq -r '.channel_point').Trim()
$chanId = ($channelRaw | jq -r '.chan_id').Trim()
$numUpdates = [int](($channelRaw | jq -r '.num_updates').Trim())
$localBal = ($channelRaw | jq -r '.local_balance').Trim()
$remoteBal = ($channelRaw | jq -r '.remote_balance').Trim()
$capacity = ($channelRaw | jq -r '.capacity').Trim()
$csvDelay = [int](($channelRaw | jq -r '.csv_delay').Trim())

$parts = $chanPoint -split ':'
$fundingTxid = $parts[0]
$fundingVout = $parts[1]

Log "Channel point : $chanPoint"
Log "Channel ID    : $chanId"
Log "Capacity      : $capacity sat"
Log "Local balance : $localBal sat (Bob side)"
Log "Remote balance: $remoteBal sat (Carol side)"
Log "State updates : $numUpdates"
Log "CSV delay     : $csvDelay blocks"

if ($numUpdates -lt 2) {
    Log 'Channel has fewer than 2 updates; running 3 payments to advance state...'
    foreach ($i in 1..3) {
        $inv = (alice addinvoice --amt 1000 --memo "state_advance_$i" | jq -r '.payment_request').Trim()
        carol sendpayment --pay_req="$inv" --timeout=30 --fee_limit=100 *> $null
        Log "Payment $i/3 sent."
    }
    mine 1
    $channelRaw = bob listchannels | jq --arg pub "$carolPub" '[.channels[] | select(.remote_pubkey == $pub)] | .[0]'
    $numUpdates = [int](($channelRaw | jq -r '.num_updates').Trim())
    Log "Channel now has $numUpdates state updates."
}

$confirm = Read-Host 'Pre-flight OK. Continue? [y/N]'
if ($confirm -notmatch '^[Yy]$') {
    Log 'Aborted by user.'
    exit 0
}

Log '=== PHASE 1: Capture current commitment transaction =================='
$snapshotBefore = bob listchannels | jq --arg pub "$carolPub" '[.channels[] | select(.remote_pubkey == $pub)] | .[0] | {
  num_updates,
  local_balance,
  remote_balance,
  commit_fee,
  capacity
}'
Save-Json (Join-Path $results 'phase1_snapshot_before.json') $snapshotBefore

Log 'Initiating force-close on Carol to capture commitment tx from mempool...'
carol closechannel --chan_point="$chanPoint" --force 2>&1 | Tee-Object -FilePath (Join-Path $results 'phase1_forcecloseoutput.txt')
Start-Sleep -Seconds 3

$mempoolTxids = btc getrawmempool
Save-Json (Join-Path $results 'phase1_mempool_txids.json') $mempoolTxids

$oldCommitTxid = ''
$oldCommitRawTx = ''

foreach ($txid in ($mempoolTxids | jq -r '.[]')) {
    $decoded = btc getrawtransaction "$txid" true 2> $null
    if ($LASTEXITCODE -ne 0) {
        continue
    }

    $spends = $decoded | jq -r --arg ftxid "$fundingTxid" --arg fvout "$fundingVout" '.vin[] | select(.txid == $ftxid and (.vout | tostring) == $fvout) | .txid' 2> $null
    if (-not [string]::IsNullOrWhiteSpace($spends)) {
        $oldCommitTxid = $txid
        $oldCommitRawTx = (btc getrawtransaction "$txid" false).Trim()
        Save-Json (Join-Path $results 'phase1_commitment_tx_decoded.json') $decoded
        $oldCommitRawTx | Out-File -FilePath (Join-Path $results 'phase1_commitment_tx_raw.txt') -Encoding ascii
        break
    }
}

if ([string]::IsNullOrWhiteSpace($oldCommitTxid)) {
    Log 'ERROR: Could not find commitment tx in mempool.'
    exit 1
}

Log "Captured commitment tx: $oldCommitTxid"

Log '=== PHASE 2: Clear mempool =========================================='
btc prioritisetransaction "$oldCommitTxid" 0 -99999999 *> $null
mine 1

$inMempool = (btc getrawmempool | jq -r '.[]' | Select-String -SimpleMatch $oldCommitTxid)
if ($inMempool) {
    Log 'Commitment tx still in mempool. Attempting channel abandon and extra block...'
    carol abandonchannel --chan_point="$chanPoint" *> $null
    Start-Sleep -Seconds 2
    mine 1
}

Log 'Old commitment tx evicted from mempool (or deprioritized).'

Log '=== PHASE 3: Reopen channel and advance state ======================='
bob connect "$carolPub@lnd-carol:9735" *> $null
Start-Sleep -Seconds 2

bob openchannel --node_key="$carolPub" --local_amt=500000 --push_amt=100000 2>&1 | Tee-Object -FilePath (Join-Path $results 'phase3_reopen_channel.txt')
mine 6
Start-Sleep -Seconds 5

$newChannel = bob listchannels | jq --arg pub "$carolPub" '[.channels[] | select(.remote_pubkey == $pub)] | .[0]'
Save-Json (Join-Path $results 'phase3_new_channel.json') $newChannel
$newChanPoint = ($newChannel | jq -r '.channel_point').Trim()
Log "New channel opened: $newChanPoint"

Log 'Advancing state with 5 payments...'
foreach ($i in 1..5) {
    $inv = (alice addinvoice --amt 5000 --memo "breach_test_payment_$i" | jq -r '.payment_request').Trim()
    carol sendpayment --pay_req="$inv" --timeout=30 --fee_limit=100 *> $null
    Log "Payment $i/5 done."
}
mine 1

$updatedChannel = bob listchannels | jq --arg pub "$carolPub" '[.channels[] | select(.remote_pubkey == $pub)] | .[0]'
Save-Json (Join-Path $results 'phase3_channel_after_payments.json') $updatedChannel
$updatedUpdates = ($updatedChannel | jq -r '.num_updates').Trim()
Log "Channel now at state update #$updatedUpdates; old tx considered revoked."

Log '=== PHASE 4: Broadcast revoked commitment transaction ==============='
Log "Old txid: $oldCommitTxid"

$broadcastOutput = ''
$broadcastOk = $true
try {
    $broadcastOutput = btc sendrawtransaction "$oldCommitRawTx" true 2>&1
    if ($LASTEXITCODE -ne 0) {
        $broadcastOk = $false
    }
}
catch {
    $broadcastOutput = $_.Exception.Message
    $broadcastOk = $false
}

if (-not $broadcastOk) {
    Log "Broadcast failed: $broadcastOutput"
@'
BREACH ATTEMPT ANALYSIS
=======================

Attempted: Broadcast revoked commitment transaction for Bob<->Carol channel.

Expected protocol behavior if revoked tx confirms on-chain:
1. Revoked commitment tx is mined.
2. It includes a CSV timelock on the cheater output.
3. Watchtower scans blocks and matches txid to encrypted session data.
4. Watchtower decrypts and broadcasts justice tx within CSV window.
5. Justice tx sweeps both outputs to honest party; cheater loses all channel funds.
'@ | Out-File -FilePath (Join-Path $results 'phase4_breach_analysis.txt') -Encoding ascii
    exit 0
}

$breachTxid = ($broadcastOutput | Out-String).Trim().Trim('"')
$breachTxid | Out-File -FilePath (Join-Path $results 'phase4_breach_txid.txt') -Encoding ascii
Log "Revoked tx in mempool: $breachTxid"

Log '=== PHASE 5: Mine blocks and observe watchtower response ============'
mine 1
Start-Sleep -Seconds 3

$mempoolNow = btc getrawmempool
Save-Json (Join-Path $results 'phase5_mempool_after_breach.json') $mempoolNow

Log 'Collecting breach-related logs from lnd-alice, lnd-bob, lnd-carol...'
docker logs lnd-alice --since=60s 2>&1 | Select-String -Pattern 'breach|justice|revok|sweep|steal|fraud' -CaseSensitive:$false | Tee-Object -FilePath (Join-Path $results 'phase5_alice_breach_logs.txt')
docker logs lnd-bob --since=60s 2>&1 | Select-String -Pattern 'breach|justice|revok|sweep' -CaseSensitive:$false | Tee-Object -FilePath (Join-Path $results 'phase5_bob_breach_logs.txt')
docker logs lnd-carol --since=60s 2>&1 | Select-String -Pattern 'breach|justice|revok|sweep' -CaseSensitive:$false | Tee-Object -FilePath (Join-Path $results 'phase5_carol_breach_logs.txt')

Log "Mining $csvDelay more blocks (CSV delay window)..."
mine $csvDelay

$bestBlock = (btc getbestblockhash).Trim()
$bestBlockData = btc getblock "$bestBlock" 2
$bestBlockData | jq '{
  height,
  tx_count: (.tx | length),
  txids: [.tx[] | .txid]
}' | Tee-Object -FilePath (Join-Path $results 'phase5_best_block.json')

bob walletbalance | Tee-Object -FilePath (Join-Path $results 'phase5_bob_final_balance.json') | jq '{confirmed_balance, unconfirmed_balance}'
carol walletbalance | Tee-Object -FilePath (Join-Path $results 'phase5_carol_final_balance.json') | jq '{confirmed_balance, unconfirmed_balance}'
alice walletbalance | Tee-Object -FilePath (Join-Path $results 'phase5_alice_final_balance.json') | jq '{confirmed_balance, unconfirmed_balance}'

bob pendingchannels | Tee-Object -FilePath (Join-Path $results 'phase5_bob_pending.json') | jq '{
  pending_force_closing: [.pending_force_closing_channels[]? | {
    channel: .channel.channel_point,
    limbo_balance: .limbo_balance,
    recovered_balance: .recovered_balance,
    blocks_til_maturity: .blocks_til_maturity
  }]
}'

bob closedchannels | Tee-Object -FilePath (Join-Path $results 'phase5_closed_channels.json') | jq '[
  .channels[-3:]? | .[]? | {
    close_type,
    channel_point,
    settled_balance,
    time_locked_balance
  }
]' *> $null

Log '=== PHASE 6: Simulation Summary ====================================='
Get-ChildItem $results | Sort-Object Name | Format-Table Name, Length, LastWriteTime -AutoSize | Out-String | Tee-Object -FilePath (Join-Path $results 'file_manifest.txt')

@'
=== KEY FINDINGS FOR YOUR RESEARCH PAPER ===================================

1. Channel state acts as a state machine with revocation at every update.
2. Broadcasting a revoked commitment transaction is the LN breach event.
3. Watchtower detects and responds using encrypted breach remedy data.
4. Justice transaction can sweep all channel funds to the honest party.
5. The penalty model makes cheating economically irrational.
'@ | Tee-Object -FilePath $log -Append

Log "Simulation complete. Results in: $results"
