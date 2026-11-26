<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 -- Fail-Closed Windows RC2 Verification & Packaging Harness
.DESCRIPTION
  Remediates Codex Findings F01-F05, F07-F16 & A02 inside an authorized disposable Windows CI runner/sandbox (-AuthorizedSandbox):
    0. Executes Negative Harness Self-Tests (QA_HARNESS_NEGATIVE_SELFTEST.json) proving missing files, bad digests,
       duplicate manifest entries, early GUI exits (0/1/2), missing build logs, and skipped-test markers all FAIL-CLOSED.
    1. Validates immutable INITIAL_BUILD_SHA256_MANIFEST.txt, real WINDOWS_NATIVE_BUILD.log (never synthesized),
       BUILD_PROVENANCE.json, PE headers, WHQL Authenticode + Test-FileCatalog membership + pinned member hashes on
       usbmmidd_v2, verbatim usbmmidd_v2\License.txt, and zero WDKTestCert / RustDeskIddDriver presence.
    2. Tests Coexistence & Ownership (F03): pre-registers a simulated external RustDesk service & directory outside
       $ExpectedInstallDir, runs SETUP.exe /S, and proves external service + files remain 100% untouched.
    3. Tests Startup & Win32 GUI 5-second survival (asserting exact version 1.5.3, surviving window process, and loaded
       librustdesk.dll + flutter_windows.dll) plus PORTABLE.exe self-extraction & Win32 GUI startup.
    4. Tests 3-Process Native Windows DPAPI + Security Negative Matrix (encrypt->exit->reopen decrypt, settings
       durability, cross-restart replay journal, 10-field HMAC v2 tamper rejection, Step-Up PIN re-auth/rotation/lockout,
       corrupted vault fail-closed, headless truthfulness, dry-run WoL, update signature guard, confined receive SHA-256).
    5. Tests Distinct-Sentinel Upgrade + Negative Tampered-Backup Rejection + Positive Transactional Rollback (F11).
    6. Tests Uninstall.exe /S while external RustDesk service is present (proving external service survives uninstall),
       then cleans up the test fixture and verifies pre/post host service/cert/Run-key diffs are 100% clean.
#>
param(
    [Parameter(Mandatory = $true)][string]$ReleaseDir,
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$LogsDir = "",
    [switch]$AuthorizedSandbox = $false
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (-not $AuthorizedSandbox) {
    throw "SAFETY_ABORT: Pass -AuthorizedSandbox explicitly to run installer/uninstaller tests inside an authorized disposable Windows runner or sandbox."
}

$ReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path
$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path

$SetupExe          = Join-Path $ReleaseDir "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe"
$PortableExe       = Join-Path $ReleaseDir "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe"
$SigningTxt        = Join-Path $ReleaseDir "SIGNING_STATUS.txt"
$InitialManifest   = Join-Path $ReleaseDir "INITIAL_BUILD_SHA256_MANIFEST.txt"
$ManifestTxt       = Join-Path $ReleaseDir "SHA256_MANIFEST.txt"
$BuildLogOut       = Join-Path $ReleaseDir "WINDOWS_NATIVE_BUILD.log"
$BuildProvJson     = Join-Path $ReleaseDir "BUILD_PROVENANCE.json"
$DriverProvJson    = Join-Path $ReleaseDir "DRIVER_PROVENANCE_AND_LICENSE.json"
$SelfTestJsonOut   = Join-Path $ReleaseDir "QA_HARNESS_NEGATIVE_SELFTEST.json"
$ReportJsonOut     = Join-Path $ReleaseDir "WINDOWS_RC_VERIFICATION_REPORT.json"
$ReportMdOut       = Join-Path $ReleaseDir "WINDOWS_RC_VERIFICATION_REPORT.md"
$VerifyLogOut      = Join-Path $ReleaseDir "WINDOWS_RC_VERIFICATION.log"

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "VERIFICATION_FAILED: $Message"
    }
}

function Get-NsisHelperDiagTail {
    $diagFile = Join-Path ([System.IO.Path]::GetTempPath()) "dauverse_nsis_helper.log"
    if (Test-Path -LiteralPath $diagFile) {
        return ((Get-Content -LiteralPath $diagFile -Tail 40) -join " | ")
    }
    return "no_helper_diag_log"
}

function Assert-Throws {
    param([Parameter(Mandatory = $true)][string]$CaseName, [Parameter(Mandatory = $true)][scriptblock]$Block)
    $Threw = $false
    $ErrText = ""
    try {
        & $Block
    } catch {
        $Threw = $true
        $ErrText = $_.Exception.Message
    }
    if (-not $Threw) {
        throw "NEGATIVE_SELFTEST_FAILED [$CaseName]: Expected failure, but block succeeded!"
    }
    return [ordered]@{
        case = $CaseName
        outcome = "PASS_REJECTED_AS_EXPECTED"
        error_observed = $ErrText
    }
}

function New-ReleaseManifestLines {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [ValidateSet("Initial", "Final")][string]$ManifestRole = "Final"
    )
    $BaseFull = [System.IO.Path]::GetFullPath($BaseDirectory).TrimEnd('\', '/')
    $BasePrefix = $BaseFull + [string][System.IO.Path]::DirectorySeparatorChar
    $ExcludedNorms = if ($ManifestRole -eq "Initial") {
        @("sha256_manifest.txt", "initial_build_sha256_manifest.txt")
    } else {
        @("sha256_manifest.txt")
    }
    $OutLines = @()
    $DiskFiles = [System.IO.Directory]::GetFiles($BaseFull, "*", [System.IO.SearchOption]::AllDirectories) | Sort-Object
    foreach ($diskFile in $DiskFiles) {
        $diskRel = $diskFile.Substring($BasePrefix.Length)
        $diskNorm = $diskRel.Replace("/", "\").ToLowerInvariant()
        if ($ExcludedNorms -contains $diskNorm) {
            continue
        }
        $relPosixOrWin = $diskRel.Replace("\", "/")
        if ($relPosixOrWin -notmatch "/") {
            $relOut = $diskRel
        } else {
            $relOut = $relPosixOrWin
        }
        $h = (Get-FileHash -LiteralPath $diskFile -Algorithm SHA256).Hash.ToLowerInvariant()
        $OutLines += "$h  $relOut"
    }
    return $OutLines
}

function Assert-ManifestFileValid {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestFilePath,
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [ValidateSet("Auto", "Initial", "Final")][string]$ManifestRole = "Auto",
        [switch]$VerifyListedEntriesOnly = $false
    )
    Assert-Condition (Test-Path -LiteralPath $ManifestFilePath) "Manifest file missing: $ManifestFilePath"
    Assert-Condition (Test-Path -LiteralPath $BaseDirectory) "Base directory missing: $BaseDirectory"
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $BaseDirectory "TESTS_SKIPPED_NOT_RC_ELIGIBLE.txt"))) "Build marked TESTS_SKIPPED_NOT_RC_ELIGIBLE -- refusing acceptance!"

    $BaseFull = [System.IO.Path]::GetFullPath($BaseDirectory).TrimEnd('\', '/')
    $BaseItem = Get-Item -LiteralPath $BaseFull -Force -ErrorAction Stop
    Assert-Condition ((($BaseItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) "Base directory is a reparse point / junction: $BaseFull"
    foreach ($subDir in [System.IO.Directory]::GetDirectories($BaseFull, "*", [System.IO.SearchOption]::AllDirectories)) {
        $subItem = Get-Item -LiteralPath $subDir -Force -ErrorAction Stop
        Assert-Condition ((($subItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) "Reparse directory / junction rejected in release dir: $subDir"
    }

    $ManifestFull = [System.IO.Path]::GetFullPath($ManifestFilePath)
    $ManifestSelfNorm = ""
    $BasePrefix = $BaseFull + [string][System.IO.Path]::DirectorySeparatorChar
    if ($ManifestFull.StartsWith($BasePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $ManifestSelfNorm = $ManifestFull.Substring($BasePrefix.Length).Replace("/", "\").ToLowerInvariant()
    }
    $EffectiveRole = if ($ManifestRole -ne "Auto") {
        $ManifestRole
    } elseif ($ManifestSelfNorm -eq "initial_build_sha256_manifest.txt") {
        "Initial"
    } else {
        "Final"
    }

    $Lines = @(Get-Content -LiteralPath $ManifestFilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Condition ($Lines.Count -gt 0) "Manifest file is empty: $ManifestFilePath"
    $Seen = @{}
    foreach ($line in $Lines) {
        $cleanLine = $line.TrimStart([char]0xFEFF)
        if ($cleanLine -notmatch '^([0-9a-fA-F]{64})\s\s(.+)$') {
            throw "MANIFEST_INVALID: Malformed line '$cleanLine' in $ManifestFilePath"
        }
        $expHash = $Matches[1].ToLowerInvariant()
        $relPath = $Matches[2].TrimEnd("`r", "`n")
        Assert-Condition ((-not $relPath.Contains("..")) -and (-not $relPath.Contains(":")) -and (-not $relPath.StartsWith("/")) -and (-not $relPath.StartsWith("\")) -and (-not [System.IO.Path]::IsPathRooted($relPath))) "Unsafe path '$relPath' in $ManifestFilePath"
        $segs = $relPath -split '[\\/]'
        foreach ($seg in $segs) {
            Assert-Condition ((-not [string]::IsNullOrWhiteSpace($seg)) -and ($seg -ne ".") -and ($seg -ne "..") -and (-not $seg.EndsWith(".")) -and (-not $seg.EndsWith(" "))) "Invalid segment '$seg' in '$relPath'"
        }
        $norm = ($segs -join "\").ToLowerInvariant()
        if ($EffectiveRole -eq "Initial") {
            Assert-Condition ($norm -ne "initial_build_sha256_manifest.txt" -and $norm -ne "sha256_manifest.txt") "Initial manifest must not self-list manifest files ('$relPath')"
        } elseif (-not [string]::IsNullOrEmpty($ManifestSelfNorm)) {
            Assert-Condition ($norm -ne $ManifestSelfNorm) "Manifest must not self-list '$relPath'"
        }
        Assert-Condition (-not $Seen.ContainsKey($norm)) "Duplicate manifest entry '$relPath' in $ManifestFilePath"
        $Seen[$norm] = $true

        $localRel = ($segs -join [string][System.IO.Path]::DirectorySeparatorChar)
        $full = Join-Path $BaseFull $localRel
        $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        Assert-Condition ($null -ne $item -and (-not $item.PSIsContainer)) "Manifest-listed file missing on disk: $full"
        Assert-Condition ((($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) "Reparse point / symlink rejected in release dir: $full"
        $actHash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Condition ($actHash -eq $expHash) "SHA-256 mismatch for '$relPath' (expected $expHash, got $actHash)"
    }

    if (-not $VerifyListedEntriesOnly) {
        $ExcludedDiskNorms = if ($EffectiveRole -eq "Initial") {
            @("initial_build_sha256_manifest.txt", "sha256_manifest.txt")
        } elseif (-not [string]::IsNullOrEmpty($ManifestSelfNorm)) {
            @($ManifestSelfNorm)
        } else {
            @("sha256_manifest.txt")
        }

        $DiskFiles = [System.IO.Directory]::GetFiles($BaseFull, "*", [System.IO.SearchOption]::AllDirectories)
        $CountedDiskFiles = 0
        foreach ($diskFile in $DiskFiles) {
            $diskItem = Get-Item -LiteralPath $diskFile -Force -ErrorAction Stop
            Assert-Condition ((($diskItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) "Unlisted reparse point / symlink rejected in release dir: $diskFile"
            $diskRel = $diskFile.Substring($BasePrefix.Length)
            $diskNorm = $diskRel.Replace("/", "\").ToLowerInvariant()
            if ($ExcludedDiskNorms -contains $diskNorm) {
                continue
            }
            Assert-Condition ($Seen.ContainsKey($diskNorm)) "Unlisted extra file '$diskRel' present in '$BaseFull' outside '$ManifestFilePath'"
            $CountedDiskFiles++
        }
        if ($EffectiveRole -eq "Final" -and (Test-Path -LiteralPath (Join-Path $BaseFull "INITIAL_BUILD_SHA256_MANIFEST.txt"))) {
            Assert-Condition ($Seen.ContainsKey("initial_build_sha256_manifest.txt")) "Final manifest must include and hash-verify INITIAL_BUILD_SHA256_MANIFEST.txt"
        }
        Assert-Condition ($Seen.Count -eq $CountedDiskFiles) "Manifest entry count ($($Seen.Count)) does not match disk file count ($CountedDiskFiles) in '$BaseFull'"
    }

    return $Lines.Count
}

# Structural sanity validator for WINDOWS_NATIVE_BUILD.log (corroborates stage order & compiler output; independent execution authenticity requires CI provider run logs per FT010-Q01)
function Assert-OriginalBuildLogValid {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    Assert-Condition (Test-Path -LiteralPath $LogPath) "Original WINDOWS_NATIVE_BUILD.log is missing at $LogPath (placeholder substitution is forbidden)."
    $len = (Get-Item -LiteralPath $LogPath).Length
    Assert-Condition ($len -ge 1024) "WINDOWS_NATIVE_BUILD.log is suspiciously small ($len bytes); refusing synthetic/truncated build log."
    $raw = Get-Content -Raw -LiteralPath $LogPath
    Assert-Condition (-not $raw.Contains("TESTS_SKIPPED:")) "WINDOWS_NATIVE_BUILD.log indicates tests were skipped."
    Assert-Condition (-not $raw.Contains("BUILD/TEST STEP FAILED")) "WINDOWS_NATIVE_BUILD.log contains a failed build/test step marker."

    $RequiredOrderedMarkers = @(
        "RepoRoot      :",
        "CargoTarget   :",
        ">>> [flutter pub get]",
        ">>> [Build dylib_virtual_display]",
        "Finished ``release`` profile",
        ">>> [Build librustdesk.dll",
        "Finished ``release`` profile",
        ">>> [flutter build windows --release]",
        ">>> [Generate single-file portable executable]",
        ">>> [Compile NSIS Setup Installer]",
        "Output: """,
        "=== NATIVE COMPILATION & PACKAGING SUCCEEDED ==="
    )
    $prevIdx = -1
    foreach ($marker in $RequiredOrderedMarkers) {
        $searchStart = $prevIdx + 1
        $idx = if ($searchStart -lt $raw.Length) {
            $raw.IndexOf($marker, $searchStart, [System.StringComparison]::Ordinal)
        } else {
            -1
        }
        Assert-Condition ($idx -gt $prevIdx) "WINDOWS_NATIVE_BUILD.log missing or out-of-order compiler/bundler output marker '$marker' (complete-marker synthetic logs without toolchain output are forbidden)."
        $prevIdx = $idx
    }
}

function Assert-GuiWindowSurvived {
    param(
        [Parameter(Mandatory = $true)][bool]$AliveAfter5s,
        [AllowNull()]$ExitCode,
        [Parameter(Mandatory = $true)][string[]]$LoadedModules
    )
    Assert-Condition $AliveAfter5s "GUI process exited prematurely within 5s (ExitCode=$ExitCode). Early exit 0/1/2 is NOT accepted as GUI startup."
    Assert-Condition ($LoadedModules -contains "librustdesk.dll") "Running GUI process did not load native librustdesk.dll (loaded: $($LoadedModules -join ', '))"
    Assert-Condition ($LoadedModules -contains "flutter_windows.dll") "Running GUI process did not load flutter_windows.dll (loaded: $($LoadedModules -join ', '))"
}

function Stop-ProcessesUnderDir {
    param([Parameter(Mandatory = $true)][string]$DirPath)
    $Prefix = [System.IO.Path]::GetFullPath($DirPath).TrimEnd('\', '/') + "\"
    $StoppedAny = $false
    foreach ($proc in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            if ($proc.Id -eq $PID) { continue }
            $exePath = $null
            try { $exePath = $proc.MainModule.FileName } catch { $exePath = $null }
            if ($exePath -and $exePath.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
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
        Start-Sleep -Milliseconds 400
    }
}

function Get-PeMachineHex {
    param([string]$FilePath)
    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        Assert-Condition ($fs.Length -ge 256) "PE file too small: $FilePath"
        $br = New-Object System.IO.BinaryReader($fs)
        $mz = $br.ReadUInt16()
        Assert-Condition ($mz -eq 0x5A4D) "Invalid MZ DOS header on $FilePath"
        $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $br.ReadInt32()
        Assert-Condition ($peOffset -ge 64 -and ($peOffset + 6) -le $fs.Length) "Out-of-bounds PE header offset on $FilePath"
        $fs.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peSig = $br.ReadUInt32()
        Assert-Condition ($peSig -eq 0x00004550) "Invalid PE\0\0 signature on $FilePath"
        $machine = $br.ReadUInt16()
        return ("0x{0:X4}" -f $machine)
    } finally {
        $fs.Dispose()
    }
}

$TempVerifyLog = Join-Path $env:TEMP ("dauverse_rc_verify_" + [guid]::NewGuid().ToString("N") + ".log")
$TranscriptStarted = $false
Start-Transcript -Path $TempVerifyLog -Force | Out-Null
$TranscriptStarted = $true

$CoexistDir = Join-Path $env:TEMP ("ExternalRustDeskCoexist_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$PreexistingExternalRustDesk = $null -ne (Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue)
Assert-Condition (-not $PreexistingExternalRustDesk) "Disposable runner unexpectedly already has a RustDesk service before harness start."

$PreServices = @(Get-CimInstance Win32_Service | ForEach-Object { "$($_.Name)|$($_.PathName)" } | Sort-Object)
$PreRootCerts = @(Get-ChildItem Cert:\LocalMachine\Root | Select-Object -ExpandProperty Thumbprint | Sort-Object)
$PreHkcuRun = if (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run") {
    (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" | Out-String)
} else { "" }

try {
    Write-Host "=== [1/7] Pre-Flight Bidirectional Immutable Manifest, Build Log, Provenance & PE Header Audit ==="
    foreach ($f in @($SetupExe, $PortableExe, $SigningTxt, $InitialManifest, $ManifestTxt, $BuildLogOut, $BuildProvJson, $DriverProvJson)) {
        Assert-Condition (Test-Path -LiteralPath $f) "Missing required build output before verification: $f"
    }
    $InitialManifestEntries = Assert-ManifestFileValid -ManifestFilePath $InitialManifest -BaseDirectory $ReleaseDir -ManifestRole "Initial"
    $IncomingManifestEntries = Assert-ManifestFileValid -ManifestFilePath $ManifestTxt -BaseDirectory $ReleaseDir -ManifestRole "Final"
    Assert-OriginalBuildLogValid -LogPath $BuildLogOut

    Write-Host "=== [0/7] Negative & Positive Harness Self-Tests (Codex F02 / FT010-B01 / FT010-Q01 Sentinels) ==="
    $NegTmp = Join-Path $env:TEMP ("dauverse_harness_neg_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $NegTmp | Out-Null
    try {
        $NegResults = @()
        $CaseMissing = Join-Path $NegTmp "c_missing"; New-Item -ItemType Directory -Force -Path $CaseMissing | Out-Null
        Set-Content -LiteralPath (Join-Path $CaseMissing "sample.bin") -Value "hello-rc4" -Encoding UTF8
        $GoodHash = (Get-FileHash -LiteralPath (Join-Path $CaseMissing "sample.bin") -Algorithm SHA256).Hash.ToLowerInvariant()
        $BadHash  = "0" * 64
        Set-Content -LiteralPath (Join-Path $CaseMissing "SHA256_MANIFEST.txt") -Value @("$GoodHash  sample.bin", "$GoodHash  absent.exe") -Encoding UTF8
        $NegResults += Assert-Throws "missing_manifest_file" { Assert-ManifestFileValid -ManifestFilePath (Join-Path $CaseMissing "SHA256_MANIFEST.txt") -BaseDirectory $CaseMissing -ManifestRole "Final" }

        # FT010-B01 Positive + Negative Final Layout Self-Test (exact production New-ReleaseManifestLines -> Assert-ManifestFileValid)
        $CaseFinalLayout = Join-Path $NegTmp "c_final_layout"; New-Item -ItemType Directory -Force -Path $CaseFinalLayout | Out-Null
        Copy-Item -LiteralPath (Join-Path $CaseMissing "sample.bin") -Destination (Join-Path $CaseFinalLayout "sample.bin")
        $InitLinesTest = New-ReleaseManifestLines -BaseDirectory $CaseFinalLayout -ManifestRole "Initial"
        Set-Content -LiteralPath (Join-Path $CaseFinalLayout "INITIAL_BUILD_SHA256_MANIFEST.txt") -Value $InitLinesTest -Encoding UTF8
        Assert-Condition ((Assert-ManifestFileValid -ManifestFilePath (Join-Path $CaseFinalLayout "INITIAL_BUILD_SHA256_MANIFEST.txt") -BaseDirectory $CaseFinalLayout -ManifestRole "Initial") -eq 1) "FT010-B01 initial manifest positive check failed"
        Set-Content -LiteralPath (Join-Path $CaseFinalLayout "WINDOWS_RC_VERIFICATION_REPORT.json") -Value '{"ok":true}' -Encoding UTF8
        $FinalLinesTest = New-ReleaseManifestLines -BaseDirectory $CaseFinalLayout -ManifestRole "Final"
        Set-Content -LiteralPath (Join-Path $CaseFinalLayout "SHA256_MANIFEST.txt") -Value $FinalLinesTest -Encoding UTF8
        Assert-Condition ((Assert-ManifestFileValid -ManifestFilePath (Join-Path $CaseFinalLayout "SHA256_MANIFEST.txt") -BaseDirectory $CaseFinalLayout -ManifestRole "Final") -eq 3) "FT010-B01 final manifest positive check failed"

        # FT010-B01 Negative: Final manifest omitting INITIAL_BUILD_SHA256_MANIFEST.txt MUST fail closed
        $OmittedFinalLines = @($FinalLinesTest | Where-Object { $_ -notmatch "INITIAL_BUILD_SHA256_MANIFEST\.txt" })
        Set-Content -LiteralPath (Join-Path $CaseFinalLayout "SHA256_MANIFEST.txt") -Value $OmittedFinalLines -Encoding UTF8
        $NegResults += Assert-Throws "final_manifest_missing_initial_manifest_rejected" { Assert-ManifestFileValid -ManifestFilePath (Join-Path $CaseFinalLayout "SHA256_MANIFEST.txt") -BaseDirectory $CaseFinalLayout -ManifestRole "Final" }

        $CaseBadHash = Join-Path $NegTmp "c_badhash"; New-Item -ItemType Directory -Force -Path $CaseBadHash | Out-Null
        Copy-Item -LiteralPath (Join-Path $CaseMissing "sample.bin") -Destination (Join-Path $CaseBadHash "sample.bin")
        Set-Content -LiteralPath (Join-Path $CaseBadHash "SHA256_MANIFEST.txt") -Value @("$BadHash  sample.bin") -Encoding UTF8
        $NegResults += Assert-Throws "corrupted_manifest_digest" { Assert-ManifestFileValid -ManifestFilePath (Join-Path $CaseBadHash "SHA256_MANIFEST.txt") -BaseDirectory $CaseBadHash }

        $CaseDup = Join-Path $NegTmp "c_dup"; New-Item -ItemType Directory -Force -Path $CaseDup | Out-Null
        Copy-Item -LiteralPath (Join-Path $CaseMissing "sample.bin") -Destination (Join-Path $CaseDup "sample.bin")
        Set-Content -LiteralPath (Join-Path $CaseDup "SHA256_MANIFEST.txt") -Value @("$GoodHash  sample.bin", "$GoodHash  sample.bin") -Encoding UTF8
        $NegResults += Assert-Throws "duplicate_manifest_entry" { Assert-ManifestFileValid -ManifestFilePath (Join-Path $CaseDup "SHA256_MANIFEST.txt") -BaseDirectory $CaseDup }

        $CaseExtra = Join-Path $NegTmp "c_extra"; New-Item -ItemType Directory -Force -Path $CaseExtra | Out-Null
        Copy-Item -LiteralPath (Join-Path $CaseMissing "sample.bin") -Destination (Join-Path $CaseExtra "sample.bin")
        Set-Content -LiteralPath (Join-Path $CaseExtra "unlisted_rogue.exe") -Value "unlisted" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $CaseExtra "SHA256_MANIFEST.txt") -Value @("$GoodHash  sample.bin") -Encoding UTF8
        $NegResults += Assert-Throws "unlisted_manifest_extra_rejected" { Assert-ManifestFileValid -ManifestFilePath (Join-Path $CaseExtra "SHA256_MANIFEST.txt") -BaseDirectory $CaseExtra }

        $NegResults += Assert-Throws "gui_early_exit_0_rejected" { Assert-GuiWindowSurvived -AliveAfter5s $false -ExitCode 0 -LoadedModules @("librustdesk.dll", "flutter_windows.dll") }
        $NegResults += Assert-Throws "gui_early_exit_1_rejected" { Assert-GuiWindowSurvived -AliveAfter5s $false -ExitCode 1 -LoadedModules @("librustdesk.dll", "flutter_windows.dll") }
        $NegResults += Assert-Throws "gui_early_exit_2_rejected" { Assert-GuiWindowSurvived -AliveAfter5s $false -ExitCode 2 -LoadedModules @("librustdesk.dll", "flutter_windows.dll") }
        $NegResults += Assert-Throws "gui_missing_dll_rejected" { Assert-GuiWindowSurvived -AliveAfter5s $true -ExitCode $null -LoadedModules @("flutter_windows.dll") }
        $NegResults += Assert-Throws "missing_build_log_rejected" { Assert-OriginalBuildLogValid -LogPath (Join-Path $NegTmp "no_such_build.log") }

        Set-Content -LiteralPath (Join-Path $NegTmp "tiny_build.log") -Value "Windows native build completed cleanly prior to RC verification." -Encoding UTF8
        $NegResults += Assert-Throws "synthetic_placeholder_build_log_rejected" { Assert-OriginalBuildLogValid -LogPath (Join-Path $NegTmp "tiny_build.log") }

        $PaddedSyntheticLog = ("PADDING_LINE_ONLY`r`n" * 90) + "=== NATIVE COMPILATION & PACKAGING SUCCEEDED ===`r`n"
        Set-Content -LiteralPath (Join-Path $NegTmp "padded_synthetic.log") -Value $PaddedSyntheticLog -Encoding UTF8
        $NegResults += Assert-Throws "padded_synthetic_build_log_rejected" { Assert-OriginalBuildLogValid -LogPath (Join-Path $NegTmp "padded_synthetic.log") }

        # FT010-Q01 Negative: Complete-marker fabricated build log without compiler/NSIS outputs MUST fail closed
        $AllHeadersOnlyLog = (@(
            "RepoRoot      : C:\fake",
            "CargoTarget   : C:\fake\target",
            ">>> [flutter pub get]",
            ">>> [Build dylib_virtual_display]",
            ">>> [Build librustdesk.dll]",
            ">>> [flutter build windows --release]",
            ">>> [Generate single-file portable executable]",
            ">>> [Compile NSIS Setup Installer]",
            ("PADDING_WITHOUT_COMPILER_OUTPUT_0123456789`r`n" * 35),
            "=== NATIVE COMPILATION & PACKAGING SUCCEEDED ==="
        ) -join "`r`n")
        Set-Content -LiteralPath (Join-Path $NegTmp "all_headers_synthetic.log") -Value $AllHeadersOnlyLog -Encoding UTF8
        $NegResults += Assert-Throws "complete_marker_fabricated_build_log_rejected" { Assert-OriginalBuildLogValid -LogPath (Join-Path $NegTmp "all_headers_synthetic.log") }

        $CaseSkip = Join-Path $NegTmp "c_skip"; New-Item -ItemType Directory -Force -Path $CaseSkip | Out-Null
        Copy-Item -LiteralPath (Join-Path $CaseMissing "sample.bin") -Destination (Join-Path $CaseSkip "sample.bin")
        Set-Content -LiteralPath (Join-Path $CaseSkip "SHA256_MANIFEST.txt") -Value @("$GoodHash  sample.bin") -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $CaseSkip "TESTS_SKIPPED_NOT_RC_ELIGIBLE.txt") -Value "skipped" -Encoding UTF8
        $NegResults += Assert-Throws "skipped_tests_marker_rejected" { Assert-ManifestFileValid -ManifestFilePath (Join-Path $CaseSkip "SHA256_MANIFEST.txt") -BaseDirectory $CaseSkip }

        [ordered]@{
            suite = "QA_HARNESS_NEGATIVE_SELFTEST"
            executed_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            total_cases = $NegResults.Count
            all_rejected_as_expected = $true
            cases = $NegResults
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SelfTestJsonOut -Encoding UTF8
    } finally {
        Remove-Item -LiteralPath $NegTmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $BuildProv = Get-Content -Raw -LiteralPath $BuildProvJson | ConvertFrom-Json
    $GitSha = (& git -C $RepoRoot rev-parse HEAD).Trim()
    $SubmoduleSha = (& git -C (Join-Path $RepoRoot "libs\hbb_common") rev-parse HEAD).Trim()
    Assert-Condition ($BuildProv.gates.tests_executed -eq $true) "BUILD_PROVENANCE.json reports tests_executed != true"
    Assert-Condition ($BuildProv.gates.fallback_setup_used -eq $false) "BUILD_PROVENANCE.json reports fallback_setup_used != false"
    Assert-Condition ($BuildProv.gates.rc_acceptance_eligible -eq $true) "BUILD_PROVENANCE.json reports rc_acceptance_eligible != true"
    Assert-Condition ($BuildProv.source.git_commit_sha -eq $GitSha) "BUILD_PROVENANCE git_commit_sha mismatch ($($BuildProv.source.git_commit_sha) vs $GitSha)"
    if ($BuildProv.ci_environment.github_actions -eq $true) {
        Assert-Condition ($BuildProv.resolved_toolchains.makensis_version -eq "v3.11") "F15_NSIS_PIN_MISMATCH: expected makensis_version == v3.11 in CI, got '$($BuildProv.resolved_toolchains.makensis_version)'"
    }

    $SetupSize    = (Get-Item -LiteralPath $SetupExe).Length
    $PortableSize = (Get-Item -LiteralPath $PortableExe).Length
    Assert-Condition ($SetupSize -gt 10MB) "SETUP.exe unexpectedly small: $SetupSize bytes"
    Assert-Condition ($PortableSize -gt 10MB) "PORTABLE.exe unexpectedly small: $PortableSize bytes"

    $SetupMachine    = Get-PeMachineHex -FilePath $SetupExe
    $PortableMachine = Get-PeMachineHex -FilePath $PortableExe
    Assert-Condition ($PortableMachine -eq "0x8664") "Expected x64 PE (0x8664) for PORTABLE.exe, got $PortableMachine"

    $SigningText = (Get-Content -Raw -LiteralPath $SigningTxt).Trim()
    Assert-Condition ($SigningText.StartsWith("UNSIGNED") -or $SigningText.StartsWith("SIGNED_AUTHENTICODE")) "Unexpected SIGNING_STATUS.txt content: $SigningText"

    $WdkRootCerts = @(Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "WDKTestCert" -or $_.Thumbprint -eq "D1DBB672D5A500B9809689CAEA1CE49E799767F0" })
    Assert-Condition ($WdkRootCerts.Count -eq 0) "SECURITY_VIOLATION: Found WDKTestCert in Cert:\LocalMachine\Root!"

    Write-Host "=== [2/7] External RustDesk Coexistence Setup & NSIS Silent Installer (F03, A02) ==="
    New-Item -ItemType Directory -Force -Path $CoexistDir | Out-Null
    Copy-Item -LiteralPath "$env:SystemRoot\System32\cmd.exe" -Destination (Join-Path $CoexistDir "rustdesk.exe") -Force
    $ExternalConfigFile = Join-Path $CoexistDir "RustDesk2.toml"
    Set-Content -LiteralPath $ExternalConfigFile -Value "id = 'external-coexisting-user-instance'`r`npreserve_me = true" -Encoding UTF8
    $ExternalConfigShaBefore = (Get-FileHash -LiteralPath $ExternalConfigFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $ExternalSvcBinPath = "`"$CoexistDir\rustdesk.exe`" --service"

    & sc.exe create RustDesk binPath= $ExternalSvcBinPath start= demand DisplayName= "External Preexisting RustDesk Service" | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Failed to register simulated external RustDesk service for F03 coexistence test"
    $ExternalImgBefore = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\RustDesk").ImagePath

    $HasFixedE = $false
    try {
        $diE = [System.IO.DriveInfo]::new("E:\")
        if ($diE.IsReady -and $diE.DriveType -eq [System.IO.DriveType]::Fixed) { $HasFixedE = $true }
    } catch {}
    $ExpectedInstallDir = if ($HasFixedE) { "E:\Program Files\DAUVERSE Remote Desktop" } else { "$env:ProgramFiles\DAUVERSE Remote Desktop" }

    $InstallProc = Start-Process -FilePath $SetupExe -ArgumentList "/S" -Wait -PassThru
    Assert-Condition ($InstallProc.ExitCode -eq 0) "NSIS silent install exited with $($InstallProc.ExitCode) (helperDiag=$(Get-NsisHelperDiagTail))"

    # Verify external RustDesk service & user config survived SETUP.exe /S completely untouched (F03)
    $SvcAfterInstall = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $SvcAfterInstall) "F03_VIOLATION: External RustDesk service was deleted during SETUP.exe /S!"
    $ExternalImgAfterInstall = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\RustDesk").ImagePath
    Assert-Condition ($ExternalImgAfterInstall -eq $ExternalImgBefore) "F03_VIOLATION: External RustDesk service ImagePath modified ($ExternalImgAfterInstall vs $ExternalImgBefore)!"
    Assert-Condition ((Get-FileHash -LiteralPath $ExternalConfigFile -Algorithm SHA256).Hash.ToLowerInvariant() -eq $ExternalConfigShaBefore) "F03_VIOLATION: External RustDesk config modified!"

    $RequiredInstalledFiles = @(
        "DAUVERSE_REMOTE.exe",
        "rustdesk.exe",
        "librustdesk.dll",
        "flutter_windows.dll",
        "dylib_virtual_display.dll",
        "Uninstall.exe",
        "data\app.so",
        "data\icudtl.dat",
        "usbmmidd_v2\usbmmIdd.inf",
        "usbmmidd_v2\usbmmidd.cat",
        "usbmmidd_v2\x64\usbmmIdd.dll",
        "usbmmidd_v2\License.txt"
    )
    foreach ($rel in $RequiredInstalledFiles) {
        $p = Join-Path $ExpectedInstallDir $rel
        Assert-Condition (Test-Path -LiteralPath $p) "Installed file missing after SETUP.exe /S: $p"
    }

    $ForbiddenIddFiles = @(Get-ChildItem -LiteralPath $ExpectedInstallDir -Recurse -Filter "*RustDeskIdd*" -ErrorAction SilentlyContinue)
    Assert-Condition ($ForbiddenIddFiles.Count -eq 0) "SECURITY_VIOLATION: RustDeskIddDriver files found in installation!"

    # Verify WHQL Authenticode validity + catalog membership + pinned SHA-256 digests on staged usbmmidd_v2
    $InstalledDriverDir = Join-Path $ExpectedInstallDir "usbmmidd_v2"
    $InstalledCatPath = Join-Path $InstalledDriverDir "usbmmidd.cat"
    $UsbCatSig = Get-AuthenticodeSignature -LiteralPath $InstalledCatPath
    $UsbCatStatus = [string]$UsbCatSig.Status
    $UsbCatSubject = if ($UsbCatSig.SignerCertificate) { $UsbCatSig.SignerCertificate.Subject } else { "NONE" }
    Assert-Condition ($UsbCatStatus -eq "Valid") "Expected Valid Authenticode status on usbmmidd.cat, got: $UsbCatStatus ($($UsbCatSig.StatusMessage))"
    Assert-Condition ($UsbCatSubject -match "Microsoft Windows Hardware Compatibility Publisher") "Expected Microsoft WHQL signer on usbmmidd.cat, got: $UsbCatSubject"

    if (-not ("DauverseWinTrustCatalog" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class DauverseWinTrustCatalog {
    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CryptCATAdminAcquireContext2(
        out IntPtr phCatAdmin, IntPtr pgSubsystem, string pwszHashAlgorithm, IntPtr pStrongHashPolicy, uint dwFlags);

    [DllImport("wintrust.dll", SetLastError = true)]
    private static extern bool CryptCATAdminReleaseContext(IntPtr hCatAdmin, uint dwFlags);

    [DllImport("wintrust.dll", SetLastError = true)]
    private static extern bool CryptCATAdminCalcHashFromFileHandle2(
        IntPtr hCatAdmin, IntPtr hFile, ref uint pcbHash, byte[] pbHash, uint dwFlags);

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CryptCATOpen(
        string pwszFileName, uint fdwOpenFlags, IntPtr hProv, uint dwPublicVersion, uint dwEncodingType);

    [DllImport("wintrust.dll", SetLastError = true)]
    private static extern bool CryptCATClose(IntPtr hCatalog);

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CryptCATGetMemberInfo(IntPtr hCatalog, string pwszReferenceTag);

    public static string VerifyMemberSha256InCatalog(string catalogPath, string targetFilePath) {
        IntPtr hCatAdmin = IntPtr.Zero;
        if (!CryptCATAdminAcquireContext2(out hCatAdmin, IntPtr.Zero, "SHA256", IntPtr.Zero, 0)) {
            throw new InvalidOperationException("CryptCATAdminAcquireContext2(SHA256) failed: " + Marshal.GetLastWin32Error());
        }
        try {
            string hexTag;
            using (FileStream fs = File.OpenRead(targetFilePath)) {
                uint cbHash = 0;
                CryptCATAdminCalcHashFromFileHandle2(hCatAdmin, fs.SafeFileHandle.DangerousGetHandle(), ref cbHash, null, 0);
                if (cbHash == 0) {
                    throw new InvalidOperationException("CryptCATAdminCalcHashFromFileHandle2 size query failed: " + Marshal.GetLastWin32Error());
                }
                byte[] hashBytes = new byte[cbHash];
                if (!CryptCATAdminCalcHashFromFileHandle2(hCatAdmin, fs.SafeFileHandle.DangerousGetHandle(), ref cbHash, hashBytes, 0)) {
                    throw new InvalidOperationException("CryptCATAdminCalcHashFromFileHandle2 hash failed: " + Marshal.GetLastWin32Error());
                }
                StringBuilder sb = new StringBuilder((int)cbHash * 2);
                for (int i = 0; i < cbHash; i++) {
                    sb.Append(hashBytes[i].ToString("X2"));
                }
                hexTag = sb.ToString();
            }

            IntPtr hCat = CryptCATOpen(catalogPath, 2, IntPtr.Zero, 0, 0);
            if (hCat == IntPtr.Zero || hCat == new IntPtr(-1)) {
                throw new InvalidOperationException("CryptCATOpen failed on " + catalogPath + ": " + Marshal.GetLastWin32Error());
            }
            try {
                IntPtr memberInfo = CryptCATGetMemberInfo(hCat, hexTag);
                if (memberInfo == IntPtr.Zero) {
                    throw new InvalidOperationException("Member SHA256 tag " + hexTag + " NOT FOUND in WHQL catalog " + catalogPath);
                }
                return "VALID_WINTRUST_MEMBER_SHA256:" + hexTag;
            } finally {
                CryptCATClose(hCat);
            }
        } finally {
            CryptCATAdminReleaseContext(hCatAdmin, 0);
        }
    }
}
"@
    }

    $CatTagDll = [DauverseWinTrustCatalog]::VerifyMemberSha256InCatalog($InstalledCatPath, (Join-Path $InstalledDriverDir "x64\usbmmIdd.dll"))
    $CatTagInf = [DauverseWinTrustCatalog]::VerifyMemberSha256InCatalog($InstalledCatPath, (Join-Path $InstalledDriverDir "usbmmIdd.inf"))
    $Null = Assert-Throws "non_member_binary_rejected_by_whql_catalog" {
        [DauverseWinTrustCatalog]::VerifyMemberSha256InCatalog($InstalledCatPath, (Join-Path $ExpectedInstallDir "DAUVERSE_REMOTE.exe"))
    }
    $CatalogValidationStatus = "DLL=$CatTagDll;INF=$CatTagInf;NON_MEMBER_REJECTED=PASS"
    Assert-Condition ((Get-FileHash -LiteralPath (Join-Path $InstalledDriverDir "License.txt") -Algorithm SHA256).Hash.ToLowerInvariant() -eq "44c73fc4110979899dbb5054662de581f7d4350939f19bb2d50574f613314ba2") "usbmmidd_v2\License.txt SHA-256 mismatch!"

    $ArpKey64 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop"
    Assert-Condition (Test-Path -LiteralPath $ArpKey64) "Missing 64-bit ARP Uninstall registry key at $ArpKey64"
    $ArpProps = Get-ItemProperty -LiteralPath $ArpKey64
    Assert-Condition ($ArpProps.DisplayName -eq "DAUVERSE REMOTE DESKTOP V1.0") "Unexpected ARP DisplayName: $($ArpProps.DisplayName)"
    Assert-Condition ($ArpProps.InstallLocation -eq $ExpectedInstallDir) "Unexpected ARP InstallLocation: $($ArpProps.InstallLocation)"

    $StartMenuCandidates = @(
        (Join-Path ([Environment]::GetFolderPath("Programs")) "DAUVERSE Remote Desktop\DAUVERSE Remote Desktop.lnk"),
        (Join-Path ([Environment]::GetFolderPath("CommonPrograms")) "DAUVERSE Remote Desktop\DAUVERSE Remote Desktop.lnk")
    )
    $StartMenuLnk = $StartMenuCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    Assert-Condition ($null -ne $StartMenuLnk) "Missing Start Menu shortcut in Programs or CommonPrograms"

    Write-Host "=== [3/7] Startup Verification (Exact Version 1.5.3, Win32 GUI 5s Survival & Portable GUI) ==="
    $InstalledMainExe = Join-Path $ExpectedInstallDir "DAUVERSE_REMOTE.exe"
    $InstalledShimExe = Join-Path $ExpectedInstallDir "rustdesk.exe"
    $InstalledDllMachine = Get-PeMachineHex -FilePath (Join-Path $ExpectedInstallDir "librustdesk.dll")
    Assert-Condition ($InstalledDllMachine -eq "0x8664") "Expected x64 librustdesk.dll, got $InstalledDllMachine"

    $VerOutFile1 = Join-Path $env:TEMP "dauverse_cli_ver1.txt"
    $VerProc1 = Start-Process -FilePath $InstalledMainExe -ArgumentList "--version" -WorkingDirectory $ExpectedInstallDir -RedirectStandardOutput $VerOutFile1 -Wait -PassThru
    Assert-Condition ($VerProc1.ExitCode -eq 0) "DAUVERSE_REMOTE.exe --version failed with exit code $($VerProc1.ExitCode)"
    $CliVerOut = (Get-Content -Raw -LiteralPath $VerOutFile1).Trim()
    Remove-Item -Force -LiteralPath $VerOutFile1 -ErrorAction SilentlyContinue
    Assert-Condition ($CliVerOut -eq "1.5.3") "Expected DAUVERSE_REMOTE.exe --version == '1.5.3', got '$CliVerOut'"

    $VerOutFile2 = Join-Path $env:TEMP "dauverse_cli_ver2.txt"
    $VerProc2 = Start-Process -FilePath $InstalledShimExe -ArgumentList "--version" -WorkingDirectory $ExpectedInstallDir -RedirectStandardOutput $VerOutFile2 -Wait -PassThru
    Assert-Condition ($VerProc2.ExitCode -eq 0) "rustdesk.exe --version failed with exit code $($VerProc2.ExitCode)"
    $ShimVerOut = (Get-Content -Raw -LiteralPath $VerOutFile2).Trim()
    Remove-Item -Force -LiteralPath $VerOutFile2 -ErrorAction SilentlyContinue
    Assert-Condition ($ShimVerOut -eq "1.5.3") "Expected rustdesk.exe --version == '1.5.3', got '$ShimVerOut'"

    $SessionId = (Get-Process -Id $PID).SessionId
    $GuiProc = Start-Process -FilePath $InstalledMainExe -ArgumentList "--dauverse-ui", "--no-server" -WorkingDirectory $ExpectedInstallDir -PassThru
    Start-Sleep -Seconds 5
    $GuiProc.Refresh()
    $GuiAliveAfter5s = -not $GuiProc.HasExited
    $GuiExitCode = if ($GuiProc.HasExited) { $GuiProc.ExitCode } else { $null }
    $LoadedKeyDlls = @()
    if ($GuiAliveAfter5s) {
        $LoadedKeyDlls = @($GuiProc.Modules | Where-Object { $_.ModuleName -in @("librustdesk.dll", "flutter_windows.dll") } | Select-Object -ExpandProperty ModuleName -Unique)
    }
    try {
        Assert-GuiWindowSurvived -AliveAfter5s $GuiAliveAfter5s -ExitCode $GuiExitCode -LoadedModules $LoadedKeyDlls
    } finally {
        Stop-ProcessesUnderDir -DirPath $ExpectedInstallDir
    }

    # Portable self-extraction + portable Win32 GUI 5s survival
    $PortableExtractDir = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "rustdesk"
    if (Test-Path -LiteralPath $PortableExtractDir) {
        Stop-ProcessesUnderDir -DirPath $PortableExtractDir
        Remove-Item -LiteralPath $PortableExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $PortableWorkDir = Join-Path $env:TEMP ("dauverse_portable_smoke_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $PortableWorkDir | Out-Null
    $PortableGuiSurvived = $false
    try {
        $PortProc = Start-Process -FilePath $PortableExe -ArgumentList "--version" -WorkingDirectory $PortableWorkDir -Wait -PassThru
        Assert-Condition ($PortProc.ExitCode -eq 0) "PORTABLE.exe --version exited with $($PortProc.ExitCode)"
        Start-Sleep -Seconds 2
        foreach ($reqPort in @("meta.toml", "DAUVERSE_REMOTE.exe", "librustdesk.dll", "flutter_windows.dll", "usbmmidd_v2\License.txt")) {
            Assert-Condition (Test-Path -LiteralPath (Join-Path $PortableExtractDir $reqPort)) "PORTABLE.exe did not extract $reqPort into $PortableExtractDir"
        }
        $PortGuiProc = Start-Process -FilePath (Join-Path $PortableExtractDir "DAUVERSE_REMOTE.exe") -ArgumentList "--dauverse-ui", "--no-server" -WorkingDirectory $PortableExtractDir -PassThru
        Start-Sleep -Seconds 5
        $PortGuiProc.Refresh()
        $PortAlive = -not $PortGuiProc.HasExited
        $PortExit = if ($PortGuiProc.HasExited) { $PortGuiProc.ExitCode } else { $null }
        $PortMods = if ($PortAlive) { @($PortGuiProc.Modules | Where-Object { $_.ModuleName -in @("librustdesk.dll", "flutter_windows.dll") } | Select-Object -ExpandProperty ModuleName -Unique) } else { @() }
        Assert-GuiWindowSurvived -AliveAfter5s $PortAlive -ExitCode $PortExit -LoadedModules $PortMods
        $PortableGuiSurvived = $true
    } finally {
        Stop-ProcessesUnderDir -DirPath $PortableExtractDir
        Stop-ProcessesUnderDir -DirPath $PortableWorkDir
        Remove-Item -LiteralPath $PortableWorkDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $PortableExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "=== [4/7] Multi-Process Windows DPAPI + Full Remediation Security Matrix ==="
    $PyWorker = @'
import ctypes, hashlib, hmac, json, math, os, struct, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

phase = sys.argv[1]
install_dir = Path(sys.argv[2])
repo_root = Path(sys.argv[3])
data_dir = Path(sys.argv[4])
secret = "dauverse-win-rc3-hmac-secret-2026"

effective_dir = data_dir
if phase == "phase3_corrupt":
    effective_dir = data_dir / "isolated_corrupt_dpapi"
    effective_dir.mkdir(parents=True, exist_ok=True)
    (effective_dir / "step_up_pin.vault").write_bytes(b"CORRUPTED_DPAPI_VAULT")
elif phase == "phase4_corrupt_replay":
    effective_dir = data_dir / "isolated_corrupt_replay"
    effective_dir.mkdir(parents=True, exist_ok=True)
    (effective_dir / "bridge_replay_journal.json").write_bytes(b"{corrupted_replay_journal")

os.environ["DAUVERSE_DATA_DIR"] = str(effective_dir)
os.environ["DAUVERSE_EVENT_HMAC_KEY"] = secret
os.environ["DAUVERSE_EVENT_BRIDGE_PORT"] = "0"

os.add_dll_directory(str(install_dir))
os.chdir(str(install_dir))
lib = ctypes.CDLL(str(install_dir / "librustdesk.dll"))
lib.dauverse_invoke.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
lib.dauverse_invoke.restype = ctypes.c_void_p
lib.dauverse_free_str.argtypes = [ctypes.c_void_p]
lib.dauverse_free_str.restype = None

def call_ffi(cmd, payload=None):
    ptr = lib.dauverse_invoke(cmd.encode("utf-8"), json.dumps(payload or {}).encode("utf-8"))
    assert ptr, "NULL_FFI_PTR"
    try:
        return json.loads(ctypes.cast(ptr, ctypes.c_char_p).value.decode("utf-8"))
    finally:
        lib.dauverse_free_str(ptr)

def f32_tag(val):
    raw_be = struct.pack(">f", float(val))
    bits = struct.unpack(">I", raw_be)[0]
    f32_val = struct.unpack(">f", raw_be)[0]
    return f32_val, f"f32:{bits:08x}"

def sign_v3(event_obj, issued_at_ms, nonce):
    prov = event_obj["provenance"]
    prog = event_obj.get("progress")
    if prog is None:
        prog_tag = None
    else:
        f_p, prog_tag = f32_tag(prog)
        event_obj["progress"] = f_p
    f_c, conf_tag = f32_tag(event_obj["confidence"])
    event_obj["confidence"] = f_c
    payload = [
        "DAUVERSE_AI_EVENT_V3",
        3,
        int(issued_at_ms),
        str(nonce),
        event_obj["event_id"],
        event_obj["timestamp"],
        event_obj["source"],
        event_obj["device_id"],
        event_obj["project_id"],
        event_obj["task_id"],
        event_obj["task_name"],
        event_obj["event_type"],
        event_obj["status"],
        event_obj["severity"],
        prog_tag,
        event_obj["summary"],
        event_obj.get("artifact_reference"),
        conf_tag,
        [
            prov["adapter_type"],
            bool(prov["evidence_verified"]),
            prov.get("exit_code"),
            prov.get("evidence_badge"),
        ],
    ]
    canonical = json.dumps(payload, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")
    return hmac.new(secret.encode("utf-8"), canonical, hashlib.sha256).hexdigest()

def post_json(url, obj):
    req = urllib.request.Request(
        url,
        data=json.dumps(obj).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        return e.code, (json.loads(raw) if raw.strip().startswith("{") else {"raw": raw})

if phase == "phase1":
    snap = call_ffi("dashboard_snapshot")
    assert snap.get("ok") is True, f"dashboard_snapshot failed: {snap}"
    d = snap["data"]
    sec = call_ffi("security_summary")["data"]["summary"]
    assert sec["credential_vault"] == "WINDOWS_DPAPI", f"Expected WINDOWS_DPAPI, got {sec}"

    pin_res = call_ffi("set_step_up_pin", {"pin": "WinVault#2026"})
    assert pin_res.get("ok") is True, f"set_step_up_pin failed: {pin_res}"
    vault_file = data_dir / "step_up_pin.vault"
    raw_vault = vault_file.read_bytes()
    assert len(raw_vault) > 32 and b"WinVault#2026" not in raw_vault

    svc = d["service"]
    assert svc["external_service_collision_detected"] is True, f"Expected external service collision True, got {svc}"
    assert svc["service_owned_by_dauverse"] is False, f"Expected service_owned_by_dauverse False, got {svc}"
    unatt = call_ffi("configure_unattended", {"enable": True, "step_up_pin": "WinVault#2026"})
    assert unatt.get("ok") is False, f"configure_unattended should refuse external service collision: {unatt}"

    assert call_ffi("set_performance_mode", {"mode": "HIGH_QUALITY"})["ok"] is True
    assert call_ffi("set_clipboard_policy", {"enabled": True, "allow_text_unicode": True, "allow_images": True, "allow_files": False})["ok"] is True
    assert call_ffi("transfer_set_policy", {"bandwidth_limit_kbps": 4096})["ok"] is True

    endpoint = d["bridge_endpoint"]
    env = os.environ.copy()
    env["DAUVERSE_EVENT_HMAC_KEY"] = secret
    env["DAUVERSE_EVENT_ENDPOINT"] = endpoint
    env["DAUVERSE_EVENT_BRIDGE_URL"] = endpoint

    subprocess.run(
        [sys.executable, str(repo_root / "scripts/hooks/claude_code_hook.py")],
        input=json.dumps({"hook_event_name": "Stop", "session_id": "win-rc3-01", "message": "Claude hook v3 OK"}).encode("utf-8"),
        env=env, check=True, capture_output=True,
    )
    subprocess.run(
        [sys.executable, str(repo_root / "scripts/hooks/codex_notify_hook.py"),
         json.dumps({"type": "agent-turn-complete", "turn-id": "win-rc3-02", "last-assistant-message": "Codex hook v3 OK"})],
        env=env, check=True, capture_output=True,
    )
    subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         str(repo_root / "scripts/hooks/dauverse_job_wrapper.ps1"),
         "-ProjectId", "DAUVERSE-RC3", "-TaskName", "PowerShell Wrapper v3", "-JobKind", "QA", "-CommandToRun", "exit 0"],
        env=env, check=True, capture_output=True,
    )

    now_ms = int(time.time() * 1000)
    persist_evt = {
        "event_id": "evt-win-persist-001",
        "timestamp": "2026-11-26T00:00:00Z",
        "source": "codex_cli",
        "device_id": "WIN-SANDBOX",
        "project_id": "DAUVERSE-RC3",
        "task_id": "persist-task-1",
        "task_name": "Cross-Restart Replay Sentinel",
        "event_type": "TASK_COMPLETED",
        "status": "COMPLETED",
        "severity": "SUCCESS",
        "progress": 100.0,
        "summary": "Initial accepted event before process exit",
        "artifact_reference": "RELEASE/SHA256_MANIFEST.txt",
        "confidence": 1.0,
        "provenance": {
            "adapter_type": "OFFICIAL_HOOK",
            "evidence_verified": True,
            "exit_code": 0,
            "evidence_badge": "HOOK_EXIT_0",
        },
    }
    persist_sig = sign_v3(persist_evt, now_ms, "persistnonce0001")
    persist_env = {
        "schema_version": 3,
        "event": persist_evt,
        "issued_at_ms": now_ms,
        "nonce": "persistnonce0001",
        "signature_hex": persist_sig,
    }
    code, body = post_json(endpoint, persist_env)
    assert code == 200, f"Expected 200 on persist_env, got {code}: {body}"
    (data_dir / "saved_persist_envelope.json").write_text(json.dumps(persist_env), encoding="utf-8")
    print(json.dumps({"phase1": "PASS", "dpapi_vault_bytes": len(raw_vault)}))

elif phase == "phase2":
    snap = call_ffi("dashboard_snapshot")
    assert snap.get("ok") is True, f"phase2 snapshot failed: {snap}"
    d = snap["data"]
    endpoint = d["bridge_endpoint"]

    assert d["performance"]["active_mode"] == "HIGH_QUALITY", f"F07 settings lost on reopen: {d['performance']}"
    assert d["clipboard"]["policy"]["allow_files"] is False, f"F07 clipboard policy lost: {d['clipboard']}"
    assert d["transfer_queue"]["bandwidth_limit_kbps"] == 4096, f"F07 bandwidth lost: {d['transfer_queue']}"
    assert d["notifications"]["unread_count"] >= 4, f"F07 notification journal lost: {d['notifications']}"

    ver_ok = call_ffi("verify_step_up_pin", {"pin": "WinVault#2026", "scope": "POWER_CONTROL"})
    assert ver_ok.get("ok") is True, f"DPAPI reopen verify_step_up_pin failed: {ver_ok}"
    hijack = call_ffi("set_step_up_pin", {"pin": "Hijack#9999"})
    assert hijack.get("ok") is False and "SECURITY_DENY_CURRENT_PIN_REQUIRED" in hijack.get("error", ""), f"F05 overwrite not blocked: {hijack}"
    bad_rot = call_ffi("change_step_up_pin", {"current_pin": "Wrong#0000", "new_pin": "Rotated#2027"})
    assert bad_rot.get("ok") is False, f"Wrong current PIN allowed rotation: {bad_rot}"
    good_rot = call_ffi("change_step_up_pin", {"current_pin": "WinVault#2026", "new_pin": "Rotated#2027"})
    assert good_rot.get("ok") is True, f"Authenticated PIN rotation failed: {good_rot}"
    grant_res = call_ffi("verify_step_up_pin", {"pin": "Rotated#2027", "scope": "SHUTDOWN"})
    assert grant_res.get("ok") is True and grant_res["data"].get("token_id"), f"Missing token_id: {grant_res}"
    tok_ok = call_ffi("verify_step_up_token", {"token_id": grant_res["data"]["token_id"], "scope": "SHUTDOWN"})
    assert tok_ok.get("ok") is True, f"Grant token verification failed: {tok_ok}"

    saved_env = json.loads((data_dir / "saved_persist_envelope.json").read_text(encoding="utf-8"))
    rep_code, rep_body = post_json(endpoint, saved_env)
    assert rep_code == 401, f"F09 cross-restart replay was not rejected (got {rep_code}: {rep_body})"

    now_ms = int(time.time() * 1000)
    base_evt = {
        "event_id": "evt-f01-matrix",
        "timestamp": "2026-11-26T00:01:00Z",
        "source": "claude_code",
        "device_id": "WIN-SANDBOX",
        "project_id": "DAUVERSE-RC3",
        "task_id": "f01-task",
        "task_name": "Original Task Name",
        "event_type": "TASK_COMPLETED",
        "status": "COMPLETED",
        "severity": "SUCCESS",
        "progress": 100.0,
        "summary": "Original verified summary",
        "artifact_reference": "orig.zip",
        "confidence": 1.0,
        "provenance": {
            "adapter_type": "OFFICIAL_HOOK",
            "evidence_verified": True,
            "exit_code": 0,
            "evidence_badge": "EXIT_0",
        },
    }
    valid_sig = sign_v3(base_evt, now_ms, "f01nonce00000001")
    neighbor_f32 = struct.unpack(">f", struct.pack(">I", 0x42c80001))[0]
    mutations = [
        ("task_name", lambda e: e.update({"task_name": "Tampered Task"})),
        ("summary", lambda e: e.update({"summary": "Tampered Summary"})),
        ("severity", lambda e: e.update({"severity": "CRITICAL"})),
        ("progress", lambda e: e.update({"progress": 12.5})),
        ("progress_f32_neighbor_0x42c80001", lambda e: e.update({"progress": neighbor_f32})),
        ("artifact_reference", lambda e: e.update({"artifact_reference": "evil.exe"})),
        ("confidence", lambda e: e.update({"confidence": 0.25})),
        ("provenance.adapter_type", lambda e: e["provenance"].update({"adapter_type": "APPROVED_WRAPPER_ADAPTER"})),
        ("provenance.evidence_verified", lambda e: e["provenance"].update({"evidence_verified": False})),
        ("provenance.exit_code", lambda e: e["provenance"].update({"exit_code": 1})),
        ("provenance.evidence_badge", lambda e: e["provenance"].update({"evidence_badge": "SPOOFED"})),
    ]
    for field_name, mut_fn in mutations:
        cloned = json.loads(json.dumps(base_evt))
        mut_fn(cloned)
        c_code, _ = post_json(endpoint, {
            "schema_version": 3,
            "event": cloned,
            "issued_at_ms": now_ms,
            "nonce": "f01nonce00000001",
            "signature_hex": valid_sig,
        })
        assert c_code == 401, f"F01 field mutation '{field_name}' was NOT rejected! HTTP {c_code}"

    for legacy_ver in (1, 2):
        v_code, _ = post_json(endpoint, {
            "schema_version": legacy_ver,
            "event": base_evt,
            "issued_at_ms": now_ms,
            "nonce": f"v{legacy_ver}nonce00000001",
            "signature_hex": valid_sig,
        })
        assert v_code == 401, f"Schema v{legacy_ver} was NOT rejected! HTTP {v_code}"

    untrusted_evt = json.loads(json.dumps(base_evt))
    untrusted_evt["event_id"] = "evt-untrusted-src"
    untrusted_evt["source"] = "claude_desktop"
    untrusted_sig = sign_v3(untrusted_evt, now_ms, "untrustednonce01")
    untrusted_code, _ = post_json(endpoint, {
        "schema_version": 3,
        "event": untrusted_evt,
        "issued_at_ms": now_ms,
        "nonce": "untrustednonce01",
        "signature_hex": untrusted_sig,
    })
    assert untrusted_code == 401, f"Untrusted source claiming OFFICIAL_HOOK was NOT rejected! HTTP {untrusted_code}"

    hl_deny = call_ffi("headless_activate", {})
    assert hl_deny.get("ok") is False, f"F04 unapproved headless_activate must fail: {hl_deny}"
    hl_snap = call_ffi("dashboard_snapshot")["data"]["headless"]
    assert hl_snap["virtual_display_active"] is False, f"F04 virtual_display_active falsely True: {hl_snap}"
    assert hl_snap["operational_status"] == "BLOCKED_APPROVAL_REQUIRED", f"Unexpected headless status: {hl_snap}"
    wdk_req = call_ffi("headless_request_driver", {"whql_signed": False, "self_signed_root": True, "boss_approved": True, "step_up_pin": "Rotated#2027"})
    assert wdk_req.get("ok") is False, f"WDKTestCert rustdesk_idd must stay blocked: {wdk_req}"

    perf = call_ffi("dashboard_snapshot")["data"]["performance"]
    assert perf.get("measured_fps") is None and "fps" not in perf, f"F10 synthetic FPS leaked: {perf}"
    assert perf["configured_target_fps"] > 0

    bench = call_ffi("run_benchmark")
    assert bench.get("ok") is True and bench["data"]["hmac_iterations"] == 200, f"N01 benchmark failed: {bench}"

    unsigned_pkg = data_dir / "fake_update.exe"
    unsigned_pkg.write_bytes(b"MZ" + b"\x00" * 512)
    pkg_sha = hashlib.sha256(unsigned_pkg.read_bytes()).hexdigest()
    upd = call_ffi("verify_update_package", {
        "artifact_path": str(unsigned_pkg),
        "descriptor": {
            "version": "1.0.1",
            "download_url": "https://example.invalid/update.exe",
            "expected_sha256": pkg_sha,
            "signature_status": "VERIFIED_TRUSTED_PUBLISHER",
            "release_notes_vi": "RC3 test descriptor",
        },
    })
    assert upd["ok"] is True and upd["data"]["safe_for_auto_update"] is False, f"F12 spoofed publisher allowed auto-update: {upd}"
    assert upd["data"]["signature_status"] in ("UNSIGNED_BUILD", "UNVERIFIED_PUBLISHER"), f"F12 expected UNSIGNED_BUILD, got: {upd}"

    wol_dry = call_ffi("smart_power_action", {
        "operation": "WAKE_ON_LAN",
        "dry_run": True,
        "step_up_pin": "Rotated#2027",
        "mac": "AA:BB:CC:DD:EE:FF",
        "target": "127.0.0.1:9",
    })
    assert wol_dry["ok"] is True and wol_dry["data"]["executed"] is False, f"F13 dry-run failed: {wol_dry}"

    rx_root = data_dir / "rx_confined"
    rx_root.mkdir(parents=True, exist_ok=True)
    good_rx = rx_root / "verified_payload.bin"
    good_bytes = b"DAUVERSE_RC3_VERIFIED_TRANSFER_PAYLOAD\n" * 64
    good_rx.write_bytes(good_bytes)
    good_sha = hashlib.sha256(good_bytes).hexdigest()

    assert call_ffi("transfer_track_receive", {
        "engine_job_id": 701,
        "conn_id": 1,
        "dest_dir": str(rx_root),
        "file_specs": [{
            "relative_path": "verified_payload.bin",
            "expected_bytes": len(good_bytes),
            "expected_sha256": good_sha,
        }],
        "total_bytes": len(good_bytes),
    })["ok"] is True
    fin_good = call_ffi("transfer_finalize_receive", {"engine_job_id": 701})
    assert fin_good["ok"] is True and fin_good["data"].get("verified_sha256") == good_sha, f"F16 valid finalize failed: {fin_good}"

    assert call_ffi("transfer_track_receive", {
        "engine_job_id": 702,
        "conn_id": 1,
        "dest_dir": str(rx_root),
        "files": ["verified_payload.bin"],
        "total_bytes": len(good_bytes),
    })["ok"] is True
    fin_nodigest = call_ffi("transfer_finalize_receive", {"engine_job_id": 702})
    assert fin_nodigest["ok"] is False, f"F16 missing sender SHA256 was not rejected: {fin_nodigest}"

    mut_rx = rx_root / "mutated_same_len.bin"
    mut_rx.write_bytes(b"BBBB")
    assert call_ffi("transfer_track_receive", {
        "engine_job_id": 703,
        "conn_id": 1,
        "dest_dir": str(rx_root),
        "file_specs": [{
            "relative_path": "mutated_same_len.bin",
            "expected_bytes": 4,
            "expected_sha256": hashlib.sha256(b"AAAA").hexdigest(),
        }],
        "total_bytes": 4,
    })["ok"] is True
    assert call_ffi("transfer_finalize_receive", {"engine_job_id": 703})["ok"] is False

    (rx_root / "comp_a.bin").write_bytes(b"XX")
    (rx_root / "comp_b.bin").write_bytes(b"YYYYYYYY")
    assert call_ffi("transfer_track_receive", {
        "engine_job_id": 704,
        "conn_id": 1,
        "dest_dir": str(rx_root),
        "file_specs": [
            {"relative_path": "comp_a.bin", "expected_bytes": 4, "expected_sha256": hashlib.sha256(b"XX").hexdigest()},
            {"relative_path": "comp_b.bin", "expected_bytes": 6, "expected_sha256": hashlib.sha256(b"YYYYYYYY").hexdigest()},
        ],
        "total_bytes": 10,
    })["ok"] is True
    assert call_ffi("transfer_finalize_receive", {"engine_job_id": 704})["ok"] is False

    for _ in range(5):
        w = call_ffi("verify_step_up_pin", {"pin": "Wrong#9999", "scope": "POWER_CONTROL"})
        assert w["ok"] is False
    locked = call_ffi("verify_step_up_pin", {"pin": "Rotated#2027", "scope": "POWER_CONTROL"})
    assert locked["ok"] is False and "LOCKED" in locked.get("error", "").upper(), f"F05 lockout did not trigger: {locked}"

    print(json.dumps({
        "phase2": "PASS",
        "dpapi_reopen_verified": True,
        "settings_persisted": True,
        "cross_restart_replay_http": rep_code,
        "f01_field_mutations_rejected": len(mutations),
        "headless_operational_status": hl_snap["operational_status"],
        "update_guard_effective_status": upd["data"]["signature_status"],
        "f16_verified_state": fin_good["data"].get("integrity_state"),
        "f05_lockout_verified": True,
    }))

elif phase == "phase3_corrupt":
    sec = call_ffi("security_summary")["data"]["summary"]
    assert sec["vault_healthy"] is False, f"Expected vault_healthy False, got {sec}"
    set_try = call_ffi("set_step_up_pin", {"pin": "BypassAttempt#2026"})
    ver_try = call_ffi("verify_step_up_pin", {"pin": "Rotated#2027", "scope": "POWER_CONTROL"})
    assert set_try["ok"] is False and "FAIL_CLOSED" in set_try.get("error", ""), f"set_try: {set_try}"
    assert ver_try["ok"] is False and "FAIL_CLOSED" in ver_try.get("error", ""), f"ver_try: {ver_try}"
    print(json.dumps({"phase3_corrupt_vault_fail_closed": "PASS"}))

elif phase == "phase4_corrupt_replay":
    snap = call_ffi("dashboard_snapshot")
    endpoint = snap["data"]["bridge_endpoint"]
    now_ms = int(time.time() * 1000)
    ev = {
        "event_id": "evt-corrupt-replay-1",
        "timestamp": "2026-11-26T00:05:00Z",
        "source": "codex_cli",
        "device_id": "WIN-SANDBOX",
        "project_id": "DAUVERSE-RC3",
        "task_id": "corrupt-replay",
        "task_name": "Corrupt Replay Probe",
        "event_type": "COMMAND_COMPLETED",
        "status": "COMPLETED",
        "severity": "SUCCESS",
        "progress": 100.0,
        "summary": "Must fail closed when replay journal is corrupted",
        "artifact_reference": None,
        "confidence": 1.0,
        "provenance": {
            "adapter_type": "OFFICIAL_HOOK",
            "evidence_verified": True,
            "exit_code": 0,
            "evidence_badge": None,
        },
    }
    sig = sign_v3(ev, now_ms, "corruptjournal01")
    code, body = post_json(endpoint, {
        "schema_version": 3,
        "event": ev,
        "issued_at_ms": now_ms,
        "nonce": "corruptjournal01",
        "signature_hex": sig,
    })
    assert code in (401, 503) and body.get("ok") is False, f"F09 corrupted replay journal did NOT fail closed: {code} {body}"
    print(json.dumps({"phase4_corrupt_replay_fail_closed": "PASS", "http_status": code}))
'@

    $PyTempFile = Join-Path $env:TEMP "dauverse_win_rc3_matrix.py"
    $SharedVaultDir = Join-Path $env:TEMP ("dauverse_win_dpapi_rc3_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $SharedVaultDir | Out-Null
    Set-Content -LiteralPath $PyTempFile -Value $PyWorker -Encoding UTF8

    try {
        $P1Out = & python $PyTempFile "phase1" $ExpectedInstallDir $RepoRoot $SharedVaultDir
        Assert-Condition ($LASTEXITCODE -eq 0) "Windows FFI phase1 failed with exit code $LASTEXITCODE"
        $Phase1Res = $P1Out | Select-Object -Last 1 | ConvertFrom-Json

        $P2Out = & python $PyTempFile "phase2" $ExpectedInstallDir $RepoRoot $SharedVaultDir
        Assert-Condition ($LASTEXITCODE -eq 0) "Windows FFI phase2 reopen/matrix failed with exit code $LASTEXITCODE"
        $Phase2Res = $P2Out | Select-Object -Last 1 | ConvertFrom-Json

        $P3Out = & python $PyTempFile "phase3_corrupt" $ExpectedInstallDir $RepoRoot $SharedVaultDir
        Assert-Condition ($LASTEXITCODE -eq 0) "Windows FFI phase3 corrupt-vault check failed with exit code $LASTEXITCODE"
        $Phase3Res = $P3Out | Select-Object -Last 1 | ConvertFrom-Json

        $P4Out = & python $PyTempFile "phase4_corrupt_replay" $ExpectedInstallDir $RepoRoot $SharedVaultDir
        Assert-Condition ($LASTEXITCODE -eq 0) "Windows FFI phase4 corrupt-replay check failed with exit code $LASTEXITCODE"
        $Phase4Res = $P4Out | Select-Object -Last 1 | ConvertFrom-Json
    } finally {
        Remove-Item -LiteralPath $PyTempFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $SharedVaultDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "=== [5/7] Distinct-Binary Release Simulation + Negative (Tampered & Unlisted-Extra) & Positive Transactional Rollback (F11) ==="
    Stop-ProcessesUnderDir -DirPath $ExpectedInstallDir
    $PreUpgradeSentinel = Join-Path $ExpectedInstallDir "PRE_UPGRADE_SENTINEL.json"
    [System.IO.File]::WriteAllText($PreUpgradeSentinel, '{"slot":"PRE_UPGRADE_RELEASE_A"}', (New-Object System.Text.UTF8Encoding($false)))
    $PreSentinelHash = (Get-FileHash -LiteralPath $PreUpgradeSentinel -Algorithm SHA256).Hash.ToLowerInvariant()
    $InstalledDllPath = Join-Path $ExpectedInstallDir "librustdesk.dll"
    $PreUpgradeDllHash = (Get-FileHash -LiteralPath $InstalledDllPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $UpgradeProc = Start-Process -FilePath $SetupExe -ArgumentList "/S" -Wait -PassThru
    Assert-Condition ($UpgradeProc.ExitCode -eq 0) "Upgrade SETUP.exe /S exited with $($UpgradeProc.ExitCode) (helperDiag=$(Get-NsisHelperDiagTail))"

    $RollbackSnapshotDir = "${ExpectedInstallDir}.rollback_backup"
    Assert-Condition (Test-Path -LiteralPath (Join-Path $RollbackSnapshotDir "BACKUP_SHA256_MANIFEST.txt")) "Upgrade did not generate BACKUP_SHA256_MANIFEST.txt at $RollbackSnapshotDir"
    Assert-Condition (Test-Path -LiteralPath (Join-Path $RollbackSnapshotDir "PRE_UPGRADE_SENTINEL.json")) "Upgrade backup missing PRE_UPGRADE_SENTINEL.json"

    # Simulate distinct binary Release B (distinct PE binary SHA-256 on librustdesk.dll + post-upgrade sentinel)
    Remove-Item -LiteralPath $PreUpgradeSentinel -Force -ErrorAction SilentlyContinue
    $PostUpgradeSentinel = Join-Path $ExpectedInstallDir "POST_UPGRADE_SENTINEL.json"
    [System.IO.File]::WriteAllText($PostUpgradeSentinel, '{"slot":"POST_UPGRADE_RELEASE_B"}', (New-Object System.Text.UTF8Encoding($false)))
    $OrigDllBytes = [System.IO.File]::ReadAllBytes($InstalledDllPath)
    $DistinctReleaseBDllBytes = New-Object byte[] ($OrigDllBytes.Length + 64)
    [System.Array]::Copy($OrigDllBytes, 0, $DistinctReleaseBDllBytes, 0, $OrigDllBytes.Length)
    $TagBytes = [System.Text.Encoding]::ASCII.GetBytes("DAUVERSE_DISTINCT_RELEASE_B_OVERLAY_MARKER")
    [System.Array]::Copy($TagBytes, 0, $DistinctReleaseBDllBytes, $OrigDllBytes.Length, $TagBytes.Length)
    [System.IO.File]::WriteAllBytes($InstalledDllPath, $DistinctReleaseBDllBytes)
    $PostUpgradeDllHash = (Get-FileHash -LiteralPath $InstalledDllPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Condition ($PostUpgradeDllHash -ne $PreUpgradeDllHash) "Simulated Release B binary hash must differ from Release A!"

    $RollbackScript = Join-Path $RepoRoot "scripts\windows\rollback_windows_release.ps1"

    # Negative Rollback Test 1: Tampered listed file MUST fail pre-validation BEFORE mutating $ExpectedInstallDir
    $TamperedBackupDir = "${ExpectedInstallDir}.rollback_tampered_test"
    if (Test-Path -LiteralPath $TamperedBackupDir) { Remove-Item -LiteralPath $TamperedBackupDir -Recurse -Force }
    Copy-Item -LiteralPath $RollbackSnapshotDir -Destination $TamperedBackupDir -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $TamperedBackupDir "PRE_UPGRADE_SENTINEL.json"), '{"slot":"CORRUPTED_BY_TAMPER"}', (New-Object System.Text.UTF8Encoding($false)))
    $null = Assert-Throws "tampered_backup_rollback_refused" {
        & $RollbackScript -InstallDir $ExpectedInstallDir -BackupDir $TamperedBackupDir
    }
    Assert-Condition ((Test-Path -LiteralPath $PostUpgradeSentinel) -and ((Get-FileHash -LiteralPath $InstalledDllPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $PostUpgradeDllHash)) "F11_VIOLATION: Tampered rollback mutated active installation!"
    Remove-Item -LiteralPath $TamperedBackupDir -Recurse -Force -ErrorAction SilentlyContinue

    # Negative Rollback Test 2 (Codex Re-QA F11 exact repro): Unlisted extra file in backup MUST be rejected BEFORE mutating $ExpectedInstallDir
    $ExtraBackupDir = "${ExpectedInstallDir}.rollback_extra_test"
    if (Test-Path -LiteralPath $ExtraBackupDir) { Remove-Item -LiteralPath $ExtraBackupDir -Recurse -Force }
    Copy-Item -LiteralPath $RollbackSnapshotDir -Destination $ExtraBackupDir -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $ExtraBackupDir "unlisted-extra.bin"), "UNLISTED_PAYLOAD", (New-Object System.Text.UTF8Encoding($false)))
    $null = Assert-Throws "unlisted_backup_extra_rollback_refused" {
        & $RollbackScript -InstallDir $ExpectedInstallDir -BackupDir $ExtraBackupDir
    }
    Assert-Condition ((Test-Path -LiteralPath $PostUpgradeSentinel) -and (-not (Test-Path -LiteralPath (Join-Path $ExpectedInstallDir "unlisted-extra.bin")))) "F11_VIOLATION: Unlisted-extra rollback mutated active installation!"
    Remove-Item -LiteralPath $ExtraBackupDir -Recurse -Force -ErrorAction SilentlyContinue

    # Positive Transactional Rollback Test: Valid manifested backup restores exact Release A PE binary hash + PRE_UPGRADE_SENTINEL and leaves zero unlisted/manifest files
    & $RollbackScript -InstallDir $ExpectedInstallDir -BackupDir $RollbackSnapshotDir
    Assert-Condition (Test-Path -LiteralPath $PreUpgradeSentinel) "F11_VIOLATION: Rollback did not restore PRE_UPGRADE_SENTINEL.json!"
    Assert-Condition (-not (Test-Path -LiteralPath $PostUpgradeSentinel)) "F11_VIOLATION: Stale POST_UPGRADE_SENTINEL.json remained after rollback!"
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $ExpectedInstallDir "BACKUP_SHA256_MANIFEST.txt"))) "F11_VIOLATION: BACKUP_SHA256_MANIFEST.txt leaked into restored InstallDir!"
    Assert-Condition ((Get-FileHash -LiteralPath $PreUpgradeSentinel -Algorithm SHA256).Hash.ToLowerInvariant() -eq $PreSentinelHash) "Restored PRE_UPGRADE_SENTINEL.json SHA-256 mismatch!"
    Assert-Condition ((Get-FileHash -LiteralPath $InstalledDllPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $PreUpgradeDllHash) "Restored Release A librustdesk.dll SHA-256 mismatch!"
    Assert-Condition ((Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\RustDesk").ImagePath -eq $ExternalImgBefore) "F03_VIOLATION: Rollback disturbed external RustDesk service!"
    Remove-Item -LiteralPath $RollbackSnapshotDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($HasFixedE -and (Test-Path -LiteralPath "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release")) {
        Remove-Item -LiteralPath "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release" -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "=== [6/7] NSIS Silent Uninstaller + External RustDesk Preservation & Host Diff Audit (F03) ==="
    $UninstExe = Join-Path $ExpectedInstallDir "Uninstall.exe"
    $UninstProc = Start-Process -FilePath $UninstExe -ArgumentList "/S" -Wait -PassThru
    Assert-Condition ($UninstProc.ExitCode -eq 0) "NSIS Uninstall.exe /S launcher exited with $($UninstProc.ExitCode) (helperDiag=$(Get-NsisHelperDiagTail))"

    $ArpKey32 = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\DauverseRemoteDesktop"
    for ($w = 0; $w -lt 30; $w++) {
        if ((-not (Test-Path -LiteralPath $ArpKey64)) -and (-not (Test-Path -LiteralPath $ArpKey32)) -and (-not (Test-Path -LiteralPath (Join-Path $ExpectedInstallDir "DAUVERSE_REMOTE.exe")))) {
            break
        }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 2

    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $ExpectedInstallDir "DAUVERSE_REMOTE.exe"))) "DAUVERSE_REMOTE.exe still present after uninstall!"
    Assert-Condition (-not (Test-Path -LiteralPath $ArpKey64)) "64-bit ARP registry key still present after uninstall!"
    Assert-Condition (-not (Test-Path -LiteralPath $ArpKey32)) "WOW6432Node ARP registry key still present after uninstall!"
    foreach ($lnkCand in $StartMenuCandidates) {
        Assert-Condition (-not (Test-Path -LiteralPath $lnkCand)) "Start Menu shortcut still present after uninstall: $lnkCand"
    }

    $SvcAfterUninstall = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $SvcAfterUninstall) "F03_VIOLATION: Uninstall.exe /S deleted external RustDesk Windows Service!"
    $ExternalImgAfterUninstall = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\RustDesk").ImagePath
    Assert-Condition ($ExternalImgAfterUninstall -eq $ExternalImgBefore) "F03_VIOLATION: Uninstall.exe /S altered external RustDesk service ImagePath!"
    Assert-Condition ((Get-FileHash -LiteralPath $ExternalConfigFile -Algorithm SHA256).Hash.ToLowerInvariant() -eq $ExternalConfigShaBefore) "F03_VIOLATION: Uninstall.exe /S altered external RustDesk user config!"

    & sc.exe delete RustDesk | Out-Null
    for ($sw = 0; $sw -lt 10; $sw++) {
        if ($null -eq (Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 500
    }
    Remove-Item -LiteralPath $CoexistDir -Recurse -Force -ErrorAction SilentlyContinue

    Assert-Condition ($null -eq (Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue)) "Residual RustDesk service remained after fixture cleanup!"
    Assert-Condition ($null -eq (Get-Service -Name "DauverseRemoteService" -ErrorAction SilentlyContinue)) "Unexpected DauverseRemoteService registered during test!"

    $PostServices = @(Get-CimInstance Win32_Service | ForEach-Object { "$($_.Name)|$($_.PathName)" } | Sort-Object)
    $PostRootCerts = @(Get-ChildItem Cert:\LocalMachine\Root | Select-Object -ExpandProperty Thumbprint | Sort-Object)
    $PostHkcuRun = if (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run") {
        (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" | Out-String)
    } else { "" }

    $AddedServices = @(
        Compare-Object -ReferenceObject $PreServices -DifferenceObject $PostServices |
        Where-Object {
            $_.SideIndicator -eq "=>" -and
            ($_.InputObject -notmatch '^[A-Za-z0-9]+_[0-9a-fA-F]{4,}\|.*\\svchost\.exe\b')
        }
    )
    $AddedCerts    = @(Compare-Object -ReferenceObject $PreRootCerts -DifferenceObject $PostRootCerts | Where-Object { $_.SideIndicator -eq "=>" })
    Assert-Condition ($AddedServices.Count -eq 0) "Unexpected residual Windows Services after uninstall: $($AddedServices | Out-String)"
    Assert-Condition ($AddedCerts.Count -eq 0) "Unexpected residual Root Certificates after uninstall: $($AddedCerts | Out-String)"
    Assert-Condition ($PreHkcuRun -eq $PostHkcuRun) "HKCU Run registry values changed unexpectedly after uninstall!"

    Write-Host "=== [7/7] Emitting Scoped RC4 Verification Reports & Final Bidirectional SHA256_MANIFEST.txt ==="
    $ReportObj = [ordered]@{
        schema_version = 4
        task_id = "DREMOTE-V1-RC4-FOCUSED-CLOSURE-011"
        release_candidate = "RC4"
        verified_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        git_commit_sha = $GitSha
        submodule_hbb_common_sha = $SubmoduleSha
        runner_os = [System.Environment]::OSVersion.VersionString
        runner_session_id = $SessionId
        production_status = "LOCKED"
        scope_boundary = "SINGLE_HOST_DISPOSABLE_WINDOWS_RUNNER_ONLY_NOT_TWO_MACHINE_E2E"
        artifacts = [ordered]@{
            setup_exe = [ordered]@{
                name = "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe"
                size_bytes = $SetupSize
                sha256 = (Get-FileHash -LiteralPath $SetupExe -Algorithm SHA256).Hash.ToLowerInvariant()
                pe_machine = $SetupMachine
            }
            portable_exe = [ordered]@{
                name = "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe"
                size_bytes = $PortableSize
                sha256 = (Get-FileHash -LiteralPath $PortableExe -Algorithm SHA256).Hash.ToLowerInvariant()
                pe_machine = $PortableMachine
            }
            signing_status = $SigningText
            initial_build_manifest_entries_verified = $InitialManifestEntries
        }
        single_host_windows_gates = [ordered]@{
            negative_harness_selftest_cases = "$($NegResults.Count)/$($NegResults.Count) PASS"
            initial_manifest_and_original_build_log_verified = "PASS"
            external_rustdesk_coexistence_preserved_on_install_rollback_uninstall = "PASS"
            wdktestcert_rustdesk_idd_blocked = "PASS"
            usbmmidd_v2_whql_authenticode_status = $UsbCatStatus
            usbmmidd_v2_whql_signer = $UsbCatSubject
            usbmmidd_v2_catalog_validation = $CatalogValidationStatus
            usbmmidd_v2_license_txt_preserved = "PASS"
            cli_version_exact_1_5_3 = $CliVerOut
            shim_version_exact_1_5_3 = $ShimVerOut
            installed_win32_gui_5s_survived = $GuiAliveAfter5s
            installed_win32_loaded_dlls = $LoadedKeyDlls
            portable_self_extract_and_win32_gui_5s_survived = $PortableGuiSurvived
            dpapi_four_process_security_matrix = [ordered]@{
                phase1 = $Phase1Res
                phase2 = $Phase2Res
                phase3 = $Phase3Res
                phase4 = $Phase4Res
            }
            simulated_binary_overlay_rollback_helper_and_tamper_unlisted_refusal = "PASS_SIMULATED_BINARY_OVERLAY_PARTIAL_NATIVE"
            pre_post_host_services_certs_runkyes_clean = "PASS"
        }
        remaining_blocked_gates_requiring_two_host_or_physical_lab = @(
            "BLOCKED: Two-machine Windows 11 live Remote Desktop session (P2P / Relay / Reconnect / WASAPI Audio / Explorer File Copy)",
            "PARTIAL-NATIVE (F11): Distinct Release A -> Release B native installer upgrade and rollback pilot (single-build harness uses SIMULATED_BINARY_OVERLAY)",
            "BLOCKED: Physical monitorless RTX 3060 NVENC + authorized usbmmidd_v2 driver activation & reboot persistence",
            "BLOCKED: Hunonic SK02 hardware smart plug (DisabledSmartPlugAdapter retained by governance -- no public vendor API)"
        )
    }
    $ReportObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportJsonOut -Encoding UTF8

    $MdLines = @(
        "# WINDOWS RC4 VERIFICATION REPORT (SCOPED SINGLE-HOST RUNNER EVIDENCE)",
        "",
        "- **Task ID:** ``DREMOTE-V1-RC4-FOCUSED-CLOSURE-011`` (``RC4``)",
        "- **Git Commit SHA:** ``$GitSha`` (``libs/hbb_common``: ``$SubmoduleSha``)",
        "- **Verified UTC:** ``$($ReportObj.verified_at_utc)``",
        "- **Runner OS:** ``$($ReportObj.runner_os)`` (Session ``$SessionId``)",
        "- **Signing Status:** ``$SigningText``",
        "- **Production Status:** ``LOCKED`` (Developer CI verification -- awaiting Independent Codex Re-QA)",
        "",
        "## 1. Single-Host Native Windows Gates Executed (``PASS``)",
        "1. **Negative Harness Self-Tests (``F02``, ``FT010-B01``, ``FT010-Q01``):** ``PASS`` ($($NegResults.Count)/$($NegResults.Count) negative sentinels--missing file, missing initial manifest in final layout, bad SHA-256, duplicate entry, unlisted extra file, GUI early exits ``0/1/2``, missing DLL, missing/tiny/padded/complete-marker synthetic build logs, skipped-test marker--verified to fail closed).",
        "2. **Bidirectional Immutable Build Manifest & Multi-Marker Log (``F02``, ``F15``):** ``PASS`` (``INITIAL_BUILD_SHA256_MANIFEST.txt`` verified bidirectionally before testing; real ``WINDOWS_NATIVE_BUILD.log`` ordered stage and compiler/NSIS markers verified).",
        "3. **External RustDesk Coexistence & Ownership (``F03``):** ``PASS`` (Simulated external ``RustDesk`` service and config outside ``$ExpectedInstallDir`` survived ``SETUP.exe /S``, ``rollback_windows_release.ps1``, and ``Uninstall.exe /S`` untouched; real running RustDesk service coexistence remains ``BLOCKED`` pending lab guest).",
        "4. **Driver Authenticity & License Closure (``F04``, ``A02``):** ``PASS`` (``usbmmidd.cat`` ``Status=$UsbCatStatus``, signer ``$UsbCatSubject``, catalog check ``$CatalogValidationStatus``, ``usbmmidd_v2\License.txt`` preserved verbatim; zero ``WDKTestCert`` / ``RustDeskIddDriver``).",
        "5. **Startup & Win32 GUI Liveness (``F02``):** ``PASS`` (``DAUVERSE_REMOTE.exe --version`` == ``1.5.3``, ``rustdesk.exe --version`` == ``1.5.3``, both installed and portable Win32 GUI processes survived 5s with ``librustdesk.dll`` + ``flutter_windows.dll`` loaded; interactive GUI rendering remains pilot scope).",
        "6. **4-Process Windows DPAPI & Security Negative Matrix (``F01``, ``F04``, ``F05``, ``F07``, ``F09``, ``F10``, ``F12``, ``F13``, ``F14``, ``F16``, ``N01``):** ``PASS`` (DPAPI encrypt->exit->reopen decrypt; HMAC v3 lossless f32 tags + neighbor collision rejection + corrupt replay journal fail-closed + per-file sender SHA-256 & full-identity isolation).",
        "7. **Bidirectional Manifest-Only Rollback -- Simulated Overlay Helper Check (``F11``):** ``PASS (SIMULATED_BINARY_OVERLAY)`` (Tampered and unlisted-extra backups refused without mutating ``$ExpectedInstallDir``; valid manifested backup restored Release A ``librustdesk.dll`` SHA-256 cleanly; distinct two-release A->B->A native acceptance remains pilot scope).",
        "8. **Host Cleanliness Diff:** ``PASS`` (Zero residual Windows Services, Root Certificates, or ``HKCU Run`` entries).",
        "",
        "## 2. Gates Explicitly Retained as ``BLOCKED`` / ``PARTIAL-NATIVE`` (Not Claimed as Full ``PASS``)",
        "- **Two-Machine Live Remote Session:** ``BLOCKED`` in single-runner CI (requires two authorized Windows endpoints).",
        "- **Distinct Release A -> Release B Native Upgrade/Rollback Pilot (``F11``):** ``PARTIAL-NATIVE`` (single-build harness uses ``SIMULATED_BINARY_OVERLAY``; requires two distinct built releases).",
        "- **Physical Monitorless GPU & Authorized Driver Install:** ``BLOCKED`` by governance (no host driver installation without Boss approval).",
        "- **Hunonic SK02 Hardware Control:** ``BLOCKED`` (``DisabledSmartPlugAdapter`` retained; no public vendor API)."
    )
    $MdLines -join "`r`n" | Set-Content -LiteralPath $ReportMdOut -Encoding UTF8

    if ($TranscriptStarted) {
        Stop-Transcript | Out-Null
        $TranscriptStarted = $false
    }
    Copy-Item -LiteralPath $TempVerifyLog -Destination $VerifyLogOut -Force
    Remove-Item -LiteralPath $TempVerifyLog -Force -ErrorAction SilentlyContinue

    $null = Assert-ManifestFileValid -ManifestFilePath $InitialManifest -BaseDirectory $ReleaseDir -ManifestRole "Initial" -VerifyListedEntriesOnly
    $FinalManifestLines = New-ReleaseManifestLines -BaseDirectory $ReleaseDir -ManifestRole "Final"
    Set-Content -LiteralPath $ManifestTxt -Value $FinalManifestLines -Encoding UTF8
    $FinalVerifiedCount = Assert-ManifestFileValid -ManifestFilePath $ManifestTxt -BaseDirectory $ReleaseDir -ManifestRole "Final"
    Write-Host "=== ALL SINGLE-HOST WINDOWS RC4 GATES PASSED ($FinalVerifiedCount manifest entries verified) ==="
    Get-Content -LiteralPath $ManifestTxt
} finally {
    $PSNativeCommandUseErrorActionPreference = $false
    if ((Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue) -and (-not $PreexistingExternalRustDesk)) {
        $CurrImg = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\RustDesk" -ErrorAction SilentlyContinue).ImagePath
        if ($CurrImg -and $CurrImg.Contains($CoexistDir)) {
            & sc.exe stop RustDesk 2>$null | Out-Null
            & sc.exe delete RustDesk 2>$null | Out-Null
        }
    }
    if (Test-Path -LiteralPath $CoexistDir) {
        Remove-Item -LiteralPath $CoexistDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($TranscriptStarted) {
        Stop-Transcript | Out-Null
    }
    if (Test-Path -LiteralPath $TempVerifyLog) {
        Remove-Item -LiteralPath $TempVerifyLog -Force -ErrorAction SilentlyContinue
    }
}
