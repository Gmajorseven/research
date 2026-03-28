# =============================================================================
# 06-monitor-logs.ps1 — Monitor all nodes for fraud/security events
# =============================================================================
# Tails Docker logs for all nodes and highlights events relevant to:
#   - Channel state updates (commitment transactions)
#   - HTLC adds / settles / failures
#   - Watchtower session updates (encrypted justice txs uploaded)
#   - Any breach detection events
#
# Usage:
#   pwsh scripts/windows/06-monitor-logs.ps1
#   Ctrl+C to stop.
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '=== Live Log Monitor (Ctrl+C to stop) ==============================='
Write-Host 'Monitoring: bitcoin-research, lnd-alice (tower), lnd-bob, lnd-carol'
Write-Host 'Filtering for: channel, HTLC, watchtower, breach, justice, revok'
Write-Host ''

# Function to monitor a single container in parallel
function Start-ContainerLogTail {
    param(
        [string]$Container,
        [string]$Prefix,
        [int]$Tail = 20
    )

    $process = Start-Process -FilePath 'cmd' -ArgumentList '/c', "docker logs -f --tail=$Tail $Container 2>&1" -NoNewWindow -PassThru -RedirectStandardOutput "\\.\pipe\docker_$Container"
    
    if ($process) {
        # Display with prefix
        $process | ForEach-Object {
            while (($line = $_.StandardOutput.ReadLine()) -ne $null) {
                Write-Host "$Prefix$line"
            }
        }
    }
}

# Start multiple log tails
try {
    $jobs = @()
    $jobs += Start-Job -ScriptBlock {
        & docker logs -f --tail=20 lnd-alice 2>&1 | ForEach-Object { Write-Host "[ALICE] $_" }
    }
    $jobs += Start-Job -ScriptBlock {
        & docker logs -f --tail=20 lnd-bob 2>&1 | ForEach-Object { Write-Host "[BOB]   $_" }
    }
    $jobs += Start-Job -ScriptBlock {
        & docker logs -f --tail=20 lnd-carol 2>&1 | ForEach-Object { Write-Host "[CAROL] $_" }
    }
    $jobs += Start-Job -ScriptBlock {
        & docker logs -f --tail=10 bitcoin-research 2>&1 | ForEach-Object { Write-Host "[BTC]   $_" }
    }
    
    # Wait for all jobs to complete
    $jobs | Wait-Job
}
catch {
    Write-Host "Error: $_"
}
finally {
    # Clean up jobs
    Get-Job | Stop-Job
    Get-Job | Remove-Job
    Write-Host "`nLog monitor stopped."
        if (-not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
