Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
    [int]$Amount = 50000
)

. "$PSScriptRoot/helpers.ps1"

Write-Host '=== Payment Routing Simulation ======================================'
Write-Host 'Path  : Alice -> Bob -> Carol'
Write-Host "Amount: $Amount satoshis"
Write-Host ''

Write-Host '--- Pre-payment balances ---'
Write-Host 'Alice channels:'
alice listchannels | jq '[.channels[] | {local_balance, remote_balance}]'
Write-Host 'Bob channels:'
bob listchannels | jq '[.channels[] | {local_balance, remote_balance}]'
Write-Host 'Carol channels:'
carol listchannels | jq '[.channels[] | {local_balance, remote_balance}]'

Write-Host ''
Write-Host '=== Step 1: Carol generates a payment invoice ======================='
$invoice = carol addinvoice --amt "$Amount" --memo "Research payment $Amount sat"
$paymentRequest = ($invoice | jq -r '.payment_request').Trim()
$paymentHash = ($invoice | jq -r '.r_hash').Trim()

Write-Host 'Invoice (BOLT-11):'
Write-Host $paymentRequest
Write-Host ''
Write-Host "Payment hash (hash lock): $paymentHash"

Write-Host ''
Write-Host '=== Step 2: Alice decodes the invoice (inspect the route) ==========='
alice decodepayreq "$paymentRequest" | jq '{
  destination,
  num_satoshis,
  description,
  cltv_expiry,
  payment_hash
}'

Write-Host ''
Write-Host '=== Step 3: Alice finds the route to Carol =========================='
$carolPubkey = (carol getinfo | jq -r '.identity_pubkey').Trim()
alice queryroutes --dest="$carolPubkey" --amt="$Amount" | jq '{
  routes: [.routes[] | {
    total_fees_msat,
    hops: [.hops[] | {
      chan_id,
      pub_key,
      amt_to_forward_msat,
      fee_msat,
      expiry
    }]
  }]
}'

Write-Host ''
Write-Host '=== Step 4: Alice sends the payment ================================='
alice sendpayment --pay_req="$paymentRequest" --timeout=60 --fee_limit=1000

Write-Host ''
Write-Host '--- Post-payment balances ---'
Write-Host "Alice (sent $Amount sat + fees):"
alice listchannels | jq '[.channels[] | {local_balance, remote_balance}]'
Write-Host 'Bob (collected routing fee):'
bob listchannels | jq '[.channels[] | {local_balance, remote_balance}]'
Write-Host "Carol (received $Amount sat):"
carol listchannels | jq '[.channels[] | {local_balance, remote_balance}]'

Write-Host ''
Write-Host "=== Step 5: Verify payment on Carol's side =========================="
carol listpayments 2> $null
if ($LASTEXITCODE -ne 0) {
    carol listinvoices | jq '[.invoices[-3:] | .[] | {settled, value, memo}]'
}

Write-Host ''
Write-Host 'Routing simulation complete.'
Write-Host 'Next: pwsh scripts/windows/04-watchtower.ps1'
