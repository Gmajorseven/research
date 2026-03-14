param(
    [switch]$Build,
    [string]$WalletPassword = 'research_wallet_password',
    [int]$SetupTimeout = 180,
    [int]$LndUid = 1001
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
Set-Location $Root

$Nodes = @('alice', 'bob', 'carol')
$GuiPorts = @(3000, 3001, 3002)

function Log([string]$Message) {
    Write-Host "`n==> $Message"
}

function Warn([string]$Message) {
    Write-Warning $Message
}

function Die([string]$Message) {
    Write-Error $Message
    exit 1
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Die "Required command not found: $Name"
    }
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & docker compose @Args
}

function Get-ContainerStatus([string]$Container) {
    $status = & docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $Container 2> $null
    if ($LASTEXITCODE -ne 0) {
        return 'missing'
    }

    return ($status | Out-String).Trim()
}

function Wait-ForContainer {
    param(
        [string]$Container,
        [ValidateSet('healthy', 'running')][string]$Wanted
    )

    $elapsed = 0
    while ($elapsed -lt $SetupTimeout) {
        $status = Get-ContainerStatus $Container
        if ($Wanted -eq 'healthy' -and $status -eq 'healthy') {
            return
        }
        if ($Wanted -eq 'running' -and ($status -eq 'running' -or $status -eq 'healthy')) {
            return
        }

        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    Die "Container $Container did not become $Wanted"
}

function Wait-ForHttp([string]$Url) {
    $elapsed = 0
    while ($elapsed -lt $SetupTimeout) {
        try {
            Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec 5 | Out-Null
            return
        }
        catch {
            Start-Sleep -Seconds 2
            $elapsed += 2
        }
    }

    Die "Timed out waiting for $Url"
}

function Get-NodeTlsCert([string]$Node) {
    return (Join-Path $Root "data/$Node/tls.cert")
}

function Get-NodeAdminMacaroonPath {
    return '/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon'
}

function Test-NodeHasAdminMacaroon([string]$Node) {
    & docker exec "lnd-$Node" sh -lc "[ -f $(Get-NodeAdminMacaroonPath) ]" *> $null
    return $LASTEXITCODE -eq 0
}

function Get-NodeState([string]$Node) {
    $raw = & docker exec "lnd-$Node" lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert state 2> $null
    if ($LASTEXITCODE -ne 0) {
        return ''
    }

    $match = [regex]::Match(($raw | Out-String), '"state"\s*:\s*"([^"]+)"')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return ''
}

function Wait-ForNodeRpc([string]$Node) {
    $elapsed = 0
    while ($elapsed -lt $SetupTimeout) {
        & docker exec "lnd-$Node" lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon getinfo *> $null
        if ($LASTEXITCODE -eq 0) {
            return
        }

        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    Die "Timed out waiting for lnd-$Node RPC readiness"
}

function Ensure-TlsCert([string]$Node) {
    $cert = Get-NodeTlsCert $Node
    if ((Test-Path $cert)) {
        $text = & openssl x509 -in $cert -noout -text 2> $null
        if ($LASTEXITCODE -eq 0 -and (($text | Out-String) -match "DNS:lnd-$Node")) {
            return
        }
    }

    Log "Generating TLS cert for $Node with Docker hostname SAN"

    Invoke-Compose stop "thunderhub-$Node" "lnd-$Node" *> $null

    $genScript = @"
apk add --no-cache openssl >/dev/null &&
rm -f /mnt/tls.cert /mnt/tls.key &&
cat > /tmp/openssl.cnf <<'EOF'
[req]
distinguished_name=req_distinguished_name
x509_extensions=v3_req
prompt=no
[req_distinguished_name]
CN=lnd-$Node
[v3_req]
subjectAltName=@alt_names
[alt_names]
DNS.1=localhost
DNS.2=lnd-$Node
IP.1=127.0.0.1
EOF
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout /mnt/tls.key \
  -out /mnt/tls.cert \
  -config /tmp/openssl.cnf \
  -extensions v3_req >/dev/null 2>&1 &&
chown ${LndUid}:${LndUid} /mnt/tls.cert /mnt/tls.key &&
chmod 644 /mnt/tls.cert &&
chmod 600 /mnt/tls.key
"@

    & docker run --rm -v "${Root}/data/${Node}:/mnt" alpine sh -lc $genScript *> $null

    $upArgs = @('up', '-d')
    if ($Build) {
        $upArgs += '--build'
    }
    $upArgs += "lnd-$Node"
    Invoke-Compose @upArgs *> $null
    Wait-ForContainer -Container "lnd-$Node" -Wanted healthy
}

function Create-Wallet([string]$Node) {
    Log "Creating wallet for $Node"
    $stdinData = "$WalletPassword`n$WalletPassword`nn`n`n"
    $stdinData | & docker exec -i "lnd-$Node" lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert create *> $null
    if ($LASTEXITCODE -ne 0) {
        Die "Wallet creation failed for $Node"
    }

    if (-not (Test-NodeHasAdminMacaroon $Node)) {
        Die "admin.macaroon was not created for $Node"
    }
}

function Unlock-Wallet([string]$Node) {
    Log "Unlocking wallet for $Node"
    "$WalletPassword`n" | & docker exec -i "lnd-$Node" lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert unlock --stdin *> $null
    if ($LASTEXITCODE -ne 0) {
        Die "Wallet unlock failed for $Node"
    }
}

function Ensure-WalletReady([string]$Node) {
    $state = Get-NodeState $Node
    if (Test-NodeHasAdminMacaroon $Node) {
        if ($state -eq 'LOCKED') {
            Unlock-Wallet $Node
        }
        else {
            Log "Wallet for $Node already initialized ($state)"
        }
    }
    else {
        Create-Wallet $Node
    }

    Wait-ForNodeRpc $Node
}

function Wait-ForThunderHubConnection([string]$Node) {
    $elapsed = 0
    while ($elapsed -lt $SetupTimeout) {
        $logs = & docker logs "thunderhub-$Node" 2>&1
        if (($logs | Out-String) -match 'Connected to') {
            return $true
        }

        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    Warn "ThunderHub $Node did not report a node connection within timeout"
    & docker logs "thunderhub-$Node" 2>&1 | Select-Object -Last 20
    return $false
}

Require-Command docker
Require-Command openssl
Require-Command jq

Log 'Starting Bitcoin + LND services'
$upArgs = @('up', '-d')
if ($Build) {
    $upArgs += '--build'
}
$upArgs += @('bitcoin-research', 'lnd-alice', 'lnd-bob', 'lnd-carol')
Invoke-Compose @upArgs *> $null

Wait-ForContainer -Container bitcoin-research -Wanted healthy
foreach ($node in $Nodes) {
    Wait-ForContainer -Container "lnd-$node" -Wanted healthy
}

foreach ($node in $Nodes) {
    Ensure-TlsCert $node
}

foreach ($node in $Nodes) {
    Ensure-WalletReady $node
}

Log 'Starting ThunderHub services'
$thubArgs = @('up', '-d', '--force-recreate')
if ($Build) {
    $thubArgs += '--build'
}
$thubArgs += @('thunderhub-alice', 'thunderhub-bob', 'thunderhub-carol')
Invoke-Compose @thubArgs *> $null

foreach ($node in $Nodes) {
    Wait-ForContainer -Container "thunderhub-$node" -Wanted running
}

foreach ($port in $GuiPorts) {
    Wait-ForHttp "http://localhost:$port"
}

$null = Wait-ForThunderHubConnection 'alice'
$null = Wait-ForThunderHubConnection 'bob'
$null = Wait-ForThunderHubConnection 'carol'

@'

Setup complete.

ThunderHub URLs:
  Alice: http://localhost:3000
  Bob  : http://localhost:3001
  Carol: http://localhost:3002

Wallet password:
  research_thub_password

If you changed the password, re-run with:
  pwsh scripts/windows/00-setup-gui.ps1 -WalletPassword your_password
'@ | Write-Host
