Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers.ps1"

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outputDir = (Join-Path $PSScriptRoot "..\..\results\$timestamp")
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Write-Host '=== Channel State Inspection ========================================'
Write-Host "Results will be saved to: $outputDir"
Write-Host ''

Write-Host '--- Alice: Channel details ------------------------------------------'
alice listchannels | Tee-Object (Join-Path $outputDir 'alice_channels.json') | jq '[.channels[] | {
  chan_id,
  capacity,
  local_balance,
  remote_balance,
  commit_fee,
  num_updates,
  total_satoshis_sent,
  total_satoshis_received,
  commitment_type,
  csv_delay,
  initiator,
  active
}]'

Write-Host ''
Write-Host '--- Alice: Forwarding history (routing fees earned) -----------------'
alice fwdinghistory --start_time='-1d' | Tee-Object (Join-Path $outputDir 'alice_forwarding.json') | jq '{
  last_offset_index: .last_offset_index,
  num_events: (.forwarding_events | length),
  total_fee_msat: ([.forwarding_events[].fee_msat | tonumber] | add // 0),
  events: [.forwarding_events[-5:] | .[] | {
    timestamp,
    chan_id_in,
    chan_id_out,
    amt_in_msat,
    amt_out_msat,
    fee_msat
  }]
}'

Write-Host ''
Write-Host '--- Bob: Channel details (routing node) -----------------------------'
bob listchannels | Tee-Object (Join-Path $outputDir 'bob_channels.json') | jq '[.channels[] | {
  chan_id,
  capacity,
  local_balance,
  remote_balance,
  num_updates,
  commitment_type,
  csv_delay,
  initiator,
  active
}]'

Write-Host ''
Write-Host '--- Carol: Channel details ------------------------------------------'
carol listchannels | Tee-Object (Join-Path $outputDir 'carol_channels.json') | jq '[.channels[] | {
  chan_id,
  capacity,
  local_balance,
  remote_balance,
  num_updates,
  commitment_type,
  csv_delay,
  active
}]'

Write-Host ''
Write-Host '=== Pending Channels (force-close / breach monitoring) =============='
Write-Host '--- Alice ---'
alice pendingchannels | Tee-Object (Join-Path $outputDir 'alice_pending.json') | jq '{
  waiting_close_channels: (.waiting_close_channels | length),
  pending_force_closing_channels: (.pending_force_closing_channels | length),
  pending_open_channels: (.pending_open_channels | length)
}'

Write-Host '--- Bob ---'
bob pendingchannels | Tee-Object (Join-Path $outputDir 'bob_pending.json') | jq '{
  waiting_close_channels: (.waiting_close_channels | length),
  pending_force_closing_channels: (.pending_force_closing_channels | length)
}'

Write-Host '--- Carol ---'
carol pendingchannels | Tee-Object (Join-Path $outputDir 'carol_pending.json') | jq '{
  waiting_close_channels: (.waiting_close_channels | length),
  pending_force_closing_channels: (.pending_force_closing_channels | length)
}'

Write-Host ''
Write-Host '=== Network Graph snapshot =========================================='
alice describegraph | Tee-Object (Join-Path $outputDir 'network_graph.json') | jq '{
  num_nodes: (.nodes | length),
  num_edges: (.edges | length),
  nodes: [.nodes[] | {pub_key, alias, color}],
  edges: [.edges[] | {
    channel_id,
    node1_pub,
    node2_pub,
    capacity
  }]
}'

Write-Host ''
Write-Host '=== Blockchain state ================================================'
btc getblockchaininfo | Tee-Object (Join-Path $outputDir 'blockchain_info.json') | jq '{
  chain,
  blocks,
  bestblockhash,
  difficulty,
  mempool_size: .size_on_disk
}'

Write-Host ''
Write-Host "=== Results saved to $outputDir =================================="
Get-ChildItem $outputDir | Format-Table Name, Length, LastWriteTime -AutoSize

Write-Host ''
Write-Host 'To run more payments and re-observe state changes:'
Write-Host '  pwsh scripts/windows/03-payment-routing.ps1 -Amount 10000'
Write-Host '  pwsh scripts/windows/05-channel-states.ps1'
