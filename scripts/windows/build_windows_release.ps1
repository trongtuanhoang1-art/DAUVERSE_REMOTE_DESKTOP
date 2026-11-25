<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 -- Reproducible One-Command Windows Native Build & Provenance Script (RC2)
.DESCRIPTION
  Remediates Codex Findings F02, F15 & A02:
    - Enforces strict $LASTEXITCODE checking on every external command (zero masked test/build failures).
    - Records explicit non-eligibility marker (TESTS_SKIPPED_NOT_RC_ELIGIBLE.txt) if -SkipTests is ever passed.
    - Verifies pinned SHA-256 digests for usbmmidd_v2.zip AND every staged member (usbmmidd.cat, usbmmIdd.inf,
      x64\usbmmIdd.dll, License.txt), preserving Amyuni Technologies Inc. License.txt verbatim.
    - Emits BUILD_PROVENANCE.json, DRIVER_PROVENANCE_AND_LICENSE.json, WINDOWS_NATIVE_BUILD.log,
      INITIAL_BUILD_SHA256_MANIFEST.txt, and SHA256_MANIFEST.txt.
    - Never installs drivers or Windows Services on the build host.
#>
param(
    [string]$WorkspaceRoot = "",
    [switch]$UseRepoTargetDir = $false,
    [switch]$SkipVcpkgInstall = $false,
    [switch]$SkipTests = $false,
    [switch]$AllowPortableAsSetupFallback = $false
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$StepName,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )
    Write-Host ">>> [$StepName]"
    $global:LASTEXITCODE = 0
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "BUILD/TEST STEP FAILED [$StepName] with non-zero exit code $LASTEXITCODE."
    }
}

function Test-FixedDiskDrive {
    param([string]$DriveLetterRoot)
    try {
        $di = [System.IO.DriveInfo]::new($DriveLetterRoot)
        return ($di.IsReady -and $di.DriveType -eq [System.IO.DriveType]::Fixed)
    } catch {
        return $false
    }
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    if (Test-FixedDiskDrive "E:\") {
        $WorkspaceRoot = "E:\DAUVERSE_REMOTE_DESKTOP"
    } else {
        $WorkspaceRoot = Join-Path $RepoRoot "_win_workspace"
    }
}

$Dirs = @("BUILD", "STAGING", "RELEASE", "TESTS", "QA", "DOCS", "ARTIFACTS", "LOGS", "CACHE", "TEMP", "BACKUP")
foreach ($d in $Dirs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $WorkspaceRoot $d) | Out-Null
}

$ReleaseDir = Join-Path $WorkspaceRoot "RELEASE"
Get-ChildItem -Path $ReleaseDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

if ($UseRepoTargetDir) {
    $CargoTargetDir = Join-Path $RepoRoot "target"
    Remove-Item Env:\CARGO_TARGET_DIR -ErrorAction SilentlyContinue
} else {
    $CargoTargetDir = Join-Path $WorkspaceRoot "BUILD\cargo-target"
    $env:CARGO_TARGET_DIR = $CargoTargetDir
}

$env:TEMP = Join-Path $WorkspaceRoot "TEMP"
$env:TMP = Join-Path $WorkspaceRoot "TEMP"
if (-not $env:VCPKG_ROOT) {
    $env:VCPKG_ROOT = Join-Path $WorkspaceRoot "CACHE\vcpkg"
}
$env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"

$ManifestXmlPath = Join-Path $RepoRoot "res\manifest.xml"
$ManifestXmlBackup = if (Test-Path $ManifestXmlPath) { Get-Content -Raw -Path $ManifestXmlPath } else { $null }

$LogFile = Join-Path $WorkspaceRoot ("LOGS\windows_build_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
$TranscriptActive = $false
Start-Transcript -Path $LogFile -Append | Out-Null
$TranscriptActive = $true

try {
    Write-Host "=== DAUVERSE REMOTE DESKTOP V1.0 -- WINDOWS NATIVE BUILD (RC2) ==="
    Write-Host "RepoRoot      : $RepoRoot"
    Write-Host "WorkspaceRoot : $WorkspaceRoot"
    Write-Host "CargoTarget   : $CargoTargetDir"
    Write-Host "VCPKG_ROOT    : $env:VCPKG_ROOT"

    foreach ($tool in @("cargo", "rustc", "flutter", "python", "git")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required build tool '$tool' was not found in PATH."
        }
    }

    Push-Location $RepoRoot

    # 1. Bootstrap pinned vcpkg (commit 9e593bb18ea69cc5095e012465dcd675a822ed0d from vcpkg.json)
    $VcpkgCommit = "9e593bb18ea69cc5095e012465dcd675a822ed0d"
    if (-not $SkipVcpkgInstall) {
        if (-not (Test-Path (Join-Path $env:VCPKG_ROOT ".git"))) {
            Invoke-Checked "Clone vcpkg" { git clone https://github.com/microsoft/vcpkg $env:VCPKG_ROOT }
        }
        Push-Location $env:VCPKG_ROOT
        try {
            Invoke-Checked "Fetch pinned vcpkg commit" { git fetch origin $VcpkgCommit }
            Invoke-Checked "Checkout pinned vcpkg commit" { git checkout $VcpkgCommit }
            if (-not (Test-Path ".\vcpkg.exe")) {
                Invoke-Checked "Bootstrap vcpkg.exe" { .\bootstrap-vcpkg.bat -disableMetrics }
            }
        } finally {
            Pop-Location
        }

        Invoke-Checked "Install vcpkg x64-windows-static dependencies" {
            & "$env:VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static --x-install-root="$env:VCPKG_ROOT\installed"
        }
    }
    $env:VCPKG_INSTALLED_ROOT = "$env:VCPKG_ROOT\installed"

    # 2. Resolve Flutter dependencies & generate flutter_rust_bridge bindings if absent on fresh clone
    Push-Location (Join-Path $RepoRoot "flutter")
    try {
        Invoke-Checked "flutter pub get" { & flutter pub get }
    } finally {
        Pop-Location
    }

    $GenBridgeDart = Join-Path $RepoRoot "flutter\lib\generated_bridge.dart"
    $GenBridgeRs   = Join-Path $RepoRoot "src\bridge_generated.rs"
    if ((-not (Test-Path $GenBridgeDart)) -or (-not (Test-Path $GenBridgeRs))) {
        Write-Host "[2b] Generating flutter_rust_bridge bindings for clean clone..." -ForegroundColor Cyan
        if (-not (Get-Command flutter_rust_bridge_codegen -ErrorAction SilentlyContinue)) {
            Invoke-Checked "Install cargo-expand 1.0.95" {
                & cargo install cargo-expand --version 1.0.95 --locked
            }
            Invoke-Checked "Install flutter_rust_bridge_codegen 1.80.1" {
                & cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked
            }
        }
        Invoke-Checked "Run flutter_rust_bridge_codegen" {
            & flutter_rust_bridge_codegen --rust-input "$RepoRoot\src\flutter_ffi.rs" --dart-output $GenBridgeDart --c-output "$RepoRoot\flutter\macos\Runner\bridge_generated.h"
        }
        Copy-Item -Force "$RepoRoot\flutter\macos\Runner\bridge_generated.h" "$RepoRoot\flutter\ios\Runner\bridge_generated.h"
    }
    if (Test-Path $GenBridgeDart) {
        $BridgeText = Get-Content -Raw -Path $GenBridgeDart
        if ($BridgeText.Contains("ffi.NativeFunction<ffi.Bool Function(DartPort")) {
            $BridgeText = $BridgeText.Replace(
                "ffi.NativeFunction<ffi.Bool Function(DartPort",
                "ffi.NativeFunction<ffi.Uint8 Function(DartPort"
            )
            Set-Content -Path $GenBridgeDart -Value $BridgeText -NoNewline
        }
    }

    # 3. Build Virtual Display dynamic library bridge (does NOT install driver on host)
    Push-Location (Join-Path $RepoRoot "libs\virtual_display\dylib")
    try {
        Invoke-Checked "Build dylib_virtual_display" { & cargo build --locked --release }
    } finally {
        Pop-Location
    }

    # 4. Build core Rust library with Flutter + Hardware Codec + NVIDIA RTX 3060 VRAM + DPAPI support
    Invoke-Checked "Build librustdesk.dll (flutter,hwcodec,vram)" {
        & cargo build --locked --features "flutter,hwcodec,vram" --lib --release
    }
    $DllPath = Join-Path $CargoTargetDir "release\librustdesk.dll"
    if (-not (Test-Path $DllPath)) {
        throw "Expected native library not found at $DllPath"
    }

    $CmakeExpectedDllDir = Join-Path $RepoRoot "target\release"
    $CmakeExpectedDll = Join-Path $CmakeExpectedDllDir "librustdesk.dll"
    if ($DllPath -ne $CmakeExpectedDll) {
        New-Item -ItemType Directory -Force -Path $CmakeExpectedDllDir | Out-Null
        Copy-Item -Force $DllPath $CmakeExpectedDll
    }

    # 5. Run Rust workspace base + dauverse:: & Flutter verification tests (F02: never mask skipped tests)
    if (-not $SkipTests) {
        Invoke-Checked "Rust base::fs unit & confined receive tests" {
            & cargo test --locked -p base --release --lib
        }
        Invoke-Checked "Rust dauverse:: unit & security negative tests" {
            & cargo test --locked --features "flutter,hwcodec,vram" --release --lib dauverse::
        }
        Push-Location (Join-Path $RepoRoot "flutter")
        try {
            Invoke-Checked "Flutter DAUVERSE UI & fail-closed tests" {
                & flutter test test/dauverse_ui_test.dart
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Warning "TESTS_SKIPPED: Marking output directory as NOT eligible for Release Candidate acceptance!"
        Set-Content -Path (Join-Path $ReleaseDir "TESTS_SKIPPED_NOT_RC_ELIGIBLE.txt") -Value "Tests were skipped via -SkipTests; verify_and_package_windows_rc.ps1 MUST reject this build." -Encoding UTF8
    }

    # 6. Build Flutter Windows x64 Release bundle
    Push-Location (Join-Path $RepoRoot "flutter")
    try {
        Invoke-Checked "flutter build windows --release" {
            & flutter build windows --release
        }
    } finally {
        Pop-Location
    }

    $FlutterReleaseDir = Join-Path $RepoRoot "flutter\build\windows\x64\runner\Release"
    $StagingAppDir = Join-Path $WorkspaceRoot "STAGING\DAUVERSE_REMOTE_APP"
    if (Test-Path $StagingAppDir) { Remove-Item -Recurse -Force $StagingAppDir }
    Copy-Item -Recurse -Force $FlutterReleaseDir $StagingAppDir
    Copy-Item -Force $DllPath (Join-Path $StagingAppDir "librustdesk.dll")

    $VirtDllPath = $null
    $VirtDllCandidates = @(
        (Join-Path $CargoTargetDir "release\dylib_virtual_display.dll"),
        (Join-Path $CargoTargetDir "release\deps\dylib_virtual_display.dll")
    )
    foreach ($vc in $VirtDllCandidates) {
        if (Test-Path $vc) {
            $VirtDllPath = $vc
            Copy-Item -Force $vc (Join-Path $StagingAppDir "dylib_virtual_display.dll")
            break
        }
    }
    if (-not $VirtDllPath) {
        throw "Expected dylib_virtual_display.dll was not produced."
    }

    # Stage Microsoft WHQL-signed usbmmidd_v2 virtual display files (A02: verify archive + member hashes + preserve License.txt)
    $UsbMmIddUrl = "https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip"
    $UsbMmIddZip = Join-Path $WorkspaceRoot "CACHE\usbmmidd_v2.zip"
    $ExpectedUsbMmIddSha256 = "629b51e9944762bae73948171c65d09a79595cf4c771a82ebc003fbba5b24f51"
    if (-not (Test-Path $UsbMmIddZip)) {
        Invoke-WebRequest -Uri $UsbMmIddUrl -OutFile $UsbMmIddZip
    }
    $ActualUsbSha = (Get-FileHash -Path $UsbMmIddZip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ActualUsbSha -ne $ExpectedUsbMmIddSha256) {
        throw "SECURITY_ABORT: usbmmidd_v2.zip SHA-256 mismatch! Expected $ExpectedUsbMmIddSha256, got $ActualUsbSha"
    }
    $UsbExtractDir = Join-Path $WorkspaceRoot "TEMP\usbmmidd_extract"
    if (Test-Path $UsbExtractDir) { Remove-Item -Recurse -Force $UsbExtractDir }
    Expand-Archive -Path $UsbMmIddZip -DestinationPath $UsbExtractDir -Force
    Remove-Item -Path (Join-Path $UsbExtractDir "usbmmidd_v2\Win32") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $UsbExtractDir "usbmmidd_v2\deviceinstaller64.exe"), (Join-Path $UsbExtractDir "usbmmidd_v2\deviceinstaller.exe"), (Join-Path $UsbExtractDir "usbmmidd_v2\usbmmidd.bat") -Force -ErrorAction SilentlyContinue

    $PinnedDriverMembers = [ordered]@{
        "usbmmidd.cat"    = "470149c4cf9970ba59070aa7c9409c9f63a15727de99bab53e7e51f55310779f"
        "usbmmIdd.inf"    = "a8750ca15a86742f3012886c9932bb974158cd2d9779cf891c730d976a47726a"
        "x64\usbmmIdd.dll"= "dc135d675127113915a7e5aa9fe57c84edad6be41d0890b265ef124ab26ea9e3"
        "License.txt"     = "44c73fc4110979899dbb5054662de581f7d4350939f19bb2d50574f613314ba2"
    }
    foreach ($relMember in $PinnedDriverMembers.Keys) {
        $memberPath = Join-Path (Join-Path $UsbExtractDir "usbmmidd_v2") $relMember
        if (-not (Test-Path -LiteralPath $memberPath)) {
            throw "SECURITY_ABORT: Expected usbmmidd_v2 member missing: $relMember"
        }
        $actualMemberSha = (Get-FileHash -LiteralPath $memberPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedMemberSha = $PinnedDriverMembers[$relMember]
        if ($actualMemberSha -ne $expectedMemberSha) {
            throw "SECURITY_ABORT: usbmmidd_v2 member '$relMember' SHA-256 mismatch! Expected $expectedMemberSha, got $actualMemberSha"
        }
    }

    Copy-Item -Recurse -Force (Join-Path $UsbExtractDir "usbmmidd_v2") (Join-Path $StagingAppDir "usbmmidd_v2")
    Copy-Item -Force (Join-Path $StagingAppDir "usbmmidd_v2\License.txt") (Join-Path $ReleaseDir "usbmmidd_v2_License.txt")

    # Preserve rustdesk.exe shim for owned service compatibility AND provide DAUVERSE_REMOTE.exe entrypoint
    if (Test-Path (Join-Path $StagingAppDir "rustdesk.exe")) {
        Copy-Item -Force (Join-Path $StagingAppDir "rustdesk.exe") (Join-Path $StagingAppDir "DAUVERSE_REMOTE.exe")
    }

    # 7. Build Portable Single-File Executable (DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe)
    $PortableOut = Join-Path $ReleaseDir "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe"
    if ($null -ne $ManifestXmlBackup) {
        $FilteredManifest = ($ManifestXmlBackup -split "`r?`n" | Where-Object { $_ -notmatch "dpiAware" }) -join "`r`n"
        Set-Content -Path $ManifestXmlPath -Value $FilteredManifest -Encoding UTF8
    }
    Push-Location (Join-Path $RepoRoot "libs\portable")
    try {
        Invoke-Checked "pip install portable packer requirements" {
            & python -m pip install -r requirements.txt
        }
        Invoke-Checked "Generate single-file portable executable" {
            & python .\generate.py -f $StagingAppDir -o . -e (Join-Path $StagingAppDir "rustdesk.exe")
        }
    } finally {
        Pop-Location
    }

    $PackerExe = Join-Path $CargoTargetDir "release\rustdesk-portable-packer.exe"
    if (-not (Test-Path $PackerExe)) {
        $PackerExe = Join-Path $RepoRoot "target\release\rustdesk-portable-packer.exe"
    }
    if (-not (Test-Path $PackerExe)) {
        throw "Portable packer executable was not produced at $PackerExe"
    }
    Copy-Item -Force $PackerExe $PortableOut

    # 8. Build Windows Setup Installer (DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe via NSIS makensis.exe)
    $SetupOut = Join-Path $ReleaseDir "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe"
    $MakensisPath = $null
    $MakensisCmd = Get-Command "makensis.exe" -ErrorAction SilentlyContinue
    if ($MakensisCmd) {
        $MakensisPath = $MakensisCmd.Source
    } else {
        foreach ($cand in @("C:\Program Files (x86)\NSIS\makensis.exe", "C:\Program Files\NSIS\makensis.exe")) {
            if (Test-Path $cand) {
                $MakensisPath = $cand
                break
            }
        }
    }

    $FallbackSetupUsed = $false
    $MakensisVersion = "NONE"
    if ($MakensisPath) {
        $MakensisVersion = (& $MakensisPath /VERSION | Out-String).Trim()
        $NsiScript = Join-Path $RepoRoot "installer\nsis\dauverse_setup.nsi"
        Invoke-Checked "Compile NSIS Setup Installer" {
            & $MakensisPath "/WX" "/V3" "/DSTAGING_DIR=$StagingAppDir" "/DOUT_FILE=$SetupOut" $NsiScript
        }
    } elseif ($AllowPortableAsSetupFallback) {
        $FallbackSetupUsed = $true
        Write-Warning "NSIS not found and -AllowPortableAsSetupFallback specified; copying portable binary to SETUP.exe (NOT RC ELIGIBLE)."
        Copy-Item -Force $PortableOut $SetupOut
    } else {
        throw "NSIS (makensis.exe) not found in PATH or Program Files. Install NSIS or pass -AllowPortableAsSetupFallback explicitly."
    }

    # 9. Code Signing Status Check (Never fake signatures!)
    $SigningStatusPath = Join-Path $ReleaseDir "SIGNING_STATUS.txt"
    if ($env:CERT_PFX_PATH -and $env:CERT_PFX_PASSWORD -and (Test-Path $env:CERT_PFX_PATH)) {
        Write-Host "Signing executables with provided Authenticode certificate..."
        foreach ($bin in @($PortableOut, $SetupOut)) {
            Invoke-Checked "Authenticode signtool ($($bin | Split-Path -Leaf))" {
                & signtool.exe sign /fd SHA256 /f $env:CERT_PFX_PATH /p $env:CERT_PFX_PASSWORD /tr http://timestamp.digicert.com /td SHA256 $bin
            }
        }
        Set-Content -Path $SigningStatusPath -Value "SIGNED_AUTHENTICODE -- Signed with caller-provided PFX certificate." -Encoding UTF8
    } else {
        Write-Host "CODE SIGNING STATUS: UNSIGNED (No CERT_PFX_PATH provided -- marked honestly per Section 27)."
        Set-Content -Path $SigningStatusPath -Value "UNSIGNED -- Built cleanly from source without Authenticode PFX certificate. Auto-update is disabled; verify SHA256_MANIFEST.txt before installation." -Encoding UTF8
    }

    # 10. Emit Driver Provenance & License Attestation + Reproducible Build Provenance (F15, A02)
    $UsbCatSig = Get-AuthenticodeSignature -LiteralPath (Join-Path $StagingAppDir "usbmmidd_v2\usbmmidd.cat")
    $DriverProv = [ordered]@{
        driver_package = "usbmmidd_v2"
        vendor_copyright = "Copyright (c) 2020-2021 Amyuni Technologies Inc. All rights reserved."
        staging_archive_url = $UsbMmIddUrl
        staging_archive_sha256 = $ActualUsbSha
        staged_only_never_auto_installed = $true
        wdktestcert_rustdesk_idd_excluded = $true
        authenticode_catalog_status = [string]$UsbCatSig.Status
        authenticode_catalog_status_message = [string]$UsbCatSig.StatusMessage
        authenticode_signer_subject = if ($UsbCatSig.SignerCertificate) { $UsbCatSig.SignerCertificate.Subject } else { "NONE" }
        authenticode_signer_thumbprint = if ($UsbCatSig.SignerCertificate) { $UsbCatSig.SignerCertificate.Thumbprint } else { "NONE" }
        pinned_member_sha256 = $PinnedDriverMembers
        license_file_preserved = "usbmmidd_v2/License.txt"
        license_verbatim_text = (Get-Content -Raw -LiteralPath (Join-Path $StagingAppDir "usbmmidd_v2\License.txt"))
    }
    $DriverProv | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $ReleaseDir "DRIVER_PROVENANCE_AND_LICENSE.json") -Encoding UTF8

    $GitHeadSha = (& git -C $RepoRoot rev-parse HEAD).Trim()
    $GitBranch  = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
    $SubmoduleHbbSha = (& git -C (Join-Path $RepoRoot "libs\hbb_common") rev-parse HEAD).Trim()
    $VcpkgResolvedSha = if (Test-Path (Join-Path $env:VCPKG_ROOT ".git")) { (& git -C $env:VCPKG_ROOT rev-parse HEAD).Trim() } else { $VcpkgCommit }
    $RustcVerbose = (& rustc -Vv | Out-String).Trim()
    $CargoVer = (& cargo -V | Out-String).Trim()
    $FlutterVerJson = $null
    try { $FlutterVerJson = (& flutter --version --machine | Out-String | ConvertFrom-Json) } catch {}
    $ClangVer = if (Get-Command "clang" -ErrorAction SilentlyContinue) { (& clang --version | Select-Object -First 1 | Out-String).Trim() } else { "NOT_IN_PATH" }
    $PrevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $PythonVer = (& python --version 2>&1 | Out-String).Trim()
    } finally {
        $ErrorActionPreference = $PrevEap
    }

    $BuildProv = [ordered]@{
        schema_version = 2
        task_id = "DREMOTE-V1-REMEDIATION-005"
        release_candidate = "RC2"
        built_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source = [ordered]@{
            repository = "trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP"
            git_branch = $GitBranch
            git_commit_sha = $GitHeadSha
            submodule_hbb_common_sha = $SubmoduleHbbSha
            cargo_lock_sha256 = (Get-FileHash -LiteralPath (Join-Path $RepoRoot "Cargo.lock") -Algorithm SHA256).Hash.ToLowerInvariant()
            flutter_pubspec_lock_sha256 = (Get-FileHash -LiteralPath (Join-Path $RepoRoot "flutter\pubspec.lock") -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        ci_environment = [ordered]@{
            github_actions = ($env:GITHUB_ACTIONS -eq "true")
            github_run_id = ($env:GITHUB_RUN_ID ?? "")
            github_run_number = ($env:GITHUB_RUN_NUMBER ?? "")
            github_workflow = ($env:GITHUB_WORKFLOW ?? "")
            runner_os = [System.Environment]::OSVersion.VersionString
            image_os = ($env:ImageOS ?? "")
            image_version = ($env:ImageVersion ?? "")
        }
        resolved_toolchains = [ordered]@{
            rustc_verbose = $RustcVerbose
            cargo_version = $CargoVer
            flutter_machine = $FlutterVerJson
            clang_version = $ClangVer
            makensis_version = $MakensisVersion
            python_version = $PythonVer
            vcpkg_commit_sha = $VcpkgResolvedSha
        }
        gates = [ordered]@{
            tests_executed = (-not [bool]$SkipTests)
            fallback_setup_used = $FallbackSetupUsed
            rc_acceptance_eligible = ((-not [bool]$SkipTests) -and (-not $FallbackSetupUsed))
        }
        outputs = [ordered]@{
            setup_exe = [ordered]@{
                file = "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe"
                size_bytes = (Get-Item -LiteralPath $SetupOut).Length
                sha256 = (Get-FileHash -LiteralPath $SetupOut -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            portable_exe = [ordered]@{
                file = "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe"
                size_bytes = (Get-Item -LiteralPath $PortableOut).Length
                sha256 = (Get-FileHash -LiteralPath $PortableOut -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            librustdesk_dll = [ordered]@{
                size_bytes = (Get-Item -LiteralPath $DllPath).Length
                sha256 = (Get-FileHash -LiteralPath $DllPath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            dylib_virtual_display_dll = [ordered]@{
                size_bytes = (Get-Item -LiteralPath $VirtDllPath).Length
                sha256 = (Get-FileHash -LiteralPath $VirtDllPath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    $BuildProv | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $ReleaseDir "BUILD_PROVENANCE.json") -Encoding UTF8

    Write-Host "=== NATIVE COMPILATION & PACKAGING SUCCEEDED ==="
    if ($TranscriptActive) {
        Stop-Transcript | Out-Null
        $TranscriptActive = $false
    }
    Copy-Item -LiteralPath $LogFile -Destination (Join-Path $ReleaseDir "WINDOWS_NATIVE_BUILD.log") -Force

    # 11. Freeze immutable INITIAL_BUILD_SHA256_MANIFEST.txt + SHA256_MANIFEST.txt
    $ManifestLines = @()
    Get-ChildItem -LiteralPath $ReleaseDir -File | Sort-Object Name | ForEach-Object {
        if ($_.Name -notin @("SHA256_MANIFEST.txt", "INITIAL_BUILD_SHA256_MANIFEST.txt")) {
            $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $ManifestLines += "$h  $($_.Name)"
        }
    }
    Set-Content -LiteralPath (Join-Path $ReleaseDir "INITIAL_BUILD_SHA256_MANIFEST.txt") -Value $ManifestLines -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $ReleaseDir "SHA256_MANIFEST.txt") -Value $ManifestLines -Encoding UTF8
    Get-Content (Join-Path $ReleaseDir "SHA256_MANIFEST.txt")
} finally {
    if ($null -ne $ManifestXmlBackup) {
        Set-Content -Path $ManifestXmlPath -Value $ManifestXmlBackup -NoNewline -Encoding UTF8
    }
    Pop-Location -ErrorAction SilentlyContinue
    if ($TranscriptActive) {
        Stop-Transcript | Out-Null
    }
}
