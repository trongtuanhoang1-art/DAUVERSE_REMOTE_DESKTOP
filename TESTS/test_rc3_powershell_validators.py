#!/usr/bin/env python3
"""
DAUVERSE REMOTE DESKTOP V1 (RC3) — PowerShell Validator Closure & PS 5.1 Compatibility Suite
Exercises:
  - installer/nsis/dauverse_setup_helper.ps1 (`-Action CreateVerifiedBackup` — F11/F14)
  - scripts/windows/rollback_windows_release.ps1 (`Assert-BackupManifestIntegrity`, `Get-VerifiedManifestRelativeFiles` — F11)
  - scripts/windows/verify_and_package_windows_rc.ps1 (`Assert-ManifestFileValid`, `Assert-OriginalBuildLogValid` — F02)
  - scripts/hooks/dauverse_job_wrapper.ps1 (`ConvertTo-CanonicalF32Tag` — F01)
  - All repository `.ps1` scripts parsed for zero syntax errors and zero PS7-only `??` / `??=` operators (`F15`).
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def find_pwsh() -> str:
    pwsh = shutil.which("pwsh") or "/home/antigravity/.local/pwsh/pwsh"
    if not Path(pwsh).is_file():
        raise FileNotFoundError("PowerShell (pwsh) binary not found")
    return pwsh


PWSH_HARNESS = r"""
$ErrorActionPreference = "Stop"
$repo = $env:REPO_ROOT

function Import-GlobalFunctionsFromScript([string]$path, [string[]]$names) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Syntax errors in ${path}: $($errors | Out-String)"
    }
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($names -contains $fn.Name) {
            $globalDef = $fn.Extent.Text -replace ("^function\s+" + [regex]::Escape($fn.Name)), ("function global:" + $fn.Name)
            Invoke-Expression $globalDef
        }
    }
}

function New-SyntheticPeBytes([byte]$tagByte) {
    $buf = New-Object byte[] 512
    $buf[0] = 0x4D # 'M'
    $buf[1] = 0x5A # 'Z'
    $buf[0x3C] = 0x80
    $buf[0x80] = 0x50 # 'P'
    $buf[0x81] = 0x45 # 'E'
    $buf[0x82] = 0x00
    $buf[0x83] = 0x00
    $buf[0x84] = 0x64 # AMD64 (0x8664)
    $buf[0x85] = 0x86
    $buf[0x120] = $tagByte
    return $buf
}

# 1. Verify zero syntax errors AND zero PS7-only ?? / ??= operators across all repository .ps1 files
$psFiles = Get-ChildItem -LiteralPath $repo -Recurse -Filter "*.ps1" | Where-Object {
    $_.FullName -notmatch '[\\/](target|build|\.git)[\\/]'
}
foreach ($f in $psFiles) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Parse error in $($f.FullName): $($errors | Out-String)"
    }
    $ps7Tokens = @($tokens | Where-Object {
        $_.Kind -in @(
            [System.Management.Automation.Language.TokenKind]::QuestionQuestion,
            [System.Management.Automation.Language.TokenKind]::QuestionQuestionEquals
        )
    })
    if ($ps7Tokens.Count -gt 0) {
        throw "Windows PowerShell 5.1 incompatible operator found in $($f.FullName): $($ps7Tokens[0].Extent.Text) at line $($ps7Tokens[0].Extent.StartLineNumber)"
    }
}

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dv_rc3_ps_suite_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

try {
    # 2. F11: Create backup via dauverse_setup_helper.ps1 and verify bidirectional closure via rollback_windows_release.ps1
    $installDir = Join-Path $tmpRoot "DAUVERSE_INSTALL"
    New-Item -ItemType Directory -Force -Path (Join-Path $installDir "data") | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $installDir "DAUVERSE_REMOTE.exe"), (New-SyntheticPeBytes 0x11))
    [System.IO.File]::WriteAllBytes((Join-Path $installDir "librustdesk.dll"), (New-SyntheticPeBytes 0x22))
    [System.IO.File]::WriteAllText((Join-Path $installDir "data/app_meta.json"), '{"v":1}')

    & (Join-Path $repo "installer/nsis/dauverse_setup_helper.ps1") -Action "CreateVerifiedBackup" -InstallDir $installDir -HasFixedDriveE "0"
    if ($LASTEXITCODE -ne 0) {
        throw "dauverse_setup_helper.ps1 CreateVerifiedBackup failed with exit $LASTEXITCODE"
    }
    $backupDir = "${installDir}.rollback_backup"

    Import-GlobalFunctionsFromScript (Join-Path $repo "scripts/windows/rollback_windows_release.ps1") @(
        "Compute-FileSha256Hex",
        "Test-PeBinaryHeader",
        "Assert-BackupManifestIntegrity",
        "Get-VerifiedManifestRelativeFiles"
    )

    $count = Assert-BackupManifestIntegrity -DirectoryToVerify $backupDir
    if ($count -ne 3) {
        throw "Expected 3 verified backup files, got $count"
    }

    # Negative F11a (exact Codex Re-QA 006 finding): unlisted extra file in backup MUST be rejected
    $rogue = Join-Path $backupDir "unlisted-extra.dll"
    [System.IO.File]::WriteAllBytes($rogue, (New-SyntheticPeBytes 0x99))
    $rejectedExtra = $false
    try {
        $null = Assert-BackupManifestIntegrity -DirectoryToVerify $backupDir
    } catch {
        if ($_.Exception.Message -match "Unlisted extra file") {
            $rejectedExtra = $true
        } else {
            throw "Unexpected error for unlisted extra: $($_.Exception.Message)"
        }
    }
    if (-not $rejectedExtra) {
        throw "F11 REGRESSION: Assert-BackupManifestIntegrity accepted unlisted-extra.dll!"
    }
    Remove-Item -LiteralPath $rogue -Force

    # Negative F11b: Duplicate entry in BACKUP_SHA256_MANIFEST.txt MUST be rejected
    $manifestPath = Join-Path $backupDir "BACKUP_SHA256_MANIFEST.txt"
    $origManifest = [System.IO.File]::ReadAllText($manifestPath)
    $firstLine = ($origManifest -split "`r?`n")[0]
    [System.IO.File]::WriteAllText($manifestPath, "$origManifest`n$firstLine`n")
    $rejectedDup = $false
    try {
        $null = Assert-BackupManifestIntegrity -DirectoryToVerify $backupDir
    } catch {
        if ($_.Exception.Message -match "Duplicate manifest entry") {
            $rejectedDup = $true
        }
    }
    if (-not $rejectedDup) {
        throw "F11 REGRESSION: Assert-BackupManifestIntegrity accepted duplicate manifest entry!"
    }
    [System.IO.File]::WriteAllText($manifestPath, $origManifest)

    # 3. F02: Assert-ManifestFileValid & Assert-OriginalBuildLogValid in verify_and_package_windows_rc.ps1
    Import-GlobalFunctionsFromScript (Join-Path $repo "scripts/windows/verify_and_package_windows_rc.ps1") @(
        "Assert-Condition",
        "Assert-ManifestFileValid",
        "Assert-OriginalBuildLogValid"
    )

    $mRoot = Join-Path $tmpRoot "pkg_manifest"
    New-Item -ItemType Directory -Force -Path $mRoot | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $mRoot "a.txt"), [Text.Encoding]::UTF8.GetBytes("alpha"))
    $ha = (Get-FileHash -LiteralPath (Join-Path $mRoot "a.txt") -Algorithm SHA256).Hash.ToLowerInvariant()
    $mFile = Join-Path $mRoot "SHA256_MANIFEST.txt"
    [System.IO.File]::WriteAllText($mFile, "$ha  a.txt`n")
    $null = Assert-ManifestFileValid -ManifestFilePath $mFile -BaseDirectory $mRoot

    # Negative F02a: Unlisted rogue file on disk MUST fail Assert-ManifestFileValid
    [System.IO.File]::WriteAllBytes((Join-Path $mRoot "rogue_unlisted.exe"), [Text.Encoding]::UTF8.GetBytes("rogue"))
    $rejectedUnlistedPkg = $false
    try {
        $null = Assert-ManifestFileValid -ManifestFilePath $mFile -BaseDirectory $mRoot
    } catch {
        if ($_.Exception.Message -match "Unlisted extra file") {
            $rejectedUnlistedPkg = $true
        }
    }
    if (-not $rejectedUnlistedPkg) {
        throw "F02 REGRESSION: Assert-ManifestFileValid accepted unlisted rogue file!"
    }

    # Negative F02b: Synthetic 2KB padded log missing ordered real compiler stages MUST fail Assert-OriginalBuildLogValid
    $fakeLog = Join-Path $tmpRoot "fake_build.log"
    $pad = "x" * 2048
    [System.IO.File]::WriteAllText($fakeLog, "cargo build`nflutter build windows --release`nBUILD_WINDOWS_RC_DONE`n$pad")
    $rejectedSyntheticLog = $false
    try {
        Assert-OriginalBuildLogValid -LogPath $fakeLog
    } catch {
        $rejectedSyntheticLog = $true
    }
    if (-not $rejectedSyntheticLog) {
        throw "F02 REGRESSION: Assert-OriginalBuildLogValid accepted synthetic padded build log!"
    }

    # 4. F01: ConvertTo-CanonicalF32Tag in dauverse_job_wrapper.ps1 matches Rust/Python bit-for-bit & rejects -0.0
    Import-GlobalFunctionsFromScript (Join-Path $repo "scripts/hooks/dauverse_job_wrapper.ps1") @("ConvertTo-CanonicalF32Tag")
    $tag100 = ConvertTo-CanonicalF32Tag -Val ([single]100.0) -MinVal ([single]0.0) -MaxVal ([single]100.0)
    $tag095 = ConvertTo-CanonicalF32Tag -Val ([single]0.95) -MinVal ([single]0.0) -MaxVal ([single]1.0)
    if ($tag100 -ne "f32:42c80000") { throw "Expected f32:42c80000, got $tag100" }
    if ($tag095 -ne "f32:3f733333") { throw "Expected f32:3f733333, got $tag095" }

    $negZeroBits = [byte[]](0x00, 0x00, 0x00, 0x80)
    if (-not [System.BitConverter]::IsLittleEndian) { [Array]::Reverse($negZeroBits) }
    $negZeroSingle = [System.BitConverter]::ToSingle($negZeroBits, 0)
    $rejectedNegZero = $false
    try {
        $null = ConvertTo-CanonicalF32Tag -Val $negZeroSingle -MinVal ([single]0.0) -MaxVal ([single]100.0)
    } catch {
        if ($_.Exception.Message -match "NEGATIVE_ZERO") {
            $rejectedNegZero = $true
        }
    }
    if (-not $rejectedNegZero) {
        throw "F01 REGRESSION: ConvertTo-CanonicalF32Tag accepted IEEE-754 negative zero!"
    }

    Write-Output (@{
        status = "PASS"
        ps_files_checked = $psFiles.Count
        f11_backup_closure_verified = $true
        f02_manifest_and_build_log_validators_verified = $true
        f01_ps_canonical_f32_tags_verified = $true
    } | ConvertTo-Json -Compress)
} finally {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
"""


def main() -> None:
    pwsh = find_pwsh()
    env = os.environ.copy()
    env["REPO_ROOT"] = str(REPO_ROOT)
    proc = subprocess.run(
        [pwsh, "-NoProfile", "-Command", PWSH_HARNESS],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"PowerShell validator suite failed (exit {proc.returncode}):\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
    result = json.loads(proc.stdout.strip().splitlines()[-1])
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
