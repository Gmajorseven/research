Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:Network = 'regtest'
$Script:BtcMinerWallet = 'research-miner'

function Invoke-LndCli {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('alice', 'bob', 'carol')][string]$Node,
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

function btc {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    & docker exec bitcoin-research bitcoin-cli `
        -regtest `
        -rpcuser=bitcoinrpc `
        -rpcpassword=research_password `
        @Args
}

function btc_wallet_ready {
    btc listwallets | jq -e --arg w "$Script:BtcMinerWallet" '.[] == $w' *> $null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    btc listwalletdir | jq -e --arg w "$Script:BtcMinerWallet" '.wallets[]?.name == $w' *> $null
    if ($LASTEXITCODE -eq 0) {
        btc loadwallet "$Script:BtcMinerWallet" *> $null
    }
    else {
        btc createwallet "$Script:BtcMinerWallet" *> $null
    }
}

function mine {
    param([int]$Count = 1)

    btc_wallet_ready
    $addr = (btc getnewaddress).Trim()
    btc generatetoaddress "$Count" "$addr" | Out-Null
    Write-Host "Mined $Count block(s) to $addr"
}

Write-Host "Research helpers loaded."
Write-Host "Commands: alice, bob, carol, btc, mine"
Write-Host "Example: alice getinfo"
Write-Host "         mine 6"
