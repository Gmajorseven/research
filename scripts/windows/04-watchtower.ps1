Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers.ps1"

Write-Host '=== Watchtower Configuration ========================================'
Write-Host ''

Write-Host "--- Alice's Watchtower Server info ----------------------------------"
alice tower info 2> $null
if ($LASTEXITCODE -ne 0) {
    docker exec lnd-alice lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon tower info
}

Write-Host ''
Write-Host "--- Getting Alice's tower URI ---------------------------------------"
$towerUri = (docker exec lnd-alice lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon tower info | jq -r '.uris[0]').Trim()

Write-Host "Tower URI: $towerUri"

if ([string]::IsNullOrWhiteSpace($towerUri) -or $towerUri -eq 'null') {
    Write-Host ''
    Write-Host 'WARNING: Tower URI not available yet.'
    Write-Host "         Make sure Alice's lnd.conf has [Watchtower] watchtower.active=true"
    Write-Host '         and restart Alice: docker compose restart lnd-alice'
    exit 1
}

Write-Host ''
Write-Host '--- Registering Bob as a watchtower client --------------------------'
Write-Host "Bob adding tower $towerUri..."
docker exec lnd-bob lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon wtclient add "$towerUri"

Write-Host ''
Write-Host '--- Registering Carol as a watchtower client ------------------------'
Write-Host "Carol adding tower $towerUri..."
docker exec lnd-carol lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon wtclient add "$towerUri"

Write-Host ''
Write-Host "--- Verify Bob's tower sessions -------------------------------------"
docker exec lnd-bob lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon wtclient towers | jq '[.towers[] | {pubkey, active_session_candidate, num_sessions}]'

Write-Host ''
Write-Host "--- Verify Carol's tower sessions -----------------------------------"
docker exec lnd-carol lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon wtclient towers | jq '[.towers[] | {pubkey, active_session_candidate, num_sessions}]'

Write-Host ''
Write-Host '--- Tower Statistics (Alice) ----------------------------------------'
docker exec lnd-alice lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon tower stats 2> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host '(tower stats not available in this LND version)'
}

@'
=== How Fraud Prevention Works (Justice Transaction Mechanism) =============

1. CHANNEL STATE MACHINE
   Each payment in a channel advances the state: State 0 -> 1 -> 2 -> N
   The parties exchange revocation keys to invalidate old states.

2. COMMITMENT TRANSACTIONS
   Each state has a commitment tx signed by both parties.
   Old states are revoked, and broadcasting them is a protocol violation.

3. BREACH REMEDY (JUSTICE) TRANSACTION
   For every state update, LND pre-computes a justice tx that spends
   all channel funds to the honest party if an old state is broadcast.

4. WATCHTOWER ROLE
   - Bob/Carol encrypt the justice tx and send it to Alice's tower.
   - The encryption key is derived from the txid of the revoked state,
     so the tower cannot spy on channel activity.
   - The tower monitors the blockchain continuously.
   - If a revoked commitment tx appears on-chain, the tower decrypts
     the justice tx and broadcasts it within the CSV delay window.

5. PENALTY
   The cheating party loses all their funds in the channel.
   This economic disincentive is the core fraud prevention mechanism.

=== Key lncli commands for monitoring ======================================

  bob wtclient towers
  bob wtclient sessions <tower_pubkey>

  bob pendingchannels
  alice pendingchannels

  docker logs lnd-alice --follow | grep -i "breach|justice|revok"
  docker logs lnd-bob   --follow | grep -i "breach|justice|revok"
'@ | Write-Host

Write-Host 'Watchtower setup complete.'
Write-Host 'Next: pwsh scripts/windows/05-channel-states.ps1'
