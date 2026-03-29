# =============================================================================
# helpers.ps1 — lncli shortcut aliases for the research environment
# =============================================================================
# Source this file in your PowerShell session with dot-sourcing:
#   . scripts/windows/helpers.ps1
#
# Then use:
#   alice getinfo
#   bob listchannels
#   carol addinvoice --amt 1000
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:Network = 'regtest'
$Script:BtcMinerWallet = 'research-miner'

# ---- lncli wrappers ---------------------------------------------------------
# Each calls lncli inside the correct container with the right flags.

function Invoke-LndCli {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('alice', 'bob', 'carol', 'dave', 'eifel')][string]$Node,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Args
    )

    & docker exec "lnd-$Node" lncli `
        --network="$Script:Network" `
        --rpcserver=localhost:10009 `
        --tlscertpath=/home/lnd/.lnd/tls.cert `
        --macaroonpath="/home/lnd/.lnd/data/chain/bitcoin/$Script:Network/admin.macaroon" `
        @Args
}

function alice {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    Invoke-LndCli -Node 'alice' -Args $Args
}

function bob {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    Invoke-LndCli -Node 'bob' -Args $Args
}

function carol {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    Invoke-LndCli -Node 'carol' -Args $Args
}

function dave {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    Invoke-LndCli -Node 'dave' -Args $Args
}

function eifel {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    Invoke-LndCli -Node 'eifel' -Args $Args
}

# ---- bitcoin-cli shortcut ---------------------------------------------------

function btc {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & docker exec bitcoin-research bitcoin-cli `
        -regtest `
        -rpcuser=bitcoinrpc `
        -rpcpassword=research_password `
        @Args
}

function btc_wallet_ready {
    # Fast path when our wallet is already loaded.
    btc listwallets 2> $null | jq -e --arg w "$Script:BtcMinerWallet" '.[] == $w' 2> $null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    # If wallet exists on disk, load it; otherwise create it.
    btc listwalletdir 2> $null | jq -e --arg w "$Script:BtcMinerWallet" '.wallets[]?.name == $w' 2> $null
    if ($LASTEXITCODE -eq 0) {
        btc loadwallet "$Script:BtcMinerWallet" 2> $null | Out-Null
    }
    else {
        btc createwallet "$Script:BtcMinerWallet" 2> $null | Out-Null
    }
}

# ---- Mine N blocks ----------------------------------------------------------

function mine {
    param([int]$Count = 1)

    btc_wallet_ready
    $addr = (btc getnewaddress).Trim()
    btc generatetoaddress "$Count" "$addr" | Out-Null
    Write-Host "✔ Mined $Count block(s) to $addr"
}

Write-Host "✔ Research helpers loaded."
Write-Host "  Commands: alice, bob, carol, dave, eifel, btc, mine"
Write-Host "  Example:  alice getinfo"
Write-Host "            mine 6"
