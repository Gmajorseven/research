# =============================================================================
# 08-cleanup-data.ps1 — Clean up data directories for alice, bob, and carol
# =============================================================================
# This script removes the blockchain data, LND data, and other runtime state
# for the alice, bob, and carol nodes, allowing for a fresh start.
#
# WARNING: This will delete all channel data, macaroons, blockchain state,
# and logs. Ensure you have backups if needed.
#
# Usage:
#   pwsh scripts/windows/08-cleanup-data.ps1
#   pwsh scripts/windows/08-cleanup-data.ps1 -KeepLogs     # Keep logs but remove other data
#   pwsh scripts/windows/08-cleanup-data.ps1 -DryRun       # Show what would be deleted
#   pwsh scripts/windows/08-cleanup-data.ps1 -Force        # Force permissions and cleanup
#
# =============================================================================

param(
    [switch]$KeepLogs,
    [switch]$DryRun,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$DataDir = Join-Path $ProjectRoot 'data'

$Nodes = @('alice', 'bob', 'carol')

# ---- Helper functions -------------------------------------------------------

function Log([string]$Message) {
    Write-Host "  $Message"
}

function LogWarning([string]$Message) {
    Write-Warning $Message
}

function LogSuccess([string]$Message) {
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function LogError([string]$Message) {
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

function Cleanup-Node([string]$Node) {
    $NodePath = Join-Path $DataDir $Node
    
    if (-not (Test-Path $NodePath)) {
        LogWarning "Node directory not found: $NodePath"
        return
    }
    
    Write-Host "Cleaning up $Node..." -ForegroundColor Yellow
    
    # Remove LND data (chain, graph, watchtower)
    $LndDataPath = Join-Path $NodePath 'data'
    if (Test-Path $LndDataPath) {
        if ($DryRun) {
            Log "[DRY-RUN] Would remove: $LndDataPath"
        }
        else {
            try {
                if ($Force) {
                    & takeown /F "$LndDataPath" /R /D Y 2> $null
                    & icacls "$LndDataPath" /grant:r "$env:USERNAME`:(OI)(CI)F" /T 2> $null
                }
                Remove-Item -Path $LndDataPath -Recurse -Force -ErrorAction SilentlyContinue
                LogSuccess "Removed LND data"
            }
            catch {
                LogError "Failed to remove LND data: $_"
            }
        }
    }
    
    # Remove logs if not keeping them
    if (-not $KeepLogs) {
        $LogsPath = Join-Path $NodePath 'logs'
        if (Test-Path $LogsPath) {
            if ($DryRun) {
                Log "[DRY-RUN] Would remove: $LogsPath"
            }
            else {
                try {
                    if ($Force) {
                        & takeown /F "$LogsPath" /R /D Y 2> $null
                        & icacls "$LogsPath" /grant:r "$env:USERNAME`:(OI)(CI)F" /T 2> $null
                    }
                    Remove-Item -Path $LogsPath -Recurse -Force -ErrorAction SilentlyContinue
                    LogSuccess "Removed logs"
                }
                catch {
                    LogError "Failed to remove logs: $_"
                }
            }
        }
    }
    
    # Remove letsencrypt (SSL certs)
    $LePath = Join-Path $NodePath 'letsencrypt'
    if (Test-Path $LePath) {
        if ($DryRun) {
            Log "[DRY-RUN] Would remove: $LePath"
        }
        else {
            try {
                if ($Force) {
                    & takeown /F "$LePath" /R /D Y 2> $null
                    & icacls "$LePath" /grant:r "$env:USERNAME`:(OI)(CI)F" /T 2> $null
                }
                Remove-Item -Path $LePath -Recurse -Force -ErrorAction SilentlyContinue
                LogSuccess "Removed letsencrypt certs"
            }
            catch {
                LogError "Failed to remove letsencrypt certs: $_"
            }
        }
    }
}

function Cleanup-Bitcoin {
    $BitcoinPath = Join-Path $DataDir 'bitcoin'
    
    if (-not (Test-Path $BitcoinPath)) {
        LogWarning "Bitcoin directory not found: $BitcoinPath"
        return
    }
    
    Write-Host "Cleaning up Bitcoin..." -ForegroundColor Yellow
    
    # Remove regtest blockchain data
    $RegtestPath = Join-Path $BitcoinPath 'regtest'
    if (Test-Path $RegtestPath) {
        if ($DryRun) {
            Log "[DRY-RUN] Would remove: $RegtestPath"
        }
        else {
            try {
                if ($Force) {
                    & takeown /F "$RegtestPath" /R /D Y 2> $null
                    & icacls "$RegtestPath" /grant:r "$env:USERNAME`:(OI)(CI)F" /T 2> $null
                }
                Remove-Item -Path $RegtestPath -Recurse -Force -ErrorAction SilentlyContinue
                LogSuccess "Removed regtest blockchain data"
            }
            catch {
                LogError "Failed to remove regtest data: $_"
            }
        }
    }
}

# ---- Main -------------------------------------------------------------------

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║ Data Cleanup Script                                        ║" -ForegroundColor Red
Write-Host "║ This will delete all runtime data for alice, bob, carol    ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

if ($DryRun) {
    Write-Host "DRY-RUN MODE: No files will be deleted" -ForegroundColor Yellow
    Write-Host ""
}

if ($KeepLogs) {
    Write-Host "Keeping logs (only removing data and certs)"
    Write-Host ""
}

# Require confirmation unless dry-run
if (-not $DryRun) {
    $confirm = Read-Host "Are you sure you want to delete all data? Type 'yes' to continue"
    if ($confirm -ne 'yes') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""

# Clean up nodes
foreach ($node in $Nodes) {
    Cleanup-Node $node
}

# Clean up Bitcoin
Cleanup-Bitcoin

Write-Host ""
if ($DryRun) {
    Write-Host "Cleanup complete (DRY-RUN mode)." -ForegroundColor Green
}
else {
    Write-Host "Cleanup complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next: pwsh scripts/windows/00-setup-gui.ps1" -ForegroundColor Cyan
}

Write-Host ""
