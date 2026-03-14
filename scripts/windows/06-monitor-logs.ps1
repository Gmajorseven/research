Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '=== Live Log Monitor (Ctrl+C to stop) ==============================='
Write-Host 'Monitoring: bitcoin-research, lnd-alice (tower), lnd-bob, lnd-carol'
Write-Host 'Filtering for: channel, HTLC, watchtower, breach, justice, revok'
Write-Host ''

function Start-LogTail {
    param(
        [string]$Container,
        [string]$Prefix,
        [int]$Tail
    )

    $cmd = "docker logs -f --tail=$Tail $Container 2>&1 | ForEach-Object { '$Prefix' + `$_.ToString() }"
    return Start-Process -FilePath 'pwsh' -ArgumentList '-NoProfile', '-Command', $cmd -NoNewWindow -PassThru
}

$procs = @()
$procs += Start-LogTail -Container 'lnd-alice' -Prefix '[ALICE] ' -Tail 20
$procs += Start-LogTail -Container 'lnd-bob' -Prefix '[BOB]   ' -Tail 20
$procs += Start-LogTail -Container 'lnd-carol' -Prefix '[CAROL] ' -Tail 20
$procs += Start-LogTail -Container 'bitcoin-research' -Prefix '[BTC]   ' -Tail 10

try {
    Wait-Process -Id ($procs.Id)
}
finally {
    foreach ($p in $procs) {
        if (-not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
