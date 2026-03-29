# =============================================================================
# 08-setup-dave-eifel.ps1 — Set up Dave and Eifel nodes (additional LND + ThunderHub)
# =============================================================================
# This script adds Dave and Eifel nodes to the research environment.
# It will:
#   1. Start Dave and Eifel LND containers
#   2. Create/unlock their wallets
#   3. Start their ThunderHub instances
#   4. Verify the new GUI ports respond
#
# Usage:
#   pwsh scripts/windows/08-setup-dave-eifel.ps1
#   pwsh scripts/windows/08-setup-dave-eifel.ps1 -Build
#
# Optional parameters:
#   -WalletPassword <string>   Wallet password (default: research_wallet_password)
#   -SetupTimeout <int>        Timeout in seconds (default: 180)
#   -Build                     Rebuild Docker images
# =============================================================================

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

$NewNodes = @('dave', 'eifel')
$NewGuiPorts = @(3003, 3004)

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
    try {
        $status = & docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $Container 2>$null
        return $status
    } catch {
        return 'missing'
    }
}

function Get-NodeState([string]$Node) {
    try {
        $output = & docker exec "lnd-$Node" lncli `
            --network=regtest `
            --rpcserver=localhost:10009 `
            --tlscertpath=/home/lnd/.lnd/tls.cert `
            state 2>$null
        
        if ($output -match '"state":\s*"([^"]+)"') {
            return $matches[1]
        }
        return ''
    } catch {
        return ''
    }
}

function Test-NodeHasAdminMacaroon([string]$Node) {
    $result = & docker exec "lnd-$Node" test -f "/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon" 2>$null
    return $LASTEXITCODE -eq 0
}

function Wait-ForContainer([string]$Container, [string]$Wanted) {
    $elapsed = 0
    $status = ''

    while ($elapsed -lt $SetupTimeout) {
        $status = Get-ContainerStatus $Container

        if ($Wanted -eq 'healthy' -and $status -eq 'healthy') {
            return
        } elseif ($Wanted -eq 'running' -and ($status -eq 'running' -or $status -eq 'healthy')) {
            return
        }

        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    Die "Container $Container did not become $Wanted (last status: $status)"
}

function Wait-ForHttp([string]$Url) {
    $elapsed = 0

    while ($elapsed -lt $SetupTimeout) {
        try {
            $null = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            return
        } catch {
            # Continue waiting
        }

        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    Die "Timed out waiting for $Url"
}

function Ensure-NodeTlsCerts([string]$Node) {
    $certPath = Join-Path $Root "data\$Node\tls.cert"

    if (-not (Test-Path $certPath)) {
        Warn "TLS cert for $Node not found: $certPath"
        return $false
    }

    # Check if cert contains service name
    $certContent = Get-Content $certPath -Raw
    if ($certContent -notmatch "lnd-$Node") {
        Warn "TLS cert for $Node does not contain service name 'lnd-$Node'"
        return $false
    }

    return $true
}

function Create-NodeWalletPowerShell([string]$Node) {
    Log "Creating wallet for $Node with proper input handling..."
    
    # Create a temporary PowerShell script to handle the interactive wallet creation
    $tempScript = New-TemporaryFile
    @"
param(`$Password, `$Container)
Write-Output `$Password | & docker exec -i `$Container lncli ``
    --network=regtest ``
    --rpcserver=localhost:10009 ``
    --tlscertpath=/home/lnd/.lnd/tls.cert ``
    create ``
    -n lnd-`$Container ``
    --pass `$Password ``
    --existingonly=false | Out-Null
Start-Sleep -Seconds 2
"@ | Set-Content $tempScript
    
    try {
        # Use stdin approach for wallet creation
        $createInput = @"
$WalletPassword
$WalletPassword
n

"@
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo.FileName = 'docker'
        $process.StartInfo.Arguments = "exec -i lnd-$Node lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert create"
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.CreateNoWindow = $true
        
        $process.Start() | Out-Null
        $process.StandardInput.Write($createInput)
        $process.StandardInput.Close()
        $process.WaitForExit()
        
        Start-Sleep -Seconds 5
        
        if (Test-NodeHasAdminMacaroon $Node) {
            Log "Wallet created successfully for $Node"
            return $true
        } else {
            Warn "Wallet creation may have failed for $Node - no macaroon found"
            return $false
        }
    } catch {
        Warn "Error during wallet creation for ${Node}: $_"
        return $false
    } finally {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }
}

function Unlock-NodeWallet([string]$Node) {
    Log "Unlocking wallet for $Node..."
    
    try {
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo.FileName = 'docker'
        $process.StartInfo.Arguments = "exec -i lnd-$Node lncli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/home/lnd/.lnd/tls.cert unlock --stdin"
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.CreateNoWindow = $true
        
        $process.Start() | Out-Null
        $process.StandardInput.WriteLine($WalletPassword)
        $process.StandardInput.Close()
        $process.WaitForExit(10000) | Out-Null
        
        Log "Wallet unlocked for $Node"
        return $true
    } catch {
        Warn "Could not unlock wallet for ${Node}: $_"
        return $false
    }
}

function Ensure-NodeWallet([string]$Node) {
    $nodeState = Get-NodeState $Node
    
    if (Test-NodeHasAdminMacaroon $Node) {
        if ($nodeState -eq 'LOCKED') {
            Unlock-NodeWallet $Node
        } else {
            Log "Wallet for $Node already initialized ($nodeState)"
        }
    } else {
        Create-NodeWalletPowerShell $Node
    }
}

function Wait-ForNodeRpc([string]$Node) {
    $elapsed = 0

    while ($elapsed -lt $SetupTimeout) {
        try {
            $result = & docker exec "lnd-$Node" lncli `
                --network=regtest `
                --rpcserver=localhost:10009 `
                --tlscertpath=/home/lnd/.lnd/tls.cert `
                --macaroonpath=/home/lnd/.lnd/data/chain/bitcoin/regtest/admin.macaroon `
                getinfo 2>$null
            
            if ($result) {
                return
            }
        } catch {
            # Continue waiting
        }

        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    Die "Timed out waiting for lnd-$Node RPC readiness"
}

function Wait-ForThunderHubConnection([string]$Node) {
    $elapsed = 0

    while ($elapsed -lt $SetupTimeout) {
        try {
            $logs = & docker logs "thunderhub-$Node" 2>&1
            if ($logs -match "Connected to") {
                return
            }
        } catch {
            # Continue
        }

        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    Warn "ThunderHub $Node did not report a node connection within timeout"
    try {
        $logs = & docker logs "thunderhub-$Node" 2>&1
        Write-Warning ($logs -split "`n")[-20..-1] -join "`n"
    } catch { }
}

Log "=== Dave & Eifel Extended Node Setup ==================================="

Require-Command docker
Require-Command curl

if ($Build) {
    Log "Building Docker images..."
    Invoke-Compose build --no-cache lnd thunderhub
}

Log ""
Log "Step 1: Start Dave & Eifel LND containers ============================="

Invoke-Compose up -d lnd-dave lnd-eifel | Out-Null

Log ""
Log "Step 2: Wait for LND containers to be healthy ========================"

foreach ($node in $NewNodes) {
    Log "Waiting for lnd-$node to be healthy..."
    Wait-ForContainer "lnd-$node" 'healthy'
}

Log ""
Log "Step 3: Ensure TLS certs contain service names ========================"

foreach ($node in $NewNodes) {
    if (-not (Ensure-NodeTlsCerts $node)) {
        # Simple check - if cert doesn't exist or is wrong, it's likely auto-generated by LND
        Log "TLS cert will be auto-generated by LND for $node"
    }
}

Log ""
Log "Step 4: Initialize/unlock wallets ====================================="

foreach ($node in $NewNodes) {
    Wait-ForContainer "lnd-$node" 'running'
    Ensure-NodeWallet $node
    Wait-ForNodeRpc $node
}

Log ""
Log "Step 5: Start ThunderHub instances ===================================="

Invoke-Compose up -d --force-recreate thunderhub-dave thunderhub-eifel | Out-Null

Log ""
Log "Step 6: Wait for ThunderHub services to be ready ======================"

foreach ($node in $NewNodes) {
    Log "Waiting for thunderhub-$node to be running..."
    Wait-ForContainer "thunderhub-$node" 'running'
}

for ($i = 0; $i -lt $NewGuiPorts.Count; $i++) {
    $port = $NewGuiPorts[$i]
    Log "Waiting for http://localhost:$port"
    Wait-ForHttp "http://localhost:$port"
}

Log ""
Log "Step 7: Verify ThunderHub node connections ============================="

foreach ($node in $NewNodes) {
    Wait-ForThunderHubConnection $node
}

Log ""
Log "▶▶▶ SUCCESS ▶▶▶ Dave and Eifel nodes are ready! ======================================================"
Log ""

for ($i = 0; $i -lt $NewNodes.Count; $i++) {
    $node = $NewNodes[$i]
    $port = $NewGuiPorts[$i]
    $lndUname = $node.ToUpper()
    Write-Host "$lndUname ThunderHub:  http://localhost:$port"
}

Log ""
Log "You can now use the nodes in scripts:"
Log '  . scripts/helpers.ps1'
Log '  dave getinfo'
Log '  eifel getinfo'
Log ""
Log "To fund the new nodes, run:"
Log "  pwsh scripts/windows/09-fund-dave-eifel.ps1"
Log ""
Log "To connect them to the network, run:"
Log "  pwsh scripts/windows/10-connect-dave-eifel.ps1"
Log ""
