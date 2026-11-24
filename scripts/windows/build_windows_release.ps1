<#
.SYNOPSIS
  DAUVERSE REMOTE DESKTOP V1.0 — Reproducible One-Command Windows Native Build & Packaging Script
.DESCRIPTION
  Builds the complete integrated Rust + Flutter + NVENC/VRAM + Headless Virtual Display client on Windows 10/11 x64,
  preferring E:\DAUVERSE_REMOTE_DESKTOP\{BUILD,CACHE,STAGING,RELEASE,BACKUP,LOGS} when drive E: exists so C: is not polluted.
  Produces:
    - RELEASE\DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe
    - RELEASE\DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe (requires NSIS makensis.exe or uses self-extracting installer mode)
    - RELEASE\SHA256_MANIFEST.txt
  Never installs drivers or Windows Services on the build host automatically.
#>
param(
    [string]$WorkspaceRoot = "",
    [switch]$SkipVcpkgInstall = $false,
    [switch]$SkipTests = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    if (Test-Path "E:\") {
        $WorkspaceRoot = "E:\DAUVERSE_REMOTE_DESKTOP"
    } else {
        $WorkspaceRoot = Join-Path $RepoRoot "_win_workspace"
    }
}

$Dirs = @("BUILD", "STAGING", "RELEASE", "TESTS", "QA", "DOCS", "ARTIFACTS", "LOGS", "CACHE", "TEMP", "BACKUP")
foreach ($d in $Dirs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $WorkspaceRoot $d) | Out-Null
}

# Redirect heavy caches off C:\ when E:\ workspace is active
$env:CARGO_TARGET_DIR = Join-Path $WorkspaceRoot "BUILD\cargo-target"
$env:TEMP = Join-Path $WorkspaceRoot "TEMP"
$env:TMP = Join-Path $WorkspaceRoot "TEMP"
if (-not $env:VCPKG_ROOT) {
    $env:VCPKG_ROOT = Join-Path $WorkspaceRoot "CACHE\vcpkg"
}

$LogFile = Join-Path $WorkspaceRoot ("LOGS\windows_build_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
Start-Transcript -Path $LogFile -Append | Out-Null

try {
    Write-Host "=== DAUVERSE REMOTE DESKTOP V1.0 — WINDOWS NATIVE BUILD ==="
    Write-Host "RepoRoot      : $RepoRoot"
    Write-Host "WorkspaceRoot : $WorkspaceRoot"
    Write-Host "CARGO_TARGET  : $env:CARGO_TARGET_DIR"
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
            git clone https://github.com/microsoft/vcpkg $env:VCPKG_ROOT
        }
        Push-Location $env:VCPKG_ROOT
        git fetch origin $VcpkgCommit
        git checkout $VcpkgCommit
        if (-not (Test-Path ".\vcpkg.exe")) {
            .\bootstrap-vcpkg.bat -disableMetrics
        }
        Pop-Location

        & "$env:VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static --x-install-root="$env:VCPKG_ROOT\installed"
    }
    $env:VCPKG_INSTALLED_ROOT = "$env:VCPKG_ROOT\installed"

    # 2. Ensure Flutter 3.44+ compatibility patches if Flutter >= 3.27 is installed
    $FlutterVer = (& flutter --version | Select-Object -First 1)
    Write-Host "Detected Flutter: $FlutterVer"
    Push-Location (Join-Path $RepoRoot "flutter")
    & flutter pub get
    Pop-Location

    # 3. Build Virtual Display dynamic library (RustDeskIddDriver user-mode bridge; does NOT install driver)
    Push-Location (Join-Path $RepoRoot "libs\virtual_display\dylib")
    & cargo build --locked --release
    Pop-Location

    # 4. Build core Rust library with Flutter + Hardware Codec + NVIDIA RTX 3060 VRAM support
    & cargo build --locked --features "flutter,hwcodec,vram" --lib --release
    $DllPath = Join-Path $env:CARGO_TARGET_DIR "release\librustdesk.dll"
    if (-not (Test-Path $DllPath)) {
        throw "Expected native library not found at $DllPath"
    }

    # 5. Run targeted Rust & Flutter verification tests
    if (-not $SkipTests) {
        & cargo test --locked --release --lib dauverse::
        Push-Location (Join-Path $RepoRoot "flutter")
        & flutter test test/dauverse_ui_test.dart
        Pop-Location
    }

    # 6. Build Flutter Windows x64 Release bundle
    Push-Location (Join-Path $RepoRoot "flutter")
    & flutter build windows --release
    Pop-Location

    $FlutterReleaseDir = Join-Path $RepoRoot "flutter\build\windows\x64\runner\Release"
    $StagingAppDir = Join-Path $WorkspaceRoot "STAGING\DAUVERSE_REMOTE_APP"
    if (Test-Path $StagingAppDir) { Remove-Item -Recurse -Force $StagingAppDir }
    Copy-Item -Recurse -Force $FlutterReleaseDir $StagingAppDir
    Copy-Item -Force $DllPath (Join-Path $StagingAppDir "librustdesk.dll")

    $VirtDll = Join-Path $env:CARGO_TARGET_DIR "release\deps\dylib_virtual_display.dll"
    if (Test-Path $VirtDll) {
        Copy-Item -Force $VirtDll (Join-Path $StagingAppDir "dylib_virtual_display.dll")
    }

    # Rename main binary for DAUVERSE branding while preserving rustdesk.exe shim for service compatibility
    if (Test-Path (Join-Path $StagingAppDir "rustdesk.exe")) {
        Copy-Item -Force (Join-Path $StagingAppDir "rustdesk.exe") (Join-Path $StagingAppDir "DAUVERSE_REMOTE.exe")
    }

    # 7. Build Portable Single-File Executable (DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe)
    $ReleaseDir = Join-Path $WorkspaceRoot "RELEASE"
    $PortableOut = Join-Path $ReleaseDir "DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe"
    Push-Location (Join-Path $RepoRoot "libs\portable")
    & python -m pip install -r requirements.txt
    & python .\generate.py -f $StagingAppDir -o . -e (Join-Path $StagingAppDir "rustdesk.exe")
    Pop-Location

    $PackerExe = Join-Path $env:CARGO_TARGET_DIR "release\rustdesk-portable-packer.exe"
    if (Test-Path $PackerExe) {
        Copy-Item -Force $PackerExe $PortableOut
    }

    # 8. Build Windows Setup Installer (DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe via NSIS if installed)
    $SetupOut = Join-Path $ReleaseDir "DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe"
    $Makensis = Get-Command "makensis.exe" -ErrorAction SilentlyContinue
    if ($Makensis) {
        $NsiScript = Join-Path $RepoRoot "installer\nsis\dauverse_setup.nsi"
        & $Makensis.Source "/DSTAGING_DIR=$StagingAppDir" "/DOUT_FILE=$SetupOut" $NsiScript
    } elseif (Test-Path $PortableOut) {
        Write-Warning "NSIS (makensis.exe) not found; copying unified installer/portable binary (supports --install GUI/CLI) to DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe"
        Copy-Item -Force $PortableOut $SetupOut
    }

    # 9. Code Signing Status Check (Never fake signatures!)
    if ($env:CERT_PFX_PATH -and $env:CERT_PFX_PASSWORD -and (Test-Path $env:CERT_PFX_PATH)) {
        Write-Host "Signing executables with provided Authenticode certificate..."
        foreach ($bin in @($PortableOut, $SetupOut)) {
            if (Test-Path $bin) {
                & signtool.exe sign /fd SHA256 /f $env:CERT_PFX_PATH /p $env:CERT_PFX_PASSWORD /tr http://timestamp.digicert.com /td SHA256 $bin
            }
        }
    } else {
        Write-Host "CODE SIGNING STATUS: UNSIGNED (No CERT_PFX_PATH provided — marked honestly per Section 27)."
        Set-Content -Path (Join-Path $ReleaseDir "SIGNING_STATUS.txt") -Value "UNSIGNED — Built cleanly from source without Authenticode PFX certificate. Verify SHA256_MANIFEST.txt before installation."
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
    Pop-Location -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
}
