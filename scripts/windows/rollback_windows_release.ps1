<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 — Verified Transactional Windows Rollback & Ownership-Safe Service Recovery (RC2)
.DESCRIPTION
  Remediates Codex Findings F03 & F11:
    1. Pre-validates backup directory integrity BEFORE mutating $InstallDir:
       - Requires and verifies every SHA-256 entry in BACKUP_SHA256_MANIFEST.txt (fail-closed on missing/corrupt/tampered backup).
       - Verifies valid MZ / PE\0\0 headers on backup DAUVERSE_REMOTE.exe and librustdesk.dll.
    2. Verifies SCM ImagePath ownership before stopping or restarting Windows Services (never touches external RustDesk).
    3. Stops ONLY processes whose ExecutablePath resides under $InstallDir\ (never global Stop-Process by name).
    4. Wraps quarantine + restore + post-restore SHA-256 verification in a transactional try/catch that automatically
       restores the quarantined installation if copy or verification fails.
#>
param(
    [string]$InstallDir = "",
    [string]$BackupDir = "",
    [switch]$KeepQuarantineHold = $false
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Write-Host "=== DAUVERSE REMOTE DESKTOP — VERIFIED TRANSACTIONAL ROLLBACK ==="

function Test-PeBinaryHeader {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "ROLLBACK_VALIDATION_FAILED: Required binary missing in backup: $FilePath"
    }
    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        if ($fs.Length -lt 256) {
            throw "ROLLBACK_VALIDATION_FAILED: Binary too small ($($fs.Length) bytes): $FilePath"
        }
        $br = New-Object System.IO.BinaryReader($fs)
        $mz = $br.ReadUInt16()
        if ($mz -ne 0x5A4D) {
            throw "ROLLBACK_VALIDATION_FAILED: Invalid MZ header on $FilePath"
        }
        $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $br.ReadInt32()
        if ($peOffset -lt 64 -or ($peOffset + 6) -gt $fs.Length) {
            throw "ROLLBACK_VALIDATION_FAILED: Out-of-bounds PE header offset on $FilePath"
        }
        $fs.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peSig = $br.ReadUInt32()
        if ($peSig -ne 0x00004550) {
            throw "ROLLBACK_VALIDATION_FAILED: Invalid PE\0\0 signature on $FilePath"
        }
    } finally {
        $fs.Dispose()
    }
}

function Assert-BackupManifestIntegrity {
    param([Parameter(Mandatory = $true)][string]$DirectoryToVerify)
    $ManifestPath = Join-Path $DirectoryToVerify "BACKUP_SHA256_MANIFEST.txt"
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "ROLLBACK_VALIDATION_FAILED: Missing BACKUP_SHA256_MANIFEST.txt in '$DirectoryToVerify'. Refusing unverified backup."
    }
    $Lines = @(Get-Content -LiteralPath $ManifestPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Lines.Count -lt 3) {
        throw "ROLLBACK_VALIDATION_FAILED: BACKUP_SHA256_MANIFEST.txt in '$DirectoryToVerify' has too few entries ($($Lines.Count))."
    }
    $Seen = @{}
    foreach ($line in $Lines) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s\s(.+)$') {
            throw "ROLLBACK_VALIDATION_FAILED: Malformed manifest line '$line' in '$ManifestPath'."
        }
        $expectedHash = $Matches[1].ToLowerInvariant()
        $relPath = $Matches[2].Trim()
        if ($relPath.Contains("..") -or [System.IO.Path]::IsPathRooted($relPath)) {
            throw "ROLLBACK_VALIDATION_FAILED: Unsafe relative path '$relPath' in '$ManifestPath'."
        }
        $normKey = $relPath.Replace("/", "\").ToLowerInvariant()
        if ($Seen.ContainsKey($normKey)) {
            throw "ROLLBACK_VALIDATION_FAILED: Duplicate manifest entry '$relPath' in '$ManifestPath'."
        }
        $Seen[$normKey] = $true

        $targetFile = Join-Path $DirectoryToVerify $relPath
        $item = Get-Item -LiteralPath $targetFile -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) {
            throw "ROLLBACK_VALIDATION_FAILED: Manifest-listed file missing in '$DirectoryToVerify': $relPath"
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "ROLLBACK_VALIDATION_FAILED: Reparse point / symlink rejected in '$DirectoryToVerify': $relPath"
        }
        $actualHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "ROLLBACK_VALIDATION_FAILED: SHA-256 mismatch for '$relPath' in '$DirectoryToVerify' (expected $expectedHash, got $actualHash)."
        }
    }
    Test-PeBinaryHeader -FilePath (Join-Path $DirectoryToVerify "DAUVERSE_REMOTE.exe")
    Test-PeBinaryHeader -FilePath (Join-Path $DirectoryToVerify "librustdesk.dll")
    return $Lines.Count
}

function Test-ServiceOwnedByDir {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][string]$NormalizedInstallPrefix
    )
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    if (-not (Test-Path -LiteralPath $RegPath)) {
        return $false
    }
    $Props = Get-ItemProperty -LiteralPath $RegPath -ErrorAction SilentlyContinue
    if (-not $Props -or [string]::IsNullOrWhiteSpace($Props.ImagePath)) {
        return $false
    }
    $Img = $Props.ImagePath.Trim()
    if ($Img.StartsWith('"')) {
        $Img = $Img.Substring(1)
    }
    return $Img.StartsWith($NormalizedInstallPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if (Test-Path -LiteralPath "E:\Program Files\DAUVERSE Remote Desktop") {
        $InstallDir = "E:\Program Files\DAUVERSE Remote Desktop"
    } else {
        $InstallDir = "$env:ProgramFiles\DAUVERSE Remote Desktop"
    }
}
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
$InstallPrefix = $InstallDir + "\"

if ([string]::IsNullOrWhiteSpace($BackupDir)) {
    $Candidates = @(
        "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release",
        "${InstallDir}.rollback_backup",
        (Join-Path (Split-Path -Parent $InstallDir) "DAUVERSE_ROLLBACK_BACKUP")
    )
    foreach ($c in $Candidates) {
        if (Test-Path -LiteralPath $c) {
            $BackupDir = $c
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($BackupDir) -or -not (Test-Path -LiteralPath $BackupDir)) {
    throw "Rollback backup directory not found (checked E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release and ${InstallDir}.rollback_backup). Nothing was modified."
}
$BackupDir = (Resolve-Path -LiteralPath $BackupDir).Path

# 1. F11: Pre-validate backup manifest & PE headers BEFORE touching services, processes, or $InstallDir
$VerifiedCount = Assert-BackupManifestIntegrity -DirectoryToVerify $BackupDir
Write-Host "Pre-validated $VerifiedCount SHA-256 entries and PE headers in '$BackupDir'."

# 2. F03: Check service ownership BEFORE stopping — preserve any external RustDesk service untouched
$ServicesToRestart = @()
foreach ($svcName in @("RustDesk", "DauverseRemoteService")) {
    $Svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($Svc) {
        if (Test-ServiceOwnedByDir -ServiceName $svcName -NormalizedInstallPrefix $InstallPrefix) {
            if ($Svc.Status -eq "Running") {
                Write-Host "Stopping owned Windows Service '$svcName'..."
                Stop-Service -Name $svcName -Force
                $ServicesToRestart += $svcName
            }
        } else {
            Write-Host "Preserving external Windows Service '$svcName' untouched (ImagePath outside '$InstallPrefix')."
        }
    }
}

# 3. F03: Stop ONLY processes whose ExecutablePath resides under $InstallPrefix
Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($InstallPrefix, [System.StringComparison]::OrdinalIgnoreCase)
} | ForEach-Object {
    Write-Host "Stopping owned process PID $($_.ProcessId) ($($_.ExecutablePath))..."
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

# 4. F11: Transactional quarantine + copy + post-restore SHA-256 verification with automatic recovery on failure
$BrokenHold = $null
if (Test-Path -LiteralPath $InstallDir) {
    $BrokenHold = "${InstallDir}_rollback_hold_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff")
    Move-Item -LiteralPath $InstallDir -Destination $BrokenHold
    Write-Host "Quarantined previous installation at: $BrokenHold"
}

try {
    Copy-Item -LiteralPath $BackupDir -Destination $InstallDir -Recurse -Force
    $PostCount = Assert-BackupManifestIntegrity -DirectoryToVerify $InstallDir
    Write-Host "Restored and post-verified $PostCount SHA-256 entries in '$InstallDir'."
} catch {
    Write-Warning "Rollback copy/verification failed ($($_.Exception.Message)); restoring quarantined installation from '$BrokenHold'..."
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($BrokenHold -and (Test-Path -LiteralPath $BrokenHold)) {
        Move-Item -LiteralPath $BrokenHold -Destination $InstallDir -Force
    }
    throw
}

if ($BrokenHold -and (-not $KeepQuarantineHold) -and (Test-Path -LiteralPath $BrokenHold)) {
    Remove-Item -LiteralPath $BrokenHold -Recurse -Force -ErrorAction SilentlyContinue
}

# 5. Restart ONLY owned services that were running prior to rollback
foreach ($svcName in $ServicesToRestart) {
    if (Test-ServiceOwnedByDir -ServiceName $svcName -NormalizedInstallPrefix $InstallPrefix) {
        Start-Service -Name $svcName
        Write-Host "Restarted owned Windows Service '$svcName'."
    }
}

Write-Host "Rollback completed cleanly and transactionally."
