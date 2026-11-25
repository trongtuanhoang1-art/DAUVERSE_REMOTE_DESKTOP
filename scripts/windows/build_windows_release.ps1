<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 — Reproducible One-Command Windows Native Build & Packaging Script
.DESCRIPTION
  Builds the complete integrated Rust + Flutter + NVENC/VRAM + WHQL Headless Virtual Display client on Windows 10/11 x64,
  preferring fixed disk E:\DAUVERSE_REMOTE_DESKTOP\{BUILD,CACHE,STAGING,RELEASE,BACKUP,LOGS} when available so C: is not polluted.
  Enforces strict $LASTEXITCODE checking on every external command (zero masked test/build failures).
  Produces:
    - RELEASE\DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe
    - RELEASE\DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe (via NSIS makensis.exe)
    - RELEASE\SHA256_MANIFEST.txt
    - RELEASE\SIGNING_STATUS.txt
  Never installs drivers or Windows Services on the build host.
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
Start-Transcript -Path $LogFile -Append | Out-Null

try {
    Write-Host "=== DAUVERSE REMOTE DESKTOP V1.0 — WINDOWS NATIVE BUILD ==="
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

    # Ensure flutter/windows/CMakeLists.txt finds ../../target/release/librustdesk.dll even when CARGO_TARGET_DIR is on E:\
    $CmakeExpectedDllDir = Join-Path $RepoRoot "target\release"
    $CmakeExpectedDll = Join-Path $CmakeExpectedDllDir "librustdesk.dll"
    if ($DllPath -ne $CmakeExpectedDll) {
        New-Item -ItemType Directory -Force -Path $CmakeExpectedDllDir | Out-Null
        Copy-Item -Force $DllPath $CmakeExpectedDll
    }

    # 5. Run targeted Rust & Flutter verification tests (strict non-zero exit enforcement)
    if (-not $SkipTests) {
        Invoke-Checked "Rust dauverse:: unit & security tests" {
            & cargo test --locked --release --lib dauverse::
        }
        Push-Location (Join-Path $RepoRoot "flutter")
        try {
            Invoke-Checked "Flutter DAUVERSE UI & integration tests" {
                & flutter test test/dauverse_ui_test.dart
            }
        } finally {
            Pop-Location
        }
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

    $VirtDllCandidates = @(
        (Join-Path $CargoTargetDir "release\dylib_virtual_display.dll"),
        (Join-Path $CargoTargetDir "release\deps\dylib_virtual_display.dll")
    )
    foreach ($vc in $VirtDllCandidates) {
        if (Test-Path $vc) {
            Copy-Item -Force $vc (Join-Path $StagingAppDir "dylib_virtual_display.dll")
            break
        }
    }

    # Stage Microsoft WHQL-signed usbmmidd_v2 virtual display files (SHA-256 verified; NEVER auto-installed)
    $UsbMmIddZip = Join-Path $WorkspaceRoot "CACHE\usbmmidd_v2.zip"
    $ExpectedUsbMmIddSha256 = "629b51e9944762bae73948171c65d09a79595cf4c771a82ebc003fbba5b24f51"
    if (-not (Test-Path $UsbMmIddZip)) {
        Invoke-WebRequest -Uri "https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip" -OutFile $UsbMmIddZip
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
    Copy-Item -Recurse -Force (Join-Path $UsbExtractDir "usbmmidd_v2") (Join-Path $StagingAppDir "usbmmidd_v2")

    # Preserve rustdesk.exe shim for upstream service compatibility AND provide DAUVERSE_REMOTE.exe entrypoint
    if (Test-Path (Join-Path $StagingAppDir "rustdesk.exe")) {
        Copy-Item -Force (Join-Path $StagingAppDir "rustdesk.exe") (Join-Path $StagingAppDir "DAUVERSE_REMOTE.exe")
    }

    # 7. Build Portable Single-File Executable (DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe)
    $ReleaseDir = Join-Path $WorkspaceRoot "RELEASE"
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

    if ($MakensisPath) {
        $NsiScript = Join-Path $RepoRoot "installer\nsis\dauverse_setup.nsi"
        Invoke-Checked "Compile NSIS Setup Installer" {
            & $MakensisPath "/DSTAGING_DIR=$StagingAppDir" "/DOUT_FILE=$SetupOut" $NsiScript
        }
    } elseif ($AllowPortableAsSetupFallback) {
        Write-Warning "NSIS not found and -AllowPortableAsSetupFallback specified; copying portable binary to SETUP.exe."
        Copy-Item -Force $PortableOut $SetupOut
    } else {
        throw "NSIS (makensis.exe) not found in PATH or Program Files. Install NSIS (winget install NSIS.NSIS) or pass -AllowPortableAsSetupFallback explicitly."
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
        Set-Content -Path $SigningStatusPath -Value "SIGNED_AUTHENTICODE — Signed with caller-provided PFX certificate." -Encoding UTF8
    } else {
        Write-Host "CODE SIGNING STATUS: UNSIGNED (No CERT_PFX_PATH provided — marked honestly per Section 27)."
        Set-Content -Path $SigningStatusPath -Value "UNSIGNED — Built cleanly from source without Authenticode PFX certificate. Auto-update is disabled; verify SHA256_MANIFEST.txt before installation." -Encoding UTF8
    }

    # 10. Generate SHA-256 Manifest
    $ManifestLines = @()
    Get-ChildItem -Path $ReleaseDir -File | Sort-Object Name | ForEach-Object {
        if ($_.Name -ne "SHA256_MANIFEST.txt") {
            $h = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $ManifestLines += "$h  $($_.Name)"
        }
    }
    $ManifestPath = Join-Path $ReleaseDir "SHA256_MANIFEST.txt"
    $ManifestLines | Set-Content -Path $ManifestPath -Encoding UTF8
    Write-Host "=== BUILD SUCCEEDED ==="
    Get-Content $ManifestPath
} finally {
    if ($null -ne $ManifestXmlBackup) {
        Set-Content -Path $ManifestXmlPath -Value $ManifestXmlBackup -NoNewline -Encoding UTF8
    }
    Pop-Location -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
}
