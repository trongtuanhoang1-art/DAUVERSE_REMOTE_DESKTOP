<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 -- Verified Transactional Windows Rollback & Ownership-Safe Service Recovery (RC2)
.DESCRIPTION
  Remediates Codex Findings F03 & F11:
    1. Pre-validates backup directory integrity BEFORE mutating $InstallDir:
       - Requires and verifies every SHA-256 entry in BACKUP_SHA256_MANIFEST.txt (fail-closed on missing/corrupt/tampered backup).
       - Verifies valid MZ / PE\0\0 headers on backup DAUVERSE_REMOTE.exe and librustdesk.dll.
    2. Verifies SCM ImagePath ownership before stopping or restarting Windows Services (never touches external RustDesk).
    3. Stops ONLY processes whose MainModule.FileName resides under $InstallDir\ (never global Stop-Process by name).
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
Write-Host "=== DAUVERSE REMOTE DESKTOP -- VERIFIED TRANSACTIONAL ROLLBACK ==="

function Compute-FileSha256Hex {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::OpenRead($FilePath)
        try {
            $bytes = $sha.ComputeHash($fs)
        } finally {
            $fs.Dispose()
        }
        return [System.BitConverter]::ToString($bytes).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Clear-ReadOnlyRecursive {
    param([string]$RootDir)
    if (-not [System.IO.Directory]::Exists($RootDir)) {
        return
    }
    foreach ($f in [System.IO.Directory]::GetFiles($RootDir, "*", [System.IO.SearchOption]::AllDirectories)) {
        try {
            $attr = [System.IO.File]::GetAttributes($f)
            if (($attr -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                [System.IO.File]::SetAttributes($f, ($attr -band (-bnot [System.IO.FileAttributes]::ReadOnly)))
            }
        } catch {}
    }
}

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
    param(
        [Parameter(Mandatory = $true)][string]$DirectoryToVerify,
        [string]$ManifestPathOverride = ""
    )
    if (-not (Test-Path -LiteralPath $DirectoryToVerify)) {
        throw "ROLLBACK_VALIDATION_FAILED: Directory does not exist: '$DirectoryToVerify'."
    }
    $DirFull = [System.IO.Path]::GetFullPath($DirectoryToVerify).TrimEnd('\', '/')
    $DirItem = Get-Item -LiteralPath $DirFull -Force -ErrorAction Stop
    if (($DirItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "ROLLBACK_VALIDATION_FAILED: Root directory '$DirFull' is a reparse point / junction."
    }
    foreach ($subDir in [System.IO.Directory]::GetDirectories($DirFull, "*", [System.IO.SearchOption]::AllDirectories)) {
        $subItem = Get-Item -LiteralPath $subDir -Force -ErrorAction Stop
        if (($subItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "ROLLBACK_VALIDATION_FAILED: Reparse directory / junction rejected in '$DirFull': $subDir"
        }
    }

    $ManifestPath = if ([string]::IsNullOrWhiteSpace($ManifestPathOverride)) {
        Join-Path $DirFull "BACKUP_SHA256_MANIFEST.txt"
    } else {
        $ManifestPathOverride
    }
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "ROLLBACK_VALIDATION_FAILED: Missing BACKUP_SHA256_MANIFEST.txt at '$ManifestPath'. Refusing unverified backup."
    }
    $ManifestItem = Get-Item -LiteralPath $ManifestPath -Force -ErrorAction Stop
    if (($ManifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "ROLLBACK_VALIDATION_FAILED: Manifest '$ManifestPath' is a reparse point."
    }

    $Lines = @(Get-Content -LiteralPath $ManifestPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Lines.Count -lt 3) {
        throw "ROLLBACK_VALIDATION_FAILED: BACKUP_SHA256_MANIFEST.txt in '$ManifestPath' has too few entries ($($Lines.Count))."
    }
    $Seen = @{}
    foreach ($line in $Lines) {
        $cleanLine = $line.TrimStart([char]0xFEFF)
        if ($cleanLine -notmatch '^([0-9a-fA-F]{64})\s\s(.+)$') {
            throw "ROLLBACK_VALIDATION_FAILED: Malformed manifest line '$cleanLine' in '$ManifestPath'."
        }
        $expectedHash = $Matches[1].ToLowerInvariant()
        $relPath = $Matches[2].TrimEnd("`r", "`n")
        if ($relPath.Contains("..") -or $relPath.Contains(":") -or $relPath.StartsWith("/") -or $relPath.StartsWith("\") -or [System.IO.Path]::IsPathRooted($relPath)) {
            throw "ROLLBACK_VALIDATION_FAILED: Unsafe relative path '$relPath' in '$ManifestPath'."
        }
        $sepSegments = $relPath -split '[\\/]'
        foreach ($seg in $sepSegments) {
            if ([string]::IsNullOrWhiteSpace($seg) -or $seg -eq "." -or $seg -eq ".." -or $seg.EndsWith(".") -or $seg.EndsWith(" ")) {
                throw "ROLLBACK_VALIDATION_FAILED: Invalid path segment '$seg' in '$relPath'."
            }
        }
        $normKey = ($sepSegments -join "\").ToLowerInvariant()
        if ($normKey -eq "backup_sha256_manifest.txt") {
            throw "ROLLBACK_VALIDATION_FAILED: Manifest must not self-list BACKUP_SHA256_MANIFEST.txt."
        }
        if ($Seen.ContainsKey($normKey)) {
            throw "ROLLBACK_VALIDATION_FAILED: Duplicate manifest entry '$relPath' in '$ManifestPath'."
        }
        $Seen[$normKey] = $relPath

        $localRel = ($sepSegments -join [string][System.IO.Path]::DirectorySeparatorChar)
        $targetFile = Join-Path $DirFull $localRel
        $item = Get-Item -LiteralPath $targetFile -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) {
            throw "ROLLBACK_VALIDATION_FAILED: Manifest-listed file missing in '$DirFull': $relPath"
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "ROLLBACK_VALIDATION_FAILED: Reparse point / symlink rejected in '$DirFull': $relPath"
        }
        $actualHash = Compute-FileSha256Hex -FilePath $targetFile
        if ($actualHash -ne $expectedHash) {
            throw "ROLLBACK_VALIDATION_FAILED: SHA-256 mismatch for '$relPath' in '$DirFull' (expected $expectedHash, got $actualHash)."
        }
    }

    $DirPrefixLen = $DirFull.Length + 1
    $DiskFiles = [System.IO.Directory]::GetFiles($DirFull, "*", [System.IO.SearchOption]::AllDirectories)
    $CountedDiskFiles = 0
    foreach ($diskFile in $DiskFiles) {
        $diskItem = Get-Item -LiteralPath $diskFile -Force -ErrorAction Stop
        if (($diskItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "ROLLBACK_VALIDATION_FAILED: Unlisted reparse point / symlink rejected in '$DirFull': $diskFile"
        }
        $diskRel = $diskFile.Substring($DirPrefixLen)
        $diskNorm = $diskRel.Replace("/", "\").ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($ManifestPathOverride) -and $diskNorm -eq "backup_sha256_manifest.txt") {
            continue
        }
        if (-not $Seen.ContainsKey($diskNorm)) {
            throw "ROLLBACK_VALIDATION_FAILED: Unlisted extra file '$diskRel' found in '$DirFull' outside BACKUP_SHA256_MANIFEST.txt."
        }
        $CountedDiskFiles++
    }
    if ($Seen.Count -ne $CountedDiskFiles) {
        throw "ROLLBACK_VALIDATION_FAILED: Manifest entry count ($($Seen.Count)) does not match disk file count ($CountedDiskFiles) in '$DirFull'."
    }

    Test-PeBinaryHeader -FilePath (Join-Path $DirFull "DAUVERSE_REMOTE.exe")
    Test-PeBinaryHeader -FilePath (Join-Path $DirFull "librustdesk.dll")
    return $Lines.Count
}

function Get-VerifiedManifestRelativeFiles {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    $RelList = New-Object System.Collections.Generic.List[string]
    $Lines = @(Get-Content -LiteralPath $ManifestPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($line in $Lines) {
        $cleanLine = $line.TrimStart([char]0xFEFF)
        if ($cleanLine -match '^([0-9a-fA-F]{64})\s\s(.+)$') {
            $segs = ($Matches[2].Trim()) -split '[\\/]'
            $RelList.Add(($segs -join [string][System.IO.Path]::DirectorySeparatorChar))
        }
    }
    return ,$RelList
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
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\', '/')
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
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir).TrimEnd('\', '/')
$BackupManifestFile = Join-Path $BackupDir "BACKUP_SHA256_MANIFEST.txt"

# 1. F11: Pre-validate bidirectional backup manifest closure & PE headers BEFORE touching services, processes, or $InstallDir
$VerifiedCount = Assert-BackupManifestIntegrity -DirectoryToVerify $BackupDir
$ManifestRelativeFiles = Get-VerifiedManifestRelativeFiles -ManifestPath $BackupManifestFile
Write-Host "Pre-validated $VerifiedCount bidirectional SHA-256 entries and PE headers in '$BackupDir'."

# 2. F03: Check service ownership BEFORE stopping -- preserve any external RustDesk service untouched
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

# 3. F03: Stop ONLY processes whose MainModule.FileName resides under $InstallPrefix
$StoppedAny = $false
foreach ($proc in [System.Diagnostics.Process]::GetProcesses()) {
    try {
        if ($proc.Id -eq $PID) { continue }
        $exePath = $null
        try { $exePath = $proc.MainModule.FileName } catch { $exePath = $null }
        if ($exePath -and $exePath.StartsWith($InstallPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "Stopping owned process PID $($proc.Id) ($exePath)..."
            try {
                $proc.Kill()
                $null = $proc.WaitForExit(5000)
                $StoppedAny = $true
            } catch {}
        }
    } finally {
        $proc.Dispose()
    }
}
if ($StoppedAny) {
    [System.Threading.Thread]::Sleep(400)
}

# 4. F11: Transactional quarantine + manifest-only copy + bidirectional post-restore SHA-256 verification
$BrokenHold = $null
if (Test-Path -LiteralPath $InstallDir) {
    Clear-ReadOnlyRecursive -RootDir $InstallDir
    $BrokenHold = "${InstallDir}_rollback_hold_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff")
    Move-Item -LiteralPath $InstallDir -Destination $BrokenHold
    Write-Host "Quarantined previous installation at: $BrokenHold"
}

try {
    $null = [System.IO.Directory]::CreateDirectory($InstallDir)
    foreach ($relItem in $ManifestRelativeFiles) {
        $srcItem = Join-Path $BackupDir $relItem
        $srcMeta = Get-Item -LiteralPath $srcItem -Force -ErrorAction Stop
        if (($srcMeta.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "ROLLBACK_VALIDATION_FAILED: Refusing reparse source file during restore: $srcItem"
        }
        $dstItem = Join-Path $InstallDir $relItem
        $dstParent = [System.IO.Path]::GetDirectoryName($dstItem)
        if ($dstParent -and (-not [System.IO.Directory]::Exists($dstParent))) {
            $null = [System.IO.Directory]::CreateDirectory($dstParent)
        }
        [System.IO.File]::Copy($srcItem, $dstItem, $false)
    }
    $PostCount = Assert-BackupManifestIntegrity -DirectoryToVerify $InstallDir -ManifestPathOverride $BackupManifestFile
    Write-Host "Restored and bidirectionally post-verified $PostCount SHA-256 entries in '$InstallDir'."
} catch {
    Write-Warning "Rollback copy/verification failed ($($_.Exception.Message)); restoring quarantined installation from '$BrokenHold'..."
    if (Test-Path -LiteralPath $InstallDir) {
        Clear-ReadOnlyRecursive -RootDir $InstallDir
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($BrokenHold -and (Test-Path -LiteralPath $BrokenHold)) {
        Move-Item -LiteralPath $BrokenHold -Destination $InstallDir -Force
    }
    throw
}

if ($BrokenHold -and (-not $KeepQuarantineHold) -and (Test-Path -LiteralPath $BrokenHold)) {
    Clear-ReadOnlyRecursive -RootDir $BrokenHold
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
