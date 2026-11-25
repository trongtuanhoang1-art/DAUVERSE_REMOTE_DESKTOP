<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 — Safe Windows Rollback & Service Cleanup Script
#>
param(
    [string]$InstallDir = "",
    [string]$BackupDir = ""
)

$ErrorActionPreference = "Stop"
Write-Host "=== DAUVERSE REMOTE DESKTOP — SAFE ROLLBACK ==="

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if (Test-Path "E:\Program Files\DAUVERSE Remote Desktop") {
        $InstallDir = "E:\Program Files\DAUVERSE Remote Desktop"
    } else {
        $InstallDir = "$env:ProgramFiles\DAUVERSE Remote Desktop"
    }
}

if ([string]::IsNullOrWhiteSpace($BackupDir)) {
    $Candidates = @(
        "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release",
        "${InstallDir}.rollback_backup",
        (Join-Path (Split-Path -Parent $InstallDir) "DAUVERSE_ROLLBACK_BACKUP")
    )
    foreach ($c in $Candidates) {
        if (Test-Path $c) {
            $BackupDir = $c
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($BackupDir) -or -not (Test-Path $BackupDir)) {
    throw "Rollback backup directory not found (checked E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release and ${InstallDir}.rollback_backup). Nothing was modified."
}

foreach ($svcName in @("RustDesk", "DauverseRemoteService")) {
    $Svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($Svc -and $Svc.Status -eq "Running") {
        Write-Host "Stopping Windows Service '$svcName'..."
        Stop-Service -Name $svcName -Force
    }
}

Get-Process -Name "DAUVERSE_REMOTE", "rustdesk" -ErrorAction SilentlyContinue | Stop-Process -Force

if (Test-Path $InstallDir) {
    $BrokenHold = "${InstallDir}_rollback_hold_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    Move-Item -Path $InstallDir -Destination $BrokenHold
    Write-Host "Quarantined previous installation at: $BrokenHold"
}

Copy-Item -Path $BackupDir -Destination $InstallDir -Recurse -Force
Write-Host "Restored verified backup from '$BackupDir' into '$InstallDir'."

$MainSvc = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
if ($MainSvc) {
    Start-Service -Name "RustDesk"
    Write-Host "Restarted Windows Service 'RustDesk'."
}
Write-Host "Rollback completed cleanly."
