<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 — Safe Windows Rollback & Service Cleanup Script
#>
param(
    [string]$InstallDir = "E:\Program Files\DAUVERSE Remote Desktop",
    [string]$BackupDir = "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release"
)

$ErrorActionPreference = "Stop"
Write-Host "=== DAUVERSE REMOTE DESKTOP — SAFE ROLLBACK ==="

$Svc = Get-Service -Name "DauverseRemoteService" -ErrorAction SilentlyContinue
if ($Svc -and $Svc.Status -eq "Running") {
    Write-Host "Stopping DauverseRemoteService..."
    Stop-Service -Name "DauverseRemoteService" -Force
}

if (-not (Test-Path $BackupDir)) {
    throw "Rollback backup directory not found at '$BackupDir'. Nothing was modified."
}

if (Test-Path $InstallDir) {
    $BrokenHold = "${InstallDir}_rollback_hold_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    Move-Item -Path $InstallDir -Destination $BrokenHold
    Write-Host "Quarantined previous installation at: $BrokenHold"
}

Copy-Item -Path $BackupDir -Destination $InstallDir -Recurse -Force
Write-Host "Restored verified backup into: $InstallDir"

if ($Svc) {
    Start-Service -Name "DauverseRemoteService"
    Write-Host "Restarted DauverseRemoteService."
}
Write-Host "Rollback completed cleanly."
