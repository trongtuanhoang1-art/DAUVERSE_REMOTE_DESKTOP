<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 -- NSIS Installer/Uninstaller Ownership & Backup Helper (RC2)
.DESCRIPTION
  Invoked from installer\nsis\dauverse_setup.nsi via $PLUGINSDIR during install, upgrade, and uninstall:
    - StopOwnedProcesses: Terminates ONLY processes whose MainModule.FileName resides strictly under $InstallDir\.
    - CreateVerifiedBackup: Copies existing $InstallDir into $InstallDir.rollback_backup (and E:\ backup when
      $HasFixedDriveE == "1") using pure .NET IO/SHA256 APIs and generates UTF-8 (no-BOM) BACKUP_SHA256_MANIFEST.txt.
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
$DiagLog = Join-Path ([System.IO.Path]::GetTempPath()) "dauverse_nsis_helper.log"

function Write-HelperLog {
    param([string]$Msg)
    $ts = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $line = "[$ts] [$Action] $Msg"
    Write-Host $line
    try {
        [System.IO.File]::AppendAllText($DiagLog, "$line`r`n", (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
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

try {
    $FullInstallDir = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\', '/')
    $InstallPrefix = $FullInstallDir + [string][System.IO.Path]::DirectorySeparatorChar
    Write-HelperLog "Starting helper for InstallDir='$FullInstallDir' HasFixedDriveE='$HasFixedDriveE' Is64BitProcess=$([Environment]::Is64BitProcess)"

    if ($Action -eq "StopOwnedProcesses") {
        $StoppedCount = 0
        foreach ($proc in [System.Diagnostics.Process]::GetProcesses()) {
            try {
                if ($proc.Id -eq $PID) { continue }
                $exePath = $null
                try { $exePath = $proc.MainModule.FileName } catch { $exePath = $null }
                if ($exePath -and $exePath.StartsWith($InstallPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Write-HelperLog "Stopping owned process PID $($proc.Id): $exePath"
                    try {
                        $proc.Kill()
                        $null = $proc.WaitForExit(5000)
                        $StoppedCount++
                    } catch {
                        Write-HelperLog "Warning stopping PID $($proc.Id): $($_.Exception.Message)"
                    }
                }
            } finally {
                $proc.Dispose()
            }
        }
        if ($StoppedCount -gt 0) {
            [System.Threading.Thread]::Sleep(400)
        }
        Write-HelperLog "StopOwnedProcesses completed (stopped=$StoppedCount)."
        exit 0
    }

    if ($Action -eq "CreateVerifiedBackup") {
        $MainExe = [System.IO.Path]::Combine($FullInstallDir, "DAUVERSE_REMOTE.exe")
        if (-not [System.IO.File]::Exists($MainExe)) {
            Write-HelperLog "No existing DAUVERSE_REMOTE.exe in '$FullInstallDir'; skipping upgrade backup."
            exit 0
        }

        Clear-ReadOnlyRecursive -RootDir $FullInstallDir

        $Targets = New-Object System.Collections.Generic.List[string]
        $Targets.Add("${FullInstallDir}.rollback_backup")
        if ($HasFixedDriveE -eq "1" -and [System.IO.Directory]::Exists("E:\")) {
            $Targets.Add("E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release")
        }

        $Sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            foreach ($dst in $Targets) {
                $DstFull = [System.IO.Path]::GetFullPath($dst).TrimEnd('\', '/')
                if ([System.IO.Directory]::Exists($DstFull)) {
                    Clear-ReadOnlyRecursive -RootDir $DstFull
                    [System.IO.Directory]::Delete($DstFull, $true)
                }
                $null = [System.IO.Directory]::CreateDirectory($DstFull)

                $RootAttr = [System.IO.File]::GetAttributes($FullInstallDir)
                if (($RootAttr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "BACKUP_ABORT: InstallDir '$FullInstallDir' is a reparse point / junction."
                }
                foreach ($srcDir in [System.IO.Directory]::GetDirectories($FullInstallDir, "*", [System.IO.SearchOption]::AllDirectories)) {
                    $dirAttr = [System.IO.File]::GetAttributes($srcDir)
                    if (($dirAttr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "BACKUP_ABORT: Directory junction / reparse point rejected in existing installation: $srcDir"
                    }
                }

                $SrcFiles = [System.IO.Directory]::GetFiles($FullInstallDir, "*", [System.IO.SearchOption]::AllDirectories)
                [System.Array]::Sort($SrcFiles, [System.StringComparer]::Ordinal)

                $ManifestLines = New-Object System.Collections.Generic.List[string]
                foreach ($srcFile in $SrcFiles) {
                    $fileName = [System.IO.Path]::GetFileName($srcFile)
                    if ($fileName.Equals("BACKUP_SHA256_MANIFEST.txt", [System.StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }
                    $fileAttr = [System.IO.File]::GetAttributes($srcFile)
                    if (($fileAttr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "BACKUP_ABORT: Reparse point / symlink rejected in existing installation: $srcFile"
                    }
                    $relPath = $srcFile.Substring($InstallPrefix.Length)
                    if ($relPath.Contains(":")) {
                        throw "BACKUP_ABORT: Alternate data stream or colon path rejected: $relPath"
                    }
                    $dstFile = [System.IO.Path]::Combine($DstFull, $relPath)
                    $dstParent = [System.IO.Path]::GetDirectoryName($dstFile)
                    if ($dstParent -and (-not [System.IO.Directory]::Exists($dstParent))) {
                        $null = [System.IO.Directory]::CreateDirectory($dstParent)
                    }
                    [System.IO.File]::Copy($srcFile, $dstFile, $true)

                    $fs = [System.IO.File]::OpenRead($dstFile)
                    try {
                        $hashBytes = $Sha256.ComputeHash($fs)
                    } finally {
                        $fs.Dispose()
                    }
                    $hexHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
                    $ManifestLines.Add("$hexHash  $relPath")
                }

                if ($ManifestLines.Count -lt 3) {
                    throw "BACKUP_ABORT: Backup directory '$DstFull' unexpectedly incomplete ($($ManifestLines.Count) files)."
                }
                $ManifestPath = [System.IO.Path]::Combine($DstFull, "BACKUP_SHA256_MANIFEST.txt")
                [System.IO.File]::WriteAllLines($ManifestPath, $ManifestLines, (New-Object System.Text.UTF8Encoding($false)))
                Write-HelperLog "Created verified rollback snapshot at '$DstFull' ($($ManifestLines.Count) SHA-256 entries)."
            }
        } finally {
            $Sha256.Dispose()
        }
        exit 0
    }
} catch {
    Write-HelperLog "FATAL_ERROR: $($_.ToString()) | Stack: $($_.ScriptStackTrace)"
    [Console]::Error.WriteLine($_.ToString())
    exit 1
}
