#!/usr/bin/env python3
"""
Generates real SPDX 2.3 Software Bill of Materials (SBOM.spdx.json) and THIRD_PARTY_NOTICES
directly from the repository's locked Cargo.lock and flutter/pubspec.lock files.
"""

import datetime
import hashlib
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def parse_cargo_lock(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    pkgs = []
    for block in text.split("[[package]]")[1:]:
        name_m = re.search(r'^name\s*=\s*"([^"]+)"', block, re.M)
        ver_m = re.search(r'^version\s*=\s*"([^"]+)"', block, re.M)
        src_m = re.search(r'^source\s*=\s*"([^"]+)"', block, re.M)
        chk_m = re.search(r'^checksum\s*=\s*"([^"]+)"', block, re.M)
        if name_m and ver_m:
            pkgs.append({
                "ecosystem": "cargo",
                "name": name_m.group(1),
                "version": ver_m.group(1),
                "source": src_m.group(1) if src_m else "workspace-local",
                "checksum": chk_m.group(1) if chk_m else None,
            })
    return pkgs


def parse_pubspec_lock(path: Path) -> list[dict]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    pkgs = []
    cur_name = None
    cur_ver = None
    cur_src = None
    for line in lines:
        m_pkg = re.match(r"^  ([a-zA-Z0-9_]+):\s*$", line)
        if m_pkg:
            if cur_name and cur_ver:
                pkgs.append({
                    "ecosystem": "pub",
                    "name": cur_name,
                    "version": cur_ver,
                    "source": cur_src or "pub.dev",
                    "checksum": None,
                })
            cur_name = m_pkg.group(1)
            cur_ver = None
            cur_src = None
            continue
        if cur_name:
            m_ver = re.match(r'^    version:\s*"([^"]+)"', line)
            if m_ver:
                cur_ver = m_ver.group(1)
            m_src = re.match(r"^    source:\s*(\S+)", line)
            if m_src:
                cur_src = m_src.group(1)
    if cur_name and cur_ver:
        pkgs.append({
            "ecosystem": "pub",
            "name": cur_name,
            "version": cur_ver,
            "source": cur_src or "pub.dev",
            "checksum": None,
        })
    return pkgs


def main() -> None:
    cargo_pkgs = parse_cargo_lock(REPO_ROOT / "Cargo.lock")
    pub_pkgs = parse_pubspec_lock(REPO_ROOT / "flutter" / "pubspec.lock")
    all_pkgs = cargo_pkgs + pub_pkgs

    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    spdx_packages = [
        {
            "SPDXID": "SPDXRef-RootPackage-DauverseRemoteDesktop",
            "name": "DAUVERSE-REMOTE-DESKTOP",
            "versionInfo": "1.0.0-rc4.3",
            "downloadLocation": "https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP",
            "licenseConcluded": "AGPL-3.0-only",
            "licenseDeclared": "AGPL-3.0-only",
            "copyrightText": "Copyright (C) 2026 DAUVERSE Ecosystem & Purslane Tech Pte. Ltd. (RustDesk Upstream)",
        }
    ]

    for idx, pkg in enumerate(all_pkgs, start=1):
        safe_id = re.sub(r"[^A-Za-z0-9.\-]", "-", f"{pkg['ecosystem']}-{pkg['name']}-{idx}")
        entry = {
            "SPDXID": f"SPDXRef-Pkg-{safe_id}",
            "name": pkg["name"],
            "versionInfo": pkg["version"],
            "downloadLocation": pkg["source"],
            "filesAnalyzed": False,
            "licenseConcluded": "NOASSERTION",
            "externalRefs": [
                {
                    "referenceCategory": "PACKAGE-MANAGER",
                    "referenceType": "purl",
                    "referenceLocator": f"pkg:{pkg['ecosystem']}/{pkg['name']}@{pkg['version']}",
                }
            ],
        }
        if pkg["checksum"]:
            entry["checksums"] = [{"algorithm": "SHA256", "checksumValue": pkg["checksum"]}]
        spdx_packages.append(entry)

    sbom = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "DAUVERSE-REMOTE-DESKTOP-V1-SBOM",
        "documentNamespace": "https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/sbom/v1.0.0-rc4.3",
        "creationInfo": {
            "created": now,
            "creators": ["Tool: generate_sbom_and_notices.py", "Organization: DAUVERSE"],
        },
        "packages": spdx_packages,
    }

    sbom_path = REPO_ROOT / "SBOM.spdx.json"
    sbom_path.write_text(json.dumps(sbom, indent=2) + "\n", encoding="utf-8")

    cargo_lock_sha = hashlib.sha256((REPO_ROOT / "Cargo.lock").read_bytes()).hexdigest()
    notices = [
        "# THIRD-PARTY OPEN SOURCE NOTICES — DAUVERSE REMOTE DESKTOP V1.0",
        "",
        "DAUVERSE REMOTE DESKTOP V1.0 (`1.0.0-rc4.3`) is free and open-source software distributed under the",
        "**GNU Affero General Public License v3.0 (AGPL-3.0)**. Full verbatim license text is",
        "preserved in both `LICENSE` and `LICENCE`.",
        "",
        "## 1. Primary Upstream Attribution",
        "- **RustDesk** (`https://github.com/rustdesk/rustdesk`, commit `a0c0963c483fc8f1aeed4547787d1673adcb583c`, v1.5.3)",
        "  - Copyright (C) Purslane Tech Pte. Ltd. (`info@rustdesk.com`) and RustDesk Contributors.",
        "  - License: GNU Affero General Public License v3.0 (`AGPL-3.0`).",
        "- **hbb_common** (`https://github.com/rustdesk/hbb_common`, commit `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb`)",
        "  - License: GNU Affero General Public License v3.0 (`AGPL-3.0`).",
        "- **rustdesk-server (Self-Host Reference)** (`https://github.com/rustdesk/rustdesk-server`, v1.1.16)",
        "  - License: GNU Affero General Public License v3.0 (`AGPL-3.0`).",
        "- **Amyuni USB Mobile Monitor Virtual Display Driver (`usbmmidd_v2`)** (`https://www.amyuni.com` • staging archive `https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip`, SHA-256 `629b51e9944762bae73948171c65d09a79595cf4c771a82ebc003fbba5b24f51`)",
        "  - Copyright 2014-2021 Amyuni Technologies Inc. (`https://www.amyuni.com`).",
        "  - Staged Unmodified Member SHA-256 Digests:",
        "    - `usbmmidd_v2/usbmmidd.cat`: `470149c4cf9970ba59070aa7c9409c9f63a15727de99bab53e7e51f55310779f` (`Microsoft Windows Hardware Compatibility Publisher`)",
        "    - `usbmmidd_v2/usbmmIdd.inf`: `a8750ca15a86742f3012886c9932bb974158cd2d9779cf891c730d976a47726a`",
        "    - `usbmmidd_v2/x64/usbmmIdd.dll`: `dc135d675127113915a7e5aa9fe57c84edad6be41d0890b265ef124ab26ea9e3`",
        "    - `usbmmidd_v2/License.txt`: `44c73fc4110979899dbb5054662de581f7d4350939f19bb2d50574f613314ba2` (preserved unaltered in `usbmmidd_v2/License.txt`)",
        "  - Acknowledgment & Verbatim License Notice (`usbmmidd_v2/License.txt`, staged opt-in only, never auto-installed):",
        "    ```text",
        "    Copyright 2014-2021 Amyuni Technologies Inc.",
        "    https://www.amyuni.com",
        "",
        "    This software is provided 'as-is', without any express or implied warranty. In no event will the authors be held liable for any damages arising from the use of this software.",
        "    By using this software, you accept to be prompted with an advertisement page which is not always under the control of the author. A fully commercial version is available for users who do not wisth to see those advertisements.",
        "",
        "    Permission is granted to anyone to use this software for any purpose subject to the following restrictions:",
        "",
        "    1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software.",
        "       If you use this software in a product, an acknowledgment in the product documentation would be required.",
        "    2. Altered versions must be plainly marked as such, and must not be misrepresented as being the original software.",
        "    3. This notice may not be removed or altered from any distribution.",
        "    ```",
        "- **RustDeskIddDriver (Surveyed Only — Blocked & Not Bundled)** (`https://github.com/rustdesk-org/RustDeskIddDriver`, v0.4)",
        "  - License: Microsoft Public License (`MS-PL`). Status: `BLOCKED_DO_NOT_INSTALL` (uses self-signed `WDKTestCert` SHA-1 certificate; excluded from DAUVERSE staging and installers).",
        "- **Virtual-Display-Driver (Fallback Reference)** (`https://github.com/VirtualDrivers/Virtual-Display-Driver`, 25.7.23)",
        "  - License: MIT License.",
        "- **sysinfo** (`https://github.com/GuillaumeGomez/sysinfo` / `rustdesk-org/sysinfo` v0.29.10)",
        "  - Copyright (C) Guillaume Gomez and Contributors. License: MIT License.",
        "- **LibreHardwareMonitor (Optional Sensor Bridge Reference)** (`https://github.com/LibreHardwareMonitor/LibreHardwareMonitor`, v0.9.6)",
        "  - License: Mozilla Public License 2.0 (`MPL-2.0`).",
        "- **Flutter Framework (`3.24.5`) & Patched Multi-Window Engine** (`https://github.com/flutter/flutter` & `https://github.com/rustdesk/engine`)",
        "  - Copyright 2014 The Flutter Authors. License: BSD 3-Clause License.",
        "  - Windows x64 Engine Archive (`windows-x64-release.zip`): SHA-256 `ec8cabf36ee4ff24c8d98de25b00e70781eb03876265aee84d0fe554a110036e` (`flutter_windows.dll` SHA-256 `295d3767a5e5c4017f4877e67a4a8926178ecdfbb1196c3bd21ec5f5097f5ed3`).",
        "- **Bundled Offline UI Fonts (`Be Vietnam Pro`, `Inter`, `Roboto Mono`)** (`https://github.com/google/fonts`)",
        "  - License: SIL Open Font License v1.1 (`OFL-1.1`). Verbatim license texts bundled at:",
        "    - `flutter/assets/fonts/be_vietnam_pro/OFL.txt`",
        "    - `flutter/assets/fonts/inter/OFL.txt`",
        "    - `flutter/assets/fonts/roboto_mono/OFL.txt`",
        "",
        "## 2. Locked Dependency Summary",
        f"- **Cargo Lockfile (`Cargo.lock`) SHA-256:** `{cargo_lock_sha}`",
        f"- **Total Locked Rust Crates:** {len(cargo_pkgs)}",
        f"- **Total Locked Dart/Flutter Packages:** {len(pub_pkgs)}",
        f"- **Full Machine-Readable Inventory:** See `SBOM.spdx.json` ({len(spdx_packages)} SPDX package records).",
        "",
        "## 3. Core Rust & Flutter Crate Inventory (Excerpt + Complete Count in SBOM.spdx.json)",
    ]
    for pkg in sorted(cargo_pkgs, key=lambda x: x["name"])[:80]:
        notices.append(f"- `cargo:{pkg['name']}@{pkg['version']}` ({pkg['source']})")
    notices.append(f"- ... plus {max(0, len(cargo_pkgs) - 80)} additional Cargo crates and {len(pub_pkgs)} Pub packages documented in `SBOM.spdx.json`.")

    (REPO_ROOT / "THIRD_PARTY_NOTICES").write_text("\n".join(notices) + "\n", encoding="utf-8")
    print(f"Generated SBOM.spdx.json ({len(spdx_packages)} packages) and THIRD_PARTY_NOTICES.")


if __name__ == "__main__":
    main()
