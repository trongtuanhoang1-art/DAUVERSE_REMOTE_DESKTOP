<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 -- Unified Complete Windows RC2 QA Archive Packager & Clean-Room Auditor
.DESCRIPTION
  Assembles the single self-contained deliverable DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip
  covering all 17 mandatory QA handoff items (Codex Sec. 4.3, Sec. 14 & Task DREMOTE-V1-REMEDIATION-005):
    - RELEASE/: SETUP.exe, PORTABLE.exe, librustdesk.dll, dylib_virtual_display.dll, usbmmidd_v2/ (incl. License.txt),
      SIGNING_STATUS.txt, BUILD_PROVENANCE.json, DRIVER_PROVENANCE_AND_LICENSE.json, INITIAL_BUILD_SHA256_MANIFEST.txt
    - LOGS/: WINDOWS_NATIVE_BUILD.log, WINDOWS_RC_VERIFICATION.log, GitHub Actions console logs
    - EVIDENCE/: WINDOWS_RC_VERIFICATION_REPORT.{json,md}, QA_HARNESS_NEGATIVE_SELFTEST.json, Linux preflight evidence
    - QA/: Original untouched DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md (SHA-256 f07b61ed...),
      FINDINGS_REMEDIATION_MATRIX.md, CODEX_REQA_WINDOWS_RC2_HANDOFF.md
    - DOCS/ & LICENSES/: FEATURE_ACCEPTANCE_MATRIX.md, HUONG_DAN_BOSS.md, LICENSE, LICENCE, THIRD_PARTY_NOTICES,
      LICENSE_COMPLIANCE_REPORT.md, UPSTREAM_MANIFEST.json, SBOM.spdx.json
    - BUNDLE/: Self-contained DAUVERSE_REMOTE_DESKTOP_V1_RC2.bundle verified in an empty git init --bare repo (exit 0)
    - SOURCE/: Complete clean corresponding source snapshot of HEAD + pinned libs/hbb_common submodule
    - SHA256_MANIFEST.txt: Bidirectional recursive manifest verified via clean-room extraction (0 missing, 0 unlisted)
#>
param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [Parameter(Mandatory = $true)][string]$OutputDir
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$RepoRoot      = (Resolve-Path -LiteralPath $RepoRoot).Path
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir     = (Resolve-Path -LiteralPath $OutputDir).Path

$ReleaseDir    = Join-Path $WorkspaceRoot "RELEASE"
$StagingAppDir = Join-Path $WorkspaceRoot "STAGING\DAUVERSE_REMOTE_APP"
$ExpectedCodexReportSha = "f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913"
$ExpectedCodexRc2ReQaReportSha = "c23d36e7d83b2fb1402238d8a8501b9de899fcd94b2774155b6a602fd77fb954"

function Assert-PackCondition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "PACKAGE_AUDIT_FAILED: $Message"
    }
}

$PackStage = Join-Path $WorkspaceRoot "TEMP\rc2_complete_qa_stage"
if (Test-Path -LiteralPath $PackStage) { Remove-Item -LiteralPath $PackStage -Recurse -Force }
foreach ($sub in @("RELEASE", "LOGS", "EVIDENCE", "EVIDENCE\LINUX_PREFLIGHT", "QA", "DOCS", "LICENSES", "BUNDLE", "SOURCE")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $PackStage $sub) | Out-Null
}

Write-Host "=== [1/5] Staging Release Binaries, Staged WHQL Driver Set, Provenance & Logs ==="
foreach ($relFile in @(
    "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe",
    "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe",
    "SIGNING_STATUS.txt",
    "BUILD_PROVENANCE.json",
    "DRIVER_PROVENANCE_AND_LICENSE.json",
    "INITIAL_BUILD_SHA256_MANIFEST.txt",
    "usbmmidd_v2_License.txt"
)) {
    $src = Join-Path $ReleaseDir $relFile
    Assert-PackCondition (Test-Path -LiteralPath $src) "Missing required release file: $src"
    Copy-Item -LiteralPath $src -Destination (Join-Path $PackStage "RELEASE\$relFile") -Force
}

foreach ($dllName in @("librustdesk.dll", "dylib_virtual_display.dll")) {
    $dllSrc = Join-Path $StagingAppDir $dllName
    Assert-PackCondition (Test-Path -LiteralPath $dllSrc) "Missing staged DLL for offline PE inspection: $dllSrc"
    Copy-Item -LiteralPath $dllSrc -Destination (Join-Path $PackStage "RELEASE\$dllName") -Force
}
Assert-PackCondition (Test-Path -LiteralPath (Join-Path $StagingAppDir "usbmmidd_v2\usbmmidd.cat")) "Missing staged usbmmidd_v2 directory"
Copy-Item -LiteralPath (Join-Path $StagingAppDir "usbmmidd_v2") -Destination (Join-Path $PackStage "RELEASE\usbmmidd_v2") -Recurse -Force

foreach ($logFile in @("WINDOWS_NATIVE_BUILD.log", "WINDOWS_RC_VERIFICATION.log")) {
    $lSrc = Join-Path $ReleaseDir $logFile
    Assert-PackCondition (Test-Path -LiteralPath $lSrc) "Missing required native log: $lSrc"
    Assert-PackCondition ((Get-Item -LiteralPath $lSrc).Length -ge 1024) "Native log unexpectedly small: $lSrc"
    Copy-Item -LiteralPath $lSrc -Destination (Join-Path $PackStage "LOGS\$logFile") -Force
}

$CiLogsDir = Join-Path $WorkspaceRoot "LOGS"
foreach ($ciConsoleLog in @("GITHUB_ACTIONS_BUILD_CONSOLE.log", "GITHUB_ACTIONS_VERIFY_CONSOLE.log")) {
    $cPath = Join-Path $CiLogsDir $ciConsoleLog
    if (Test-Path -LiteralPath $cPath) {
        Copy-Item -LiteralPath $cPath -Destination (Join-Path $PackStage "LOGS\$ciConsoleLog") -Force
    }
}

foreach ($evFile in @(
    "WINDOWS_RC_VERIFICATION_REPORT.json",
    "WINDOWS_RC_VERIFICATION_REPORT.md",
    "QA_HARNESS_NEGATIVE_SELFTEST.json"
)) {
    $eSrc = Join-Path $ReleaseDir $evFile
    Assert-PackCondition (Test-Path -LiteralPath $eSrc) "Missing verification evidence: $eSrc"
    Copy-Item -LiteralPath $eSrc -Destination (Join-Path $PackStage "EVIDENCE\$evFile") -Force
}

$RepoEvDir = Join-Path $RepoRoot "ARTIFACTS\evidence"
if (Test-Path -LiteralPath $RepoEvDir) {
    Get-ChildItem -LiteralPath $RepoEvDir -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $PackStage "EVIDENCE\LINUX_PREFLIGHT\$($_.Name)") -Force
    }
}

Write-Host "=== [2/5] Staging Original Codex QA Reports, Remediation Matrix, Handoff, Docs & Licenses ==="
$CodexReportSrc = Join-Path $RepoRoot "QA\DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md"
Assert-PackCondition (Test-Path -LiteralPath $CodexReportSrc) "Missing QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md"
$ActualCodexSha = (Get-FileHash -LiteralPath $CodexReportSrc -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-PackCondition ($ActualCodexSha -eq $ExpectedCodexReportSha) "Codex QA report SHA-256 mismatch! Expected $ExpectedCodexReportSha, got $ActualCodexSha"
Copy-Item -LiteralPath $CodexReportSrc -Destination (Join-Path $PackStage "QA\DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md") -Force

$CodexReQaReportSrc = Join-Path $RepoRoot "QA\DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md"
Assert-PackCondition (Test-Path -LiteralPath $CodexReQaReportSrc) "Missing QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md"
$ActualCodexReQaSha = (Get-FileHash -LiteralPath $CodexReQaReportSrc -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-PackCondition ($ActualCodexReQaSha -eq $ExpectedCodexRc2ReQaReportSha) "Codex RC2 Re-QA report SHA-256 mismatch! Expected $ExpectedCodexRc2ReQaReportSha, got $ActualCodexReQaSha"
Copy-Item -LiteralPath $CodexReQaReportSrc -Destination (Join-Path $PackStage "QA\DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md") -Force

$Rc3HandoffSrc = Join-Path $RepoRoot "DAUVERSE_REMOTE_V1_RC3_SOURCE_REVIEW_HANDOFF.md"
if (Test-Path -LiteralPath $Rc3HandoffSrc) {
    Copy-Item -LiteralPath $Rc3HandoffSrc -Destination (Join-Path $PackStage "QA\DAUVERSE_REMOTE_V1_RC3_SOURCE_REVIEW_HANDOFF.md") -Force
}

$MatrixSrc = Join-Path $RepoRoot "FINDINGS_REMEDIATION_MATRIX.md"
Assert-PackCondition (Test-Path -LiteralPath $MatrixSrc) "Missing FINDINGS_REMEDIATION_MATRIX.md"
Copy-Item -LiteralPath $MatrixSrc -Destination (Join-Path $PackStage "QA\FINDINGS_REMEDIATION_MATRIX.md") -Force

$ReQaHandoffSrc = Join-Path $RepoRoot "QA\CODEX_REQA_WINDOWS_RC2_HANDOFF.md"
Assert-PackCondition (Test-Path -LiteralPath $ReQaHandoffSrc) "Missing QA/CODEX_REQA_WINDOWS_RC2_HANDOFF.md"
Copy-Item -LiteralPath $ReQaHandoffSrc -Destination (Join-Path $PackStage "QA\CODEX_REQA_WINDOWS_RC2_HANDOFF.md") -Force

foreach ($docRel in @("FEATURE_ACCEPTANCE_MATRIX.md", "HUONG_DAN_BOSS.md")) {
    $dSrc = Join-Path $RepoRoot $docRel
    Assert-PackCondition (Test-Path -LiteralPath $dSrc) "Missing required doc: $dSrc"
    Copy-Item -LiteralPath $dSrc -Destination (Join-Path $PackStage "DOCS\$docRel") -Force
}
if (Test-Path -LiteralPath (Join-Path $RepoRoot "DOCS")) {
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot "DOCS") -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $PackStage "DOCS\$($_.Name)") -Force
    }
}

foreach ($licRel in @("LICENSE", "LICENCE", "THIRD_PARTY_NOTICES", "LICENSE_COMPLIANCE_REPORT.md", "UPSTREAM_MANIFEST.json", "SBOM.spdx.json")) {
    $licSrc = Join-Path $RepoRoot $licRel
    Assert-PackCondition (Test-Path -LiteralPath $licSrc) "Missing required license/SBOM file: $licSrc"
    Copy-Item -LiteralPath $licSrc -Destination (Join-Path $PackStage "LICENSES\$licRel") -Force
}
Copy-Item -LiteralPath (Join-Path $ReleaseDir "usbmmidd_v2_License.txt") -Destination (Join-Path $PackStage "LICENSES\usbmmidd_v2_License.txt") -Force

Write-Host "=== [3/5] Creating & Verifying Self-Contained Git Bundle + Exporting Clean Source & Submodule ==="
$BundlePath = Join-Path $PackStage "BUNDLE\DAUVERSE_REMOTE_DESKTOP_V1_RC2.bundle"
& git -C $RepoRoot bundle create $BundlePath HEAD --branches --tags
Assert-PackCondition ($LASTEXITCODE -eq 0) "git bundle create failed with exit code $LASTEXITCODE"

$BareVerifyDir = Join-Path $WorkspaceRoot "TEMP\rc2_bare_bundle_verify.git"
if (Test-Path -LiteralPath $BareVerifyDir) { Remove-Item -LiteralPath $BareVerifyDir -Recurse -Force }
& git init --bare $BareVerifyDir | Out-Null

$PrevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $BundleVerifyOut = (& git -C $BareVerifyDir bundle verify $BundlePath 2>&1 | Out-String)
    $BundleVerifyExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $PrevEap
}
Assert-PackCondition ($BundleVerifyExit -eq 0) "Self-contained git bundle verify FAILED in empty bare repo (exit $BundleVerifyExit): $BundleVerifyOut"
Remove-Item -LiteralPath $BareVerifyDir -Recurse -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllText((Join-Path $PackStage "BUNDLE\BUNDLE_BARE_VERIFY.txt"), $BundleVerifyOut, (New-Object System.Text.UTF8Encoding($false)))

$TempMainZip = Join-Path $WorkspaceRoot "TEMP\rc2_main_src.zip"
$TempSubZip  = Join-Path $WorkspaceRoot "TEMP\rc2_sub_hbb.zip"
if (Test-Path -LiteralPath $TempMainZip) { Remove-Item -LiteralPath $TempMainZip -Force }
if (Test-Path -LiteralPath $TempSubZip)  { Remove-Item -LiteralPath $TempSubZip -Force }

& git -C $RepoRoot archive --format=zip -o $TempMainZip HEAD
Assert-PackCondition ($LASTEXITCODE -eq 0) "git archive HEAD failed"
[System.IO.Compression.ZipFile]::ExtractToDirectory($TempMainZip, (Join-Path $PackStage "SOURCE"))
Remove-Item -LiteralPath $TempMainZip -Force

$SubDestDir = Join-Path $PackStage "SOURCE\libs\hbb_common"
if (Test-Path -LiteralPath $SubDestDir) { Remove-Item -LiteralPath $SubDestDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $SubDestDir | Out-Null
& git -C (Join-Path $RepoRoot "libs\hbb_common") archive --format=zip -o $TempSubZip HEAD
Assert-PackCondition ($LASTEXITCODE -eq 0) "git archive libs/hbb_common failed"
[System.IO.Compression.ZipFile]::ExtractToDirectory($TempSubZip, $SubDestDir)
Remove-Item -LiteralPath $TempSubZip -Force

Write-Host "=== [4/5] Generating Recursive SHA256_MANIFEST.txt & Zipping Complete RC2 Archive ==="
$StageRootNorm = (Resolve-Path -LiteralPath $PackStage).Path.TrimEnd('\')
$ManifestEntries = New-Object System.Collections.Generic.List[string]
$AllStageFiles = @(Get-ChildItem -LiteralPath $StageRootNorm -Recurse -File | Sort-Object FullName)
foreach ($f in $AllStageFiles) {
    Assert-PackCondition ((($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) "Reparse point / symlink forbidden in QA archive: $($f.FullName)"
    $relPosix = $f.FullName.Substring($StageRootNorm.Length).TrimStart('\').Replace('\', '/')
    if ($relPosix -ne "SHA256_MANIFEST.txt") {
        $sha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $ManifestEntries.Add("$sha  $relPosix")
    }
}
$ArchiveManifestPath = Join-Path $StageRootNorm "SHA256_MANIFEST.txt"
[System.IO.File]::WriteAllLines($ArchiveManifestPath, $ManifestEntries, (New-Object System.Text.UTF8Encoding($false)))

$ZipOutPath = Join-Path $OutputDir "DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip"
if (Test-Path -LiteralPath $ZipOutPath) { Remove-Item -LiteralPath $ZipOutPath -Force }

$ZipStream = [System.IO.File]::Open($ZipOutPath, [System.IO.FileMode]::Create)
try {
    $ZipArchive = New-Object System.IO.Compression.ZipArchive($ZipStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        $FilesToZip = @(Get-ChildItem -LiteralPath $StageRootNorm -Recurse -File | Sort-Object FullName)
        foreach ($zf in $FilesToZip) {
            $entryName = $zf.FullName.Substring($StageRootNorm.Length).TrimStart('\').Replace('\', '/')
            $entry = $ZipArchive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $inStream = [System.IO.File]::OpenRead($zf.FullName)
            try {
                $outStream = $entry.Open()
                try {
                    $inStream.CopyTo($outStream)
                } finally {
                    $outStream.Dispose()
                }
            } finally {
                $inStream.Dispose()
            }
        }
    } finally {
        $ZipArchive.Dispose()
    }
} finally {
    $ZipStream.Dispose()
}

Write-Host "=== [5/5] Clean-Room Extraction & Bidirectional Manifest + Bare Bundle Audit ==="
$CleanRoom = Join-Path $WorkspaceRoot "TEMP\rc2_cleanroom_audit"
if (Test-Path -LiteralPath $CleanRoom) { Remove-Item -LiteralPath $CleanRoom -Recurse -Force }
New-Item -ItemType Directory -Force -Path $CleanRoom | Out-Null

try {
    $ReadZip = [System.IO.Compression.ZipFile]::OpenRead($ZipOutPath)
    try {
        foreach ($entry in $ReadZip.Entries) {
            $ename = $entry.FullName
            Assert-PackCondition ((-not $ename.StartsWith("/")) -and (-not $ename.StartsWith("\")) -and (-not $ename.Contains("..")) -and ($ename -notmatch '^[A-Za-z]:')) "Unsafe ZIP entry path: $ename"
        }
    } finally {
        $ReadZip.Dispose()
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipOutPath, $CleanRoom)

    $CleanManifest = Join-Path $CleanRoom "SHA256_MANIFEST.txt"
    Assert-PackCondition (Test-Path -LiteralPath $CleanManifest) "SHA256_MANIFEST.txt missing in extracted clean-room"
    $CleanLines = @(Get-Content -LiteralPath $CleanManifest | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $ListedSet = @{}
    foreach ($cl in $CleanLines) {
        $clClean = $cl.TrimStart([char]0xFEFF)
        Assert-PackCondition ($clClean -match '^([0-9a-f]{64})\s\s(.+)$') "Malformed manifest line in clean-room: $clClean"
        $expH = $Matches[1]
        $relP = $Matches[2]
        Assert-PackCondition (-not $ListedSet.ContainsKey($relP)) "Duplicate manifest path in clean-room: $relP"
        $ListedSet[$relP] = $true
        $diskPath = Join-Path $CleanRoom ($relP.Replace('/', '\'))
        Assert-PackCondition (Test-Path -LiteralPath $diskPath) "MISSING file in clean-room extraction: $relP"
        $actH = (Get-FileHash -LiteralPath $diskPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-PackCondition ($actH -eq $expH) "MISMATCH in clean-room extraction for $relP ($actH vs $expH)"
    }

    $CleanRootNorm = (Resolve-Path -LiteralPath $CleanRoom).Path.TrimEnd('\')
    $DiskFiles = @(Get-ChildItem -LiteralPath $CleanRootNorm -Recurse -File)
    $Unlisted = @()
    foreach ($df in $DiskFiles) {
        $relDisk = $df.FullName.Substring($CleanRootNorm.Length).TrimStart('\').Replace('\', '/')
        if ($relDisk -ne "SHA256_MANIFEST.txt" -and (-not $ListedSet.ContainsKey($relDisk))) {
            $Unlisted += $relDisk
        }
    }
    Assert-PackCondition ($Unlisted.Count -eq 0) "UNLISTED unexpected files in clean-room ZIP: $($Unlisted -join ', ')"

    $CleanCodexSha = (Get-FileHash -LiteralPath (Join-Path $CleanRoom "QA\DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md") -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-PackCondition ($CleanCodexSha -eq $ExpectedCodexReportSha) "Clean-room Codex QA report hash mismatch!"

    $CleanBare = Join-Path $WorkspaceRoot "TEMP\rc2_cleanroom_bare.git"
    if (Test-Path -LiteralPath $CleanBare) { Remove-Item -LiteralPath $CleanBare -Recurse -Force }
    & git init --bare $CleanBare | Out-Null
    & git -C $CleanBare bundle verify (Join-Path $CleanRoom "BUNDLE\DAUVERSE_REMOTE_DESKTOP_V1_RC2.bundle") | Out-Null
    Assert-PackCondition ($LASTEXITCODE -eq 0) "Clean-room bare git bundle verify failed!"
    Remove-Item -LiteralPath $CleanBare -Recurse -Force -ErrorAction SilentlyContinue
} finally {
    Remove-Item -LiteralPath $CleanRoom -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $PackStage -Recurse -Force -ErrorAction SilentlyContinue
}

Copy-Item -LiteralPath (Join-Path $ReleaseDir "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe") -Destination (Join-Path $OutputDir "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe") -Force
Copy-Item -LiteralPath (Join-Path $ReleaseDir "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe") -Destination (Join-Path $OutputDir "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe") -Force

$ZipSha = (Get-FileHash -LiteralPath $ZipOutPath -Algorithm SHA256).Hash.ToLowerInvariant()
$SetupSha = (Get-FileHash -LiteralPath (Join-Path $OutputDir "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe") -Algorithm SHA256).Hash.ToLowerInvariant()
$PortSha  = (Get-FileHash -LiteralPath (Join-Path $OutputDir "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe") -Algorithm SHA256).Hash.ToLowerInvariant()

[System.IO.File]::WriteAllText("$ZipOutPath.sha256", "$ZipSha  DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip`n", (New-Object System.Text.UTF8Encoding($false)))
$OuterLines = @(
    "$ZipSha  DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip",
    "$SetupSha  DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe",
    "$PortSha  DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe"
)
[System.IO.File]::WriteAllLines((Join-Path $OutputDir "FINAL_HANDOFF_SHA256_MANIFEST.txt"), [string[]]$OuterLines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "=== COMPLETE RC2 QA ARCHIVE PACKAGED & CLEAN-ROOM VERIFIED ($($CleanLines.Count) inner files, 0 missing, 0 unlisted) ==="
Get-Content -LiteralPath (Join-Path $OutputDir "FINAL_HANDOFF_SHA256_MANIFEST.txt")
