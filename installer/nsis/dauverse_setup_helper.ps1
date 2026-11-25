<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 — NSIS Installer/Uninstaller Ownership & Backup Helper (RC2)
.DESCRIPTION
  Invoked from installer\nsis\dauverse_setup.nsi via $PLUGINSDIR during install, upgrade, and uninstall:
    - StopOwnedProcesses: Terminates ONLY processes whose ExecutablePath resides strictly under $InstallDir\.
    - CreateVerifiedBackup: Copies existing $InstallDir into $InstallDir.rollback_backup (and E:\ backup when
      $HasFixedDriveE == "1") and generates BACKUP_SHA256_MANIFEST.txt verified by rollback_windows_release.ps1.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("StopOwnedProcesses", "CreateVerifiedBackup")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$InstallDir,

    [string]$HasFixedDriveE = "0"
)

$ErrorActionPreference = "Stop"
$FullInstallDir = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
$InstallPrefix = $FullInstallDir + "\"

if ($Action -eq "StopOwnedProcesses") {
    $Procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($InstallPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    })
    foreach ($p in $Procs) {
        if ($p.ProcessId -ne $PID) {
            Write-Host "Stopping owned process PID $($p.ProcessId): $($p.ExecutablePath)"
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    exit 0
}

if ($Action -eq "CreateVerifiedBackup") {
    if (-not (Test-Path -LiteralPath (Join-Path $FullInstallDir "DAUVERSE_REMOTE.exe"))) {
        Write-Host "No existing DAUVERSE_REMOTE.exe in '$FullInstallDir'; skipping upgrade backup."
        exit 0
    }
    $Targets = @("${FullInstallDir}.rollback_backup")
    if ($HasFixedDriveE -eq "1") {
        $Targets += "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release"
    }
    foreach ($dst in $Targets) {
        $Parent = Split-Path -Parent $dst
        if ($Parent -and (-not (Test-Path -LiteralPath $Parent))) {
            New-Item -ItemType Directory -Force -Path $Parent | Out-Null
        }
        if (Test-Path -LiteralPath $dst) {
            Remove-Item -LiteralPath $dst -Recurse -Force
        }
        Copy-Item -LiteralPath $FullInstallDir -Destination $dst -Recurse -Force
        $DstResolved = (Resolve-Path -LiteralPath $dst).Path.TrimEnd('\')
        $Lines = @()
        Get-ChildItem -LiteralPath $DstResolved -Recurse -File | Sort-Object FullName | ForEach-Object {
            if ($_.Name -ne "BACKUP_SHA256_MANIFEST.txt") {
                $rel = $_.FullName.Substring($DstResolved.Length).TrimStart('\')
                $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                $Lines += "$hash  $rel"
            }
        }
        if ($Lines.Count -lt 3) {
            throw "BACKUP_ABORT: Backup directory '$DstResolved' unexpectedly incomplete ($($Lines.Count) files)."
        }
        Set-Content -LiteralPath (Join-Path $DstResolved "BACKUP_SHA256_MANIFEST.txt") -Value $Lines -Encoding UTF8
        Write-Host "Created verified rollback snapshot at '$DstResolved' ($($Lines.Count) SHA-256 entries)."
    }
    exit 0
}
