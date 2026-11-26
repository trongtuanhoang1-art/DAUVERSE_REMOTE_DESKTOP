# DAUVERSE REMOTE V1 RC2 — INDEPENDENT RE-QA REPORT

**Task:** DREMOTE-V1-INDEPENDENT-REQA-006  
**Reviewer role:** CODEX — Independent QA & Security Reviewer  
**Developer:** ANTIGRAVITY CLOUD  
**Review date:** 26-11-2026, Asia/Saigon (UTC+07:00)  
**Production:** **LOCKED — KHÔNG PHẢI PRODUCTION APPROVED**  
**Final verdict:** **FAIL**

## 1. Kết luận điều hành

RC2 có cải thiện thực chất so với RC1: artifact khớp các hash được yêu cầu; manifest đóng hai chiều; bundle và snapshot khớp commit; pin submodule được kiểm tra theo nội dung upstream; recovery cuối không sửa mã sản phẩm hoặc hash báo cáo Codex gốc. Chữ ký catalog/driver được kiểm tra đọc-only, không cài driver. Các sửa đổi về ownership, mặc định FFI fail-closed, PIN rotation và telemetry schema có giá trị.

Tuy nhiên **không đủ điều kiện CONDITIONAL GO FOR CONTROLLED WINDOWS PILOT ở trạng thái hiện tại**. Review phát hiện các acceptance gap còn tồn tại: canonical HMAC làm tròn trường float (F01); replay journal lỗi bị bỏ qua khi khởi tạo (F09); rollback chấp nhận file ngoài manifest rồi sao chép cả backup (F11); confinement handle Windows còn nhánh không kiểm tra và prefix không theo component (F14); receive engine chưa chứng minh digest/độ dài từng file đối ứng sender (F16). Service revoke còn cập nhật trạng thái bộ nhớ mà không chứng minh dừng SCM thực tế (F08); persistence lỗi chưa thống nhất fail-closed (F07). Có phát hiện mới **N01/P2: sai hệ số biểu diễn HMAC benchmark khoảng 10 lần**.

**FAIL dựa trên các khuyết điểm source/validator quan sát được và acceptance chưa đạt, không chỉ vì thiếu quyền chạy EXE.** Các mô hình Python không được trình bày là exploit native; việc chứng minh exploit native cho F14 vẫn NOT_TESTED. Đồng thời các bài thử hai máy, NVENC, Headless native, unattended/reboot và Smart Power thực tế vẫn BLOCKED/NOT_TESTED. Không tự đóng bất kỳ F01–F16 nào chỉ dựa trên developer PASS.

### 1.1 Quy ước mức bằng chứng

| Nhãn | Ý nghĩa trong báo cáo |
|---|---|
| **IV** | Reviewer tự kiểm tra byte/hash, source/diff, cấu trúc hoặc metadata/API; không có nghĩa đã chạy sản phẩm. |
| **IE-HELPER** | Reviewer tự chạy các hàm validator đã tách bằng AST, với fixture inert; không chạy installer/rollback body/sản phẩm. |
| **IE-MODEL** | Reviewer tự chạy mô hình Python/arithmetic bám source; không phải compiled Rust, DLL hay remote session. |
| **DEV** | Log/test/report do developer/CI cung cấp; đã đối chiếu nhất quán và hash nhưng không tự động nâng thành independently executed product tests. |
| **BLOCKED** | Thiếu môi trường/quyền/evidence cần thiết để đạt acceptance thực tế trong nhiệm vụ này. |
| **NOT_TESTED** | Chưa thực thi bài thử cụ thể. Không đồng nghĩa PASS hoặc không có lỗi. |

Giữ nguyên severity lịch sử: **F01–F06 P1; F07–F14 và F16 P2; F15 P3** (6 P1, 9 P2, 1 P3; không chứng minh P0). N01/P2 là finding mới, không thay severity lịch sử.

### 1.2 Ranh giới thực thi và bảo toàn

Mọi extraction/fixture/evidence reviewer ở workspace E, không tạo workspace ổ C. Đọc ZIP có sẵn trong Downloads, sao chép vào E; không tải/chạy candidate EXE/DLL trên host. Không build, install, service/driver mutation, BIOS/firewall/router, truy cập DAUVERSE AI hoặc workflow trigger. Public GitHub API chỉ đọc, không phát sinh dịch vụ trả phí. Wintrust/CryptCAT và Get-AuthenticodeSignature chỉ đọc file bằng API hệ điều hành; không nạp thư viện candidate, không đăng ký catalog vào hệ thống.

Các file `rc2_payload/` giữ nguyên; recheck cuối **1.389/1.389 manifest entries khớp**. Reviewer chỉ tạo script, fixture và hồ sơ riêng. **Independently executed native product tests: 0** theo giới hạn người dùng. Những lệnh hash, Git, parse, helper và model dưới đây thực sự đã được reviewer chạy.

## 2. Tiếp nhận artifact và an toàn archive

### 2.1 Phân biệt outer wrapper và COMPLETE_QA thật

Tên file tải từ GitHub giống tên ZIP nội bộ. Đây là **hai lớp archive**, không phải mismatch của expected payload:

| Đối tượng | Bytes | SHA256 | Kết quả |
|---|---:|---|---|
| GitHub artifact ZIP bên ngoài ở workspace root | 243478014 | `ec93d9362600b0b20b3b6ace76fef0efbe2f900d6c93a725d9288e9afeb4c993` | IV: khớp digest artifact GitHub; không so nhầm với expected inner ZIP. |
| `qa_extracted_untrusted/DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip` | 182312356 | `86d592a0839bd86d5a6087930d9fd5255e0a8747655807f4843df0896a0cd3c9` | IV: khớp expected COMPLETE_QA.zip. |
| `rc2_payload/RELEASE/DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe` | 35345420 | `052cee1f4102baee7cc94defe3bc4b90691d5079352a140a7aee30bc1bdb33cc` | IV: khớp expected SETUP. |
| `rc2_payload/RELEASE/DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe` | 26471936 | `73a560a27636cb2a5f876854b1bb42a1e6d16af2d7f66024165c4d05ae3069b4` | IV: khớp expected PORTABLE. |
| `rc2_payload/QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md` | 51476 | `f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913` | IV: khớp expected ORIGINAL CODEX QA REPORT. |

Setup/portable đứng riêng trong wrapper và bản trong RELEASE khớp nhau. Expected hash là trust anchor do người yêu cầu cung cấp; bản thân digest không chứng minh code an toàn hay executable được ký.

### 2.2 Kiểm tra trước extraction

`audit_zip.py` kiểm tra entry trước khi extract: absolute/drive/UNC/traversal, phân cách đường dẫn, case-fold collision, duplicate, Unix symlink/special-file mode v? t?n Windows nguy hi?m (ADS/reserved/trailing-dot), encrypted entry, kích thước/ratio theo giới hạn script. Đọc toàn bộ entry để kiểm tra CRC, đích resolve nằm dưới thư mục QA riêng. Không chạy file từ archive.

- Outer: **5 entries**, tổng uncompressed **244130166 bytes**; extraction vào `qa_extracted_untrusted/` sau kiểm tra.
- Inner: **1390 files**, tổng uncompressed **221920830 bytes**; extraction vào `rc2_payload/` sau kiểm tra.
- Không phát hiện entry vi phạm các kiểm tra trên. Đây không phải malware scan hoặc bảo đảm toàn bộ parser ZIP không lỗi.
- Hồ sơ: `independent_audit/outer_zip_audit.json`, `payload_zip_audit.json`.

### 2.3 Manifest hai chiều

Root `rc2_payload/SHA256_MANIFEST.txt` có **1389 entries**, actual **1390 files gồm chính manifest**; self-exclusion có chủ đích. Kiểm tra listed→disk và disk→listed: **0 missing, 0 digest mismatch, 0 duplicate/path issue, 0 unlisted**. SHA256 manifest: `c7c568e3b3ddbb11c7a548a1d123a3706d2f2fcd7a4f77c41fa82d214b415793`.

`RELEASE/INITIAL_BUILD_SHA256_MANIFEST.txt`: **7 entries khớp**; `WINDOWS_NATIVE_BUILD.log` được resolve tới LOGS theo cấu trúc đóng gói, không tạo log mới để làm PASS. `FINAL_HANDOFF_SHA256_MANIFEST.txt` ở wrapper được đối chiếu với artifact được giao. Evidence: `manifest_verification.json`, `initial_manifest_verification.json`, `final_input_recheck.json`.

**Phân biệt:** manifest toàn bộ delivery hiện tại đóng hai chiều, nhưng các hàm validator runtime/rollback không vì vậy tự trở thành validator hai chiều (xem F02/F11).

## 3. Git bundle, source snapshot, submodule và recovery cuối

### 3.1 Chuỗi source kiểm tra độc lập

| Hạng mục | Kết quả IV | Giới hạn |
|---|---|---|
| RC1 | `309948002371aba1407532c9ba8d9d216a02e771` | Baseline review. |
| RC2 | `0e1e3e87185159a481360b2c2b28f3dee541328f` | Commit bundle/snapshot/CI/provenance nhất quán. |
| Git bundle | SHA256 `3fd64d094d901efe98fa75ede07d05f1cfbc55961b5f19f98a12653feb1e8efd`; `git bundle verify` exit 0; complete history | Import vào bare verifier riêng, hooks disabled; không checkout/chạy source. |
| Object integrity | `git fsck --full --strict` exit 0 | Không thay thế chữ ký hoặc review logic. |
| SOURCE snapshot | **1237 tracked blobs khớp**, 0 missing/mismatch/extra sau chuẩn hóa case và loại gitlink | So Git blob ID với byte snapshot, không chỉ tin manifest. |
| Pinned hbb_common | Gitlink `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb`; **33 blobs** khớp upstream tree API, không truncated/extra/missing | Không coi main bundle là bundle lịch sử riêng của submodule. |
| Commit signature | RC2 không có `gpgsig`; `verify-commit` exit 1 | **Unsigned commit**, không có signed build attestation trong hồ sơ đã kiểm tra. |

`DOCS`/`docs` tạo **66 case-only aliases** giữa Git path và snapshot Windows. Đây là ánh xạ cùng file trên filesystem không phân biệt case, không phải 66 file lạ hoặc ZIP traversal. Đã sửa phân loại ban đầu trong `source_extras_verification.json`; không giấu mismatch thực tế. Hồ sơ: `bundle_verify.txt`, `git_fsck.txt`, `source_snapshot_verification.json`, `submodule_verification.json`, `hbb_common_upstream_tree.json`.

### 3.2 Toàn bộ diff RC1 → RC2

Diff đầy đủ: **50 files; +7813 / -1355 lines; 660209 bytes**, SHA256 `109b7038071f8c066afe8141f325edbbe3e6b4ea97256122781562adb3bb20fe` (`independent_audit/rc1_rc2_full.txt`). Mỗi file có diff riêng và digest trong `diff_inventory.json`, toàn bộ hunk headers và nhóm review trong `whole_diff_review_ledger.json`; danh sách 50 file ở phụ lục 12.

Review bao phủ delta sản phẩm Rust/Dart/UI/FFI, receive filesystem và IPC WriteDone, NSIS/rollback, hook Python/PowerShell, harness/build/package/workflow, dependency pin, evidence và hồ sơ acceptance. Đã theo ngược call path quan trọng, không chỉ grep chuỗi PASS. Source review không phải chứng minh mọi runtime path an toàn; phần native, fuzz, GPU và môi trường nhiều máy không được thực thi.

### 3.3 Phạm vi recovery cuối — VERIFIED

So parent `a03dc62a0d8f0122b7ef511c4ca3e97cb7e153b3` → RC2:

1. `.github/workflows/dauverse-windows-build.yml`
2. `ARTIFACTS/SHA256_MANIFEST.txt`
3. `SHA256_MANIFEST.txt`

Chỉ **3 file**, **+69/-2**, không có mã sản phẩm. SHA256 workflow RC2: `d9547b66a50c0018eb281b633af7df3969132963396de1e19f7f54d108c269a4`. Báo cáo Codex gốc ở parent và RC2 đều là `f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913`; expected literal pin trong workflow không bị đổi. **PASS cho yêu cầu recovery cuối chỉ sửa workflow/manifest.** Không được suy rộng thành toàn bộ RC1→RC2 không đổi sản phẩm: delta tổng thể có sửa sản phẩm.

Evidence: `final_recovery_diff.txt`, `final_recovery_verification.json`.

## 4. CI, provenance, chữ ký và license

### 4.1 Đối chiếu GitHub trực tiếp (read-only)

Provider URL: `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/actions/runs/45720572543`.

- Run **45720572543**, manual `workflow_dispatch`, attempt 1; `head_sha` đúng RC2; completed/**success**.
- Created **2026-11-25T23:20:18Z**, updated **2026-11-26T00:06:04Z** (sáng 26-11 theo Asia/Saigon); khoảng 45m46s.
- Job **139577570401**, `Build & Verify DAUVERSE Remote V1 RC2 (Windows x64)`: success.
- Artifact **15073758746**, size **243478014**, digest đúng outer `ec93d936...`, chưa expired tại lúc đọc.
- Endpoint tải CI logs trả **403 Forbidden**. Đã lưu `provider_logs_access_status.txt`; **không tuyên bố đã tải và xác thực độc lập raw logs trực tiếp từ GitHub**. Bundled logs được hash, đọc và đối chiếu identity/provenance, nhưng vẫn là DEV evidence trong phạm vi runtime.

Raw metadata lưu ở `github_run_45720572543.json`, `github_jobs_45720572543.json`, `github_artifacts_45720572543.json`. CI green xác nhận provider ghi nhận workflow thành công, không phải signed attestation source→binary, cũng không chứng minh mọi feature PASS. Các cảnh báo Action Node/cache không bị gọi nhầm là failed tests.

### 4.2 Provenance và toolchain

`RELEASE/BUILD_PROVENANCE.json`, schema 2, built **2026-11-26T00:00:09Z**, gắn đúng commit/submodule/run/output hashes. SHA256 `3a6a2ab8b2653102b2565842fb01e4eadd1c00fccd11190d7b70dc89c5d6fb30`. Đã kiểm tra các bản lock tương ứng:

- Cargo.lock: `c09e5bfcb87918f84c0c4f806f1f3b7ef1a8a879c3214f44046f7b516756909b`.
- pubspec.lock: `321bcc2ad73db2baefd4ebb8c4add69d8ba3ddac9a74d227090a7d76a763a31c`.
- DEV recorded: Rust/Cargo **1.100.0**, Flutter **3.50.0**, Dart **3.14**, clang **17.0.6**, Python **3.12.10**, vcpkg **9e593bb18ea69cc5095e012465dcd675a822ed0d**; Windows Server 2022 build **20348**, image **20261116.370.1**.
- **NSIS resolved thực tế v3.10**, không khẳng định mọi build dùng 3.11: workflow chỉ cài 3.11 nếu NSIS chưa có. Đây là giới hạn reproducibility/pin cần ghi nhận trong F15.

Không rebuild vì người dùng cấm. Không có bằng chứng reviewer tự tái tạo byte-identical executable hoặc xác nhận mọi network dependency build. Provenance nhất quán và hash closure tốt hơn không đủ biến thành reproducible-build certification.

### 4.3 Chữ ký executable và catalog driver

`Get-AuthenticodeSignature` được chạy đọc-only:

| File | Trạng thái quan sát |
|---|---|
| SETUP.exe, PORTABLE.exe, librustdesk.dll, dylib_virtual_display.dll | **NotSigned** |
| usbmmidd driver DLL và CAT được giao | **Valid**, Microsoft Windows Hardware Compatibility Publisher; thumbprint `984E03B613E8C2AE9C692F0DB2C031BF3EE3A0FA` |

Đã kiểm tra catalog membership bằng API hệ điều hành, không cài driver/catalog: INF member tag `A8750CA15A86742F3012886C9932BB974158CD2D9779CF891C730D976A47726A`; DLL SIP hash tag `33329938E29FB2FDC8398E238B5047184464F4F7B6735918EC5B61E7D606D5BA`; cả hai có trong CAT. Negative control all-zero tag không có. DLL SIP hash không bắt buộc bằng raw-file SHA256.

Evidence: `authenticode_readonly.json`, `catalog_membership_readonly.json`, `independent_catalog.py`. Tham chiếu thiết kế primary Microsoft: WINTRUST_CATALOG_INFO, CryptCATAdminCalcHashFromFileHandle2, CryptCATGetMemberInfo, CryptCATOpen. **Valid catalog/member ≠ đã test cài/activate hardware, không phải bản WinVerifyTrust toàn bộ policy được reviewer tái chạy.** Trust/revocation phụ thuộc ngữ cảnh OS lúc đọc; không chứng nhận vĩnh viễn.

Static PE: NSIS setup stub **x86/0x14c** là phù hợp với một bootstrapper, không tự coi là sai kiến trúc; portable/engine/DLL kiểm tra là x64. Engine có **347 exports**, gồm `dauverse_invoke`, hàm free tương ứng. Chưa load DLL, chưa chứng minh Flutter dependency closure hay giải mã toàn bộ portable payload. Evidence `pe_static_inspection.json`.

### 4.4 Driver package, licenses, SBOM

Driver staging archive pin được ghi là `629b51e9944762bae73948171c65d09a79595cf4c771a82ebc003fbba5b24f51`; **không tải lại upstream ZIP để so byte**. Reviewer kiểm tra driver/CAT/INF đã giao, nội dung license 999 bytes và provenance. WDK test-cert driver bị policy chặn; không được thay bằng chứng unsigned/test-cert thành WHQL runtime PASS.

`usbmmidd_v2_License.txt` còn notice/điều khoản quảng bá của Amyuni. Có LICENSE_COMPLIANCE/THIRD_PARTY/upstream manifest; không đưa ý kiến pháp lý rằng mọi nghĩa vụ redistribution đã hoàn thành. SPDX JSON parse được, **1239 packages, 0 files, 0 relationships**: inventory không phải full binary-to-component SBOM. Không chạy SCA toàn bộ dependencies/CVE audit. Bounded scan added diff theo private-key header/GitHub-token/AWS-key shape có **0 hit**; không gọi đó là exhaustive secret audit.

## 5. Hồ sơ Re-QA và đánh giá tuyên bố Windows “7/7 PASS”

### 5.1 Hồ sơ đầu vào đã rà soát

Đã đọc báo cáo Codex gốc (466 lines, verdict lịch sử FAIL), `QA/FINDINGS_REMEDIATION_MATRIX.md`, `DOCS/FEATURE_ACCEPTANCE_MATRIX.md`, `QA/CODEX_REQA_WINDOWS_RC2_HANDOFF.md`, hướng dẫn, build/signing/driver provenance, report JSON/Markdown, negative selftest, native/build/verify console logs và Linux preflight. Đã đối chiếu các bản sao trong SOURCE với bản đóng gói, giữ acceptance gốc thay vì tự nhận trạng thái `REMEDIATED (PENDING INDEPENDENT RE-QA)` là CLOSED.

Các observation lịch sử A01/A02 về delivery/bundle nay có IV giải quyết ở phạm vi cung cấp artifact/source. A03 native verification chỉ có DEV và vẫn thiếu thực thi độc lập. A04 trust/license improved, không đạt xác nhận toàn bộ binary trust, license nghĩa vụ hoặc feature runtime. Không dùng A01/A02 đã giải quyết để che các F còn mở.

Feature matrix FAM-01…12 có trộn PASS theo scope và BLOCKED. Các hạn chế cần sửa cách đọc:

- FAM-06 confined finalize không chứng minh đủ sender→receiver integrity hay NTFS race.
- FAM-09 “distinct-sentinel rollback” không phải distinct-release rollback.
- FAM-10 replay good-path qua restart không bao phủ corrupt/unreadable journal.
- FAM-11 ba process không phải reboot hoặc nhiều Windows profiles.
- FAM-02/license claim không thay thế review redistribution. Các nhãn PASS trong matrix là **claim DEV có phạm vi**, không phải kết luận reviewer cho toàn bộ chức năng.

### 5.2 “Sandbox” thực chất được chứng minh tới đâu?

`EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json` schema 2, timestamp **2026-11-26T00:00:58Z**, commit/submodule đúng, runner NT20348, session 2; tự ghi scope:

`SINGLE_HOST_DISPOSABLE_WINDOWS_RUNNER_ONLY_NOT_TWO_MACHINE_E2E`

Có evidence Windows CI runner disposable. **Không có căn cứ gọi đó là một phiên Microsoft Windows Sandbox (.wsb), Windows 11 GPU lab, hoặc hai Windows endpoints.** Từ “Windows Sandbox 7/7” trong handoff không được nâng phạm vi hơn dữ liệu này.

| DEV group | Evidence được cung cấp | Reviewer xác minh tới đâu / hạn chế |
|---|---|---|
| [0/7] selftest | 10 negative helper cases rejected | IV đọc log; IE-HELPER tự chạy 10 ca, xem mục 7. |
| 1 | Immutable initial manifest 7 entries, original build log | IV digest/format/closure; không reviewer build. |
| 2 | External RustDesk coexistence fixture + install | Fixture là **cmd.exe được copy thành rustdesk.exe**, service SCM tạo nhưng không start. Không phải real running RustDesk coexistence. |
| 3 | WDK test-cert rejection, driver CAT/license, CLI/shim 1.5.3 | IV chữ ký/member/license; native CLI/shim chỉ DEV. |
| 4 | Installed GUI survives 5s, engine/Flutter DLL present; portable survives 5s | DEV liveness/module evidence; không chứng minh UI render/action hoặc remote session đúng. |
| 5 | DPAPI/PIN/settings/HMAC/replay/headless/update checks qua ba process | DEV phase 1 vault 230 bytes; phase 2 reopen, 10-field tamper/replay 401/lockout etc.; phase 3 corrupt vault denied. Không reviewer native execution, không OS reboot. |
| 6 | Tampered backup denied; pre/post distinct JSON sentinel | Reinstall cùng SETUP; không hai binary release khác nhau, không migration/crash rollback proof. IE-HELPER vẫn thấy extra file được nhận. |
| 7 | Uninstall service/cert/Run-key observations + final manifest | DEV teardown của fixture trong runner; không reviewer installer/uninstaller test. |

**7/7 là bảy nhóm script ở một host**, không phải bảy phép chứng minh mọi acceptance/feature an toàn. Nội dung log âm tính xuất hiện error mong đợi không tự là failure bất ngờ; ngược lại bỏ qua test không được đổi thành PASS.

### 5.3 Build/test log audit

- `LOGS/WINDOWS_NATIVE_BUILD.log`: **1806 bytes**, transcript cấp wrapper. Chi tiết build nằm ở `GITHUB_ACTIONS_BUILD_CONSOLE.log` (**179889 bytes**); không dùng độ dài/banners như attestation build.
- Rust base: **19 passed, 0 failed, 3 ignored**. Ba test ignored yêu cầu symlink privilege:
  - `download_refuses_linked_target_and_staging_files`
  - `download_refuses_symlink_destination_directory`
  - `path_traversal_e2e_write_rejects_symlink_escape`
- Dauverse Rust selected suite: **27 passed, 0 failed, 262 filtered out**. Không phải toàn bộ workspace 289 tests đều executed.
- Flutter console: **5 tests passed**. Test F06 forced-unbound kiểm tra default fail-closed; **4 test UI còn lại bật `setTestHarnessMode(true)`**. Không biến chúng thành native-DLL-backed interactive screen coverage. “16 screens” nếu có là số phạm vi UI/claim, không phải 16 native tests reviewer xác nhận.
- Linux `.so`/preflight/unit results vẫn là DEV, không phải Windows hardware runtime hoặc reviewer rerun.

Evidence raw và tóm tắt: `LOGS/`, `EVIDENCE/`, `independent_audit/additional_verification.json`. Tài khoản hiện tại không lấy được provider raw logs (403), vì vậy không tuyên bố authenticity provider cho từng dòng log đóng gói chỉ nhờ nó có trong manifest.

## 6. Ma trận kiểm định độc lập F01–F16

Đường dẫn trong cột source tính tương đối từ `rc2_payload/SOURCE/`; vị trí dòng áp dụng đúng snapshot RC2. **PARTIAL không có nghĩa acceptance đã hạ xuống; mọi finding dưới đây chưa CLOSED.** Với finding có source fix tích cực nhưng thiếu native evidence, ghi rõ BLOCKED thay vì dựng runtime failure.

| ID | Severity lịch sử | Bằng chứng và tiến bộ RC2 | Kết luận reviewer / remaining acceptance |
|---|---|---|---|
| **F01** | **P1** | `src/dauverse/ai_bridge.rs:157–205,230–337`: v2 domain/full field array, source policy, finite floats, HMAC/constant-time comparison; DEV 10-field tamper. | **OPEN / PARTIAL (IV + IE-MODEL).** Float progress/confidence được format 4 decimals, khác với raw f32 dùng normalize; hai raw payload có thể cùng canonical/HMAC. Không đạt bảo vệ chính xác mọi giá trị consumed. Xem 6.1. |
| **F02** | **P1** | `scripts/windows/verify_and_package_windows_rc.ps1`: missing/hash/duplicate/log/early-exit/DLL negatives; immutable manifest; IE-HELPER 10/10 rejection. | **PARTIAL / acceptance OPEN.** Log validator nhận padded synthetic success; manifest helper không chặn extras; liveness+DLL không phải UI correctness. Delivery closure PASS riêng. Missing-export/wrong-arch/native-action regression **BLOCKED/NOT_TESTED**. Không kết luận real build log bị giả. |
| **F03** | **P1** | `installer/nsis/dauverse_setup.nsi:41–57` và helper: normalize ImagePath với separator, preserve external service/process, backup abort nếu lỗi; uninstall ownership-scoped. | **SOURCE FIX VERIFIED / native closure BLOCKED.** DEV fixture không phải real RustDesk service đang chạy. Cần owned/external service thực, paths/spaces, failure exit codes, upgrade/uninstall/reboot trong guest được phép. Không đóng chỉ bằng fixture cmd.exe. |
| **F04** | **P1** | `src/dauverse/headless.rs`, driver provenance: Configured/BlockedApprovalRequired/Active/Failed; active chỉ sau native plug success; WDK test-cert blocked. IV CAT + membership. | **PARTIAL / native BLOCKED.** Cần authorized monitorless activation, capture, topology/restore, failure/reboot/GPU evidence. Signed catalog không chứng minh driver vận hành hay cấp approval. |
| **F05** | **P1** | `src/dauverse/security.rs:405–677`: enroll không overwrite, rotation đòi current PIN, corrupt vault deny, scope/expiry 300s, 5-strike lockout. DEV DPAPI/PIN 3-process. | **SOURCE FIX VERIFIED / PARTIAL, independent native BLOCKED.** Cần fault/recovery/rotation invalidation/reboot/profile tests; lockout persistence lỗi bị bỏ qua liên quan F07. Không tự đánh dấu auth bypass native. |
| **F06** | **P1** | Flutter bridge/shell: test harness default false, unbound trả ok=false/error; caller propagation; PE exports hiện diện. | **DEFAULT FAIL-CLOSED SOURCE VERIFIED / PARTIAL.** Runtime test-mode setter vẫn compile vào app, không phải compile-time isolation; chưa tìm được exposed remote enabler. Native wrong DLL/export/arch, UX/action denial **BLOCKED/NOT_TESTED**. Không gọi các test bật mock là native PASS. |
| **F07** | **P2** | `src/dauverse/mod.rs:75–84`, crypto/security persistence: durable appdata, DPAPI current-user, atomic/sync/rename writes; không còn default temp ngoài cfg(test). | **OPEN / PARTIAL.** Một số persist failures bị log/`let _` bỏ qua (lockout/history/replay initialization); ACL kế thừa chưa có explicit least-privilege proof. Disk-full/crash/reboot/multiprofile **NOT_TESTED**. Không suy diễn world-writable nếu chưa đo ACL. |
| **F08** | **P2** | `src/dauverse/service_ctrl.rs:155–208,251–280`: SCM/ownership/Run-key observation, approve-mode update/readback. | **OPEN / PARTIAL, native BLOCKED.** revoke thay Running→Stopped trong bộ nhớ không gọi dừng SCM trong đường này; Run-key deletion best-effort. Chưa chứng minh cắt active sessions/revoke unattended/reboot truth. Xem 6.3. |
| **F09** | **P2** | `src/dauverse/ai_bridge.rs:355–383,470–574`: durable 660s journal, cap 65536 fail429 không evict active, timestamp ±300s, write failure rollback+reject. | **OPEN / PARTIAL (IV + IE-MODEL).** Existing malformed/unreadable journal được ignore khi constructor mở, cache empty; captured valid envelope trong freshness window có thể mất remembered replay state sau restart. DEV 2100 events + good restart không bao phủ nhánh này. |
| **F10** | **P2** | `src/dauverse/performance.rs`: measured_fps Option, target/estimate được phân biệt, local microbenchmark label. | **SCHEMA FIX VERIFIED / PARTIAL.** Actual encode/network/NVENC SLO **BLOCKED**; chưa chứng minh nguồn counter native. Có regression **N01/P2** về hmac_event_sign_us scaling, xem mục 8. |
| **F11** | **P2** | `scripts/windows/rollback_windows_release.ps1:85–127,233`: hash/duplicate/reparse/listed PE validation, quarantine/recovery logic. | **OPEN / PARTIAL (IV + IE-HELPER).** Unlisted backup extra được validator nhận, line233 copy cả folder. DEV same-binary distinct sentinel không đạt distinct-release requirement. Crash/restart/data migration native **NOT_TESTED**. |
| **F12** | **P2** | `src/dauverse/update_center.rs:49–97`: kiểm tra signature thực và pinned publisher, không tin status người gọi; unsigned manual-only, auto false; version/hash checks. | **SOURCE POLICY VERIFIED / PARTIAL.** Release hiện unsigned (IV). Valid signed update, revoked/expired chain, authenticated metadata/antirollback delivery **BLOCKED/NOT_TESTED**. Không bật auto-update để né gate. |
| **F13** | **P2** | `src/dauverse/smart_power.rs`: dry-run WoL parse/return trước UDP bind/send. DEV zero-packet guard và 102-byte loopback live test. | **SOURCE FIX VERIFIED; independent native NOT_TESTED.** Reviewer không phát packet hay power action. Real shutdown/sleep/reboot/WoL/interlocks **BLOCKED**; disabled smart plug/mock không là vendor device PASS. |
| **F14** | **P2 — risk, chưa chứng minh exploit** | `src/dauverse/crypto_util.rs:555–640`, `libs/base/src/fs.rs`: canonical precheck, leaf no-follow/reparse metadata, flush/close/sync trước finalize. | **OPEN RISK / PARTIAL (IV + IE-MODEL).** Final handle path dùng string prefix, len0 hoặc >=1024 bỏ qua check; intermediate-parent race chưa được native chứng minh/chặn đầy đủ. 3 Windows symlink tests ignored. Native NTFS race/oplock **NOT_TESTED**, không gọi là exploit đã chạy. |
| **F15** | **P3** | workflow/action SHA pins, tool/lock provenance, bundle/snapshot và release hashes tốt hơn; IV traceability. | **TRACEABILITY SUBSTANTIALLY VERIFIED / PARTIAL.** NSIS resolve3.10 khác install fallback3.11; unsigned commit/build attestation thiếu; independent reproducible rebuild **NOT_TESTED (bị cấm)**. Không đồng nhất provenance với reproducibility. |
| **F16** | **P2** | `src/dauverse/transfer_guard.rs:440–698`, `src/ui_cm_interface.rs` WriteDone: flush/sync/close rồi verify, local hash/size guard, optional expected hash single-file. | **OPEN / PARTIAL (IV + IE-MODEL).** Engine batch đặt expected SHA None, verify aggregate total không expected length từng file; local digest không so sender digest vẫn Completed. Live corruption/multi-file/resume/E2E **BLOCKED/NOT_TESTED**. |

### 6.1 F01 — HMAC coverage chưa tương đương semantic input

Canonical v2 tốt hơn v1: domain separation, event fields và provenance nằm trong input ký; finite float/source policy được xét. Không phát hiện key recovery hoặc phá primitive HMAC. Nhưng `progress`/`confidence` được ký dưới dạng chuỗi 4 số lẻ, sau đó raw f32 khác biệt vẫn dùng để normalize/range-check.

IE-MODEL: `progress=100.0f32` và `100.00000762939453f32` đều canonical `100.0000` với cùng HMAC trong mô hình; raw giá trị đầu normalize thành 100, giá trị sau thành None vì >100. Điều kiện: có một envelope được ký hợp lệ, còn thời hạn, chưa consume ID/nonce, thay một trường float trong cùng bucket làm tròn. **Không chứng minh sửa được arbitrary summary/provenance hay ký từ nguồn không được phép.** Đây là residual exact-payload/semantic acceptance defect, không phải native exploit đã thực thi.

Để đóng: ký representation lossless/canonical của mọi giá trị thực sự consumed, hoặc normalize một lần trước ký và chỉ consume representation đó; bổ sung cross-language f32/boundary/nonfinite/tamper vectors, và native negative tests. Không tự chọn một giải pháp ít strict hơn original full-payload acceptance.

### 6.2 F09 và F07 — replay/durable-state fault boundaries

Replay ingestion có nhiều nhánh fail-closed đúng: timestamp, capacity, không evict entry đang hoạt động, persist fail undo + deny. Tuy nhiên constructor `read_to_string`/`serde_json` chỉ xử lý `Ok`; journal đã tồn tại nhưng corrupt/unreadable không làm service fail-closed, replay cache khởi đầu rỗng. IE-MODEL đọc journal hợp lệ → 1 record, corrupt → 0 record; captured envelope vẫn trong ±300s sau restart.

Đây không là forge signature, cũng không khẳng định remote caller tự có quyền sửa journal. Local fault/tamper/restart trong threat model durable replay là điều kiện cần xét. Phải phân biệt “chưa từng có journal” với “đã có nhưng đọc/parse thất bại”, từ chối ingest khi không bảo toàn replay guarantee hoặc có recovery policy được chứng minh không reset security state.

`security.rs:571,591` bỏ qua lỗi persist lockout/security state cần fault-injection; DPAPI bảo vệ confidentiality ở current-user scope không tự cung cấp crash durability hay replay integrity. Source dùng UI_FORBIDDEN/current-user, entropy và LocalFree; không thấy machine-scope flag. ACL inherited chưa được đo nhiều profile. DEV encrypt→exit→reopen thành công không chứng minh disk-full/permission-denied/partial write/crash atomicity hoặc OS reboot.

### 6.3 F08 — trạng thái service/revoke chưa là OS effect

Source đã đọc SCM/Run key và ownership thay vì hoàn toàn giả lập. Nhưng `revoke_unattended_access` ở `service_ctrl.rs:251–280` xóa Run key best-effort, đổi `self.state` Running→Stopped, đổi approve-mode/keyboard/clipboard/file/password config; đường này không thực hiện/kiểm tra SCM stop. FFI audit success “revoked” vì vậy không đủ chứng minh service thực đã stopped hoặc kết nối đang hoạt động bị ngắt. Sau restart cũng phải chứng minh unattended enabled/disabled đúng config persisted, không chỉ default state trong RAM.

Không đòi kill một service external không thuộc DAUVERSE. Gate đúng là ownership-aware observe/effect/reobserve và native evidence: owned service actual state, no collateral external service change, reconnect bị từ chối sau revoke, persistence qua reboot. Chưa có thực thi độc lập; không báo runtime cutoff PASS.

### 6.4 F11 — backup manifest validator nhận extras

IE-HELPER tách đúng ba hàm `Compute-FileSha256Hex`, `Test-PeBinaryHeader`, `Assert-BackupManifestIntegrity` khỏi script rollback, không dot-source script/body rollback. Fixture gồm hai file inert chỉ có minimal PE header để đáp ứng parser và một settings file; ba entry manifest hợp lệ.

Kết quả thực thi: baseline validator count **3**; thêm `unlisted-extra.bin` không có trong manifest → validator vẫn trả **3**, không reject. Static line233 `Copy-Item` copy recursively **toàn bộ backup**, không chỉ listed files. Vì vậy phần nội dung sẽ restore không bị manifest ràng buộc hoàn toàn. Đây là tái kiểm định residual F11, không tạo duplicate finding mới.

Quarantine/recovery path có cải thiện nhưng không đủ chứng minh rollback transactional mọi failure/restart path. Cần reject extra/missing/reparse và chỉ restore closure đã xác minh; test distinct **release A/B** với binary version/hash khác, dữ liệu/settings migration, fault trước/sau move/copy/restart. JSON sentinel trước/sau cùng SETUP không đạt yêu cầu đó.

### 6.5 F14 — Windows handle confinement giữ risk mở

Pre-open `Path::starts_with` canonical parent check có component semantics; không bỏ qua tiến bộ này. Nhưng post-open Windows handle guard ở `crypto_util.rs:591–618` dùng lowercase **string** `.starts_with(cleanroot)`. IE-MODEL cho root `E:\QA\allowed` và target `E:\QA\allowed-elsewhere\file.bin`: string check nhận dù khác component. `GetFinalPathNameByHandleW` với buffer 1024 chỉ được kiểm tra khi `len>0 && len<1024`; len0/fail hoặc yêu cầu buffer lớn hơn không đi qua confinement guard đó.

Leaf no-follow flag không tự khóa toàn bộ ancestor/parent against concurrent junction replacement. Chuỗi điều kiện race để vượt qua precheck tới target khác vẫn cần native proof; **reviewer không chạy NTFS race, không khẳng định đã ghi ra ngoài root**. Cần fail-closed khi handle path retrieval lỗi/truncated, so component-normalized final path, và chứng minh chống parent swap bằng native junction/symlink/oplock tests không ignored.

### 6.6 F16 — “tính SHA256” không phải “so SHA256 sender”

Single-file finalize có expected SHA optional và có khả năng so hash khi được truyền. Receive engine/batch path `transfer_guard.rs:528–580` tạo expected SHA **None**. `585–698` hash files nhận được, chặn staging/missing, so tổng size; không ràng buộc expected length cho mỗi file, không so expected sender digest. Không có expected SHA vẫn có trạng thái `LOCAL_SHA256_COMPUTED_SIZE_VERIFIED` và Completed.

IE-MODEL: `AAAA`→`BBBB` giữ cùng 4 bytes nhưng SHA khác; batch expected lengths [4,6], actual [2,8] vẫn tổng10. Đây là counterexample logic acceptance, **không phải packet mutation/transport exploit đã chạy**. Transport có bảo vệ khác không làm local digest trở thành expected content parity proof. Yêu cầu đóng: authenticated expected name/length/digest từng file từ sender được bind vào job, so trước success/ACK; negative same-size mutation/compensating lengths + live 2-PC transfer/resume/cancel tests. Không đổi tiêu chuẩn thành chỉ hash locally.

## 7. Các phép thử reviewer thực sự đã chạy

### 7.1 Inventory thực thi độc lập (không sản phẩm)

| Nhóm | Phép kiểm / kết quả | Phạm vi chính xác |
|---|---|---|
| Archive/hash | CRC + entry safety; expected inner/exe/report hashes; manifest hai chiều; recheck1389 | IV, chỉ đọc/extract vào E. |
| Git/source | bundle verify, strict fsck, tree/blob snapshot, submodule API, full diff/recovery | IV; bare verifier local, không checkout hook/build. |
| Signature/PE | Get-AuthenticodeSignature, CryptCAT membership + negative control, PE/export parse | IV/OS read-only; không LoadLibrary candidate, không service/catalog registration. |
| QA helper negatives | **10/10** reject đúng: missing manifest, digest mismatch, case duplicate; early exit0/1/2; missing DLL; missing log; tiny fake; TESTS_SKIPPED | IE-HELPER, AST-extracted functions. Process/module arguments là fixtures; không launch GUI. |
| QA helper positives | **3** positive controls nhận đúng: valid manifest; packaged original log; alive flag+2DLL names | Không gọi alive fixture là quan sát process sản phẩm. |
| QA helper limitation probes | Padded synthetic log >1100bytes+success banner accepted; unlisted extra accepted | Chứng minh giới hạn validator, không cáo buộc log thực giả. |
| Rollback validator | Valid3-entry fixture passes; unlisted extra vẫn passes | IE-HELPER. Không rollback/copy vào install location; không candidate EXE used. |
| Four source models | Float canonical collision; corrupt replay reset; Windows prefix/buffer branch; content/length parity counterexamples | IE-MODEL, không compiled Rust/native network/filesystem race. |
| Benchmark arithmetic | sign_us12.34 → serialized1.234 | IE-MODEL cho N01, không native timing measurement. |
| Syntax/inventory | 26 Python files AST parse; 10 JSON records parse; SBOM inventory; bounded diff secret patterns 0 hit | Parse/data inspection, không execute Python hooks hoặc exhaustive code/dependency audit. |
| PowerShell parse | 5/6 shipped PS1 parse dưới PowerShell5.1; build script dùng `??` của PS7 không parse trên PS5.1 | CI dùng pwsh; host không có pwsh. Đây là **parser compatibility limitation**, không kết luận CI build broken. |

Helper run cuối: **2026-11-26T01:46:16Z**; input recheck **2026-11-26T01:47:46Z**. Fixture/log/script nguồn hash được ghi trong JSON để tái kiểm. Các con số helper không cộng vào 7/7 native product gates.

### 7.2 Evidence có thể tái kiểm

- `independent_helper_tests.json`: tên hàm, nguồn/digest, error quan sát, controls/probes.
- `rollback_helper_probe.json`: isolated scope, fixture, count và extra acceptance.
- `independent_source_models.json`: raw model inputs/results/conditions.
- `additional_verification.json`: lock/JSON/SBOM/secret-pattern/test-summary và arithmetic N01.
- `powershell_ast_parse.json`, `python_ast_parse.json`: parser results kể cả limitation, không chỉ pass.
- Các script reviewer ở workspace root và `independent_audit/` được hash trong mục 13/manifest evidence. Không cần chạy lại full build hay sản phẩm để tái kiểm nội dung kết luận static.

## 8. Finding mới

### N01 — P2 — HMAC microbenchmark bị giảm số đo khoảng 10 lần

**Status:** OPEN; IV source + IE-MODEL arithmetic; không phải native benchmark hoặc lỗi primitive HMAC.

**Location:** `rc2_payload/SOURCE/src/dauverse/performance.rs:443–447,464`, được đưa vào delta RC1→RC2. `sign_us` đã là microseconds/operation: elapsed seconds ×1_000_000 /200. Field `hmac_event_sign_us` lại tính:

```rust
hmac_event_sign_us: (sign_us * 100.0).round() / 1000.0,
```

Nếu giữ rounding 2 decimals theo microseconds thì mẫu số tương ứng phải là100, hoặc chọn cặp hệ số nhất quán cho độ chính xác khác. Với input12.34us, RC2 serialize1.234us thay vì12.34us: tỷ lệ0.1 ngoài sai số rounding. Đây là lỗi biểu diễn đơn vị được xác nhận bằng arithmetic, không cần build/run candidate.

**Impact:** báo cáo overhead signing đẹp hơn thực tế khoảng10x, gây sai quyết định telemetry/capacity/acceptance. Không chứng minh native runtime chậm hay HMAC không an toàn. Scope label local microbenchmark vẫn đúng; label không sửa được numeric scaling.

**Remediation/verification cần cho candidate sau:** sửa scaling, unit test known values/rounding boundaries/unit consistency, chạy lại benchmark được phép và công bố raw elapsed/iterations/output. Không sửa mã trong nhiệm vụ này. Evidence `additional_verification.json:new_N01_hmac_benchmark_scaling`, `independent_audit/diffs/src__dauverse__performance.rs.diff`, full diff và source line.

Không tách các residual của F01/F09/F11/F14/F16 thành finding mới trùng lặp. Unsigned binary, thiếu hardware/E2E hay 403 logs được báo là known limitation/blocker, không gán thành compromise mới. Không phát hiện thêm P0 bằng các kiểm tra đã thực hiện; không có nghĩa không thể còn lỗi khác.

## 9. Feature acceptance và remaining blockers thực tế

| Phạm vi | Developer evidence | Kết quả independent / gate còn thiếu |
|---|---|---|
| Artifact/source/provenance closure | Archive/bundle/manifests/provenance | **IV PASS** cho byte/source closure đã nêu, không functional PASS. |
| Windows install/upgrade/uninstall/coexistence | Single-runner install/teardown và cmd.exe fixture | **BLOCKED / native NOT_TESTED độc lập**. Cần disposable guest được phép, real running external và owned service, failure/reboot scenarios. |
| Remote desktop hai máy | Wiring/source/local startup | **BLOCKED / NOT_TESTED**: hai endpoints thật, authentication, P2P/relay, reconnect, disconnect/network loss, input, VI/IME, audio/WASAPI, multimonitor. |
| Clipboard/Explorer | Policy unit tests/settings persistence | **BLOCKED / NOT_TESTED**: hai máy text/html/image/files, allow/deny policy, IME paste/Explorer integration, persistence thực. |
| File transfer | Guard unit/FFI claims, local finalize | **BLOCKED / NOT_TESTED**: sender/receiver digest+length mỗi file; empty/large/multi/resume/cancel/corruption; F14/F16 còn mở. |
| NVENC/RTX3060/FPS/latency/VRAM | Local CPU scan/HMAC/loopback microbench | **BLOCKED / NOT_TESTED**: GPU encode/decode thực, end-to-end SLO, fallback/load. Không chuyển estimated headroom thành measured remote FPS. |
| Headless native | Policy/state blocked/unapproved, catalog valid | **BLOCKED / NOT_TESTED**: driver installation được phép, no-monitor activation/capture, topology restore, failure/reboot/GPU lab. Không có host driver action trong review này. |
| Unattended access | Config/state/service ownership source, DEV selected checks | **BLOCKED / NOT_TESTED**: pre-login service, OS autostart/reboot, credential gating/revoke/active-session cutoff; F08 truth gap. |
| DPAPI/PIN/security persistence | DEV 3-process reopen, corrupt-vault negative | **BLOCKED độc lập** cho native DPAPI/fault/reboot/multiprofile; source verified không thay native proof. Disk full/permissions/crash tests **NOT_TESTED**. |
| FFI production failure UX | Default unbound test; mock-enabled UI tests | **BLOCKED / NOT_TESTED** native wrong DLL/arch/export, no false success on actions; compile-time mock isolation chưa chứng minh. |
| Smart Power | Dry-run/source/unit guards, DEV local UDP test | **BLOCKED / NOT_TESTED** shutdown/sleep/reboot/WoL thật và interlocks với job/transfer/ComfyUI; reviewer không đụng DAUVERSE AI. |
| Hunonic SK02 | DisabledSmartPlugAdapter, mock-only route | **BLOCKED**, không có approved vendor/device/API evidence trong hồ sơ để nghiệm thu live. Không khẳng định độc lập vendor toàn cầu không có API. |
| Windows path confinement | No-follow leaf/source checks, ignored symlink tests | **NOT_TESTED** native junction/symlink/oplock concurrent races và dài/failing final-path API. F14 không được đóng bằng Linux/source model. |
| Signed updates/trust | Spoofed status denied; current binaries unsigned | **BLOCKED / NOT_TESTED** signed positive/revoked/expired/metadata trust/antirollback delivery; auto-update phải tiếp tục bị chặn theo policy. |
| Privileged/multi-user attack surface | Bounded source review | **NOT_TESTED** named-pipe/IPC DACL adversarial multiuser, full privilege-boundary fuzz, full dependency CVE/secret audit. Không tự certify ngoài phạm vi. |
| Reproducible build | Toolchain/lock/provenance recorded | **NOT_TESTED** independent rebuild theo giới hạn người dùng; no signed source→binary attestation. |

Các blocker không được “waive” bằng pilot label. Các hàng BLOCKED độc lập có thể có DEV PASS một scope hẹp; không xóa DEV evidence nhưng cũng không đổi nguồn gốc bằng chứng.

## 10. Điều kiện xem xét lại / bàn giao cho developer

1. **Khắc phục residual source/validator:** F01 canonical exact consumed semantics; F09 journal corruption fail-closed; F11 complete restore closure; F14 fail-closed final handle path + boundary/race protection; F16 authenticated per-file sender length/digest parity. Chốt F07 persistence fault policy và F08 service/revoke OS truth, không chỉ audit success/in-memory transition.
2. **Sửa N01** cùng regression test cho đơn vị; công bố lại benchmark, không sử dụng số đo sai làm SLO evidence.
3. **Không false PASS harness:** giữ immutable original log/manifest; provenance của log phải độc lập hơn size/banners. GUI liveness/module presence không được gọi là interactive feature acceptance. Phân biệt actual render/action/export/architecture failures; test mock được label rõ và không reachable trong production theo thiết kế được kiểm chứng.
4. **Nộp candidate mới có identity riêng:** commit/artifact/build provenance/manifests/logs updated đồng bộ; giữ nguyên báo cáo Codex gốc/hash làm historical anchor. Không chỉnh báo cáo gốc hoặc acceptance để tạo PASS. Recovery cuối RC2 hiện đáp ứng scope, nhưng sửa lỗi tiếp theo đương nhiên là product change và cần delta re-review.
5. **Cung cấp native evidence trong lab riêng được chủ sở hữu cho phép**, không trên host này: installer/service/driver lifecycle, fault/reboot/multiprofile; distinct-release rollback; FFI missing/wrong exports/arch; hai endpoints Windows; NVENC và Headless no-monitor; actual unattended revoke và Smart Power interlocks. Dừng destructive action khi không có approval; không hạ scope thành single-host microbench.
6. **Đạt chất lượng evidence:** raw timestamp/build/commit/host/profile/device identity, reproducible commands, positives/negatives và skipped count; sender/receiver digests, measured telemetry. Nếu provider logs inaccessible, ghi rõ và cung cấp cách xác minh, không tự phong attestation.
7. **Independent Re-QA lại sau sửa.** Chỉ cân nhắc verdict **CONDITIONAL GO FOR CONTROLLED WINDOWS PILOT** sau khi các release/pilot-blocking lỗi và scope được xác minh; chưa có quyền cấp verdict đó ở RC2 này. Mọi pilot vẫn cần kill-switch/rollback/controlled audience phù hợp, không tự động là production release.

Không có hành động khắc phục sản phẩm nào được reviewer thực hiện trong nhiệm vụ này; đây là yêu cầu cho candidate tiếp theo, không phải cam kết lỗi đã sửa.

## 11. Evidence map và giới hạn suy luận

| Kết luận | Evidence reviewer / nguồn liên quan |
|---|---|
| Expected hashes và manifest hai chiều | `outer_zip_audit.json`, `payload_zip_audit.json`, `manifest_verification.json`, `initial_manifest_verification.json`, `final_input_recheck.json` |
| Bundle/snapshot/submodule | `bundle_verify.txt`, `git_fsck.txt`, `source_snapshot_verification.json`, `source_extras_verification.json`, `submodule_verification.json`, upstream tree JSON |
| Full delta và final recovery | `rc1_rc2_full.txt`, `diff_inventory.json`, `diffs/`, `whole_diff_review_ledger.json`, `final_recovery_diff.txt`, `final_recovery_verification.json` |
| Provider run/job/artifact identity | Ba `github_*45720572543.json`; `provider_logs_access_status.txt` ghi403 |
| Chữ ký/catalog/static binary | `authenticode_readonly.json`, `catalog_membership_readonly.json`, `pe_static_inspection.json` |
| F02/F11 independently executed helpers | `independent_helper_tests.json`, `rollback_helper_probe.json`; root `independent_helpers.ps1` |
| F01/F09/F14/F16 source models | `independent_source_models.json`; root `independent_models.py` |
| N01, syntax/SBOM/pins/bounded secrets | `additional_verification.json`, parser JSON; root `additional_verification.py` |
| 7/7 và test scope DEV | `rc2_payload/EVIDENCE/`, `rc2_payload/LOGS/`, QA matrices/handoff và SOURCE test harness |

Evidence reviewer ở cột tên ngắn nằm trong `independent_audit/`, trừ khi chỉ rõ root hoặc `rc2_payload/`. JSON/lưu log là hỗ trợ của **một báo cáo tổng hợp duy nhất này**, không phải báo cáo verdict thứ hai. Một script có mặt không có nghĩa mọi function trong đó đã được chạy: xem đúng scope IE-HELPER/IE-MODEL.

Các giới hạn còn lại: không rebuild; không host install/native execution; provider raw logs403; upstream driver ZIP không redownload; không full portable/dependency execution closure; unsigned commit/application; parse không là semantic runtime validation; mô hình không là exploit; license inventory không là legal opinion; không CVE/SCA/fuzz exhaustive. Các giới hạn này công khai để downstream không diễn giải quá mức kết quả PASS tĩnh.

## 12. Phụ lục — toàn bộ 50 file thay đổi RC1 → RC2

Mỗi dòng dưới có diff byte/hash/hunk trong `diff_inventory.json` / `whole_diff_review_ledger.json`. Group cho biết phạm vi static review, không tuyên bố runtime acceptance PASS.

| # | Git path | Added | Deleted | Review scope |
|---:|---|---:|---:|---|
| 1 | `.github/workflows/dauverse-windows-build.yml` | 123 | 41 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 2 | `ARTIFACTS/SHA256_MANIFEST.txt` | 25 | 16 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 3 | `ARTIFACTS/evidence/ai_bridge_and_secret_scan.json` | 42 | 10 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 4 | `ARTIFACTS/evidence/benchmark_results.json` | 5 | 5 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 5 | `ARTIFACTS/evidence/dauverse_unit_security_tests.log` | 19 | 13 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 6 | `ARTIFACTS/evidence/flutter_dauverse_ui_tests.log` | 158 | 6 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 7 | `ARTIFACTS/evidence/rc2_base_fs_tests.log` | 347 | 0 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 8 | `ARTIFACTS/evidence/rc2_security_negative_matrix.json` | 41 | 0 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 9 | `ARTIFACTS/evidence/release_ffi_smoke_test.json` | 338 | 184 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 10 | `Cargo.toml` | 1 | 0 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 11 | `FEATURE_ACCEPTANCE_MATRIX.md` | 21 | 32 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 12 | `FINDINGS_REMEDIATION_MATRIX.md` | 243 | 0 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 13 | `HUONG_DAN_BOSS.md` | 26 | 37 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 14 | `LICENSE_COMPLIANCE_REPORT.md` | 3 | 2 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 15 | `QA/CODEX_REQA_WINDOWS_RC2_HANDOFF.md` | 105 | 0 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 16 | `QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md` | 466 | 0 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 17 | `SHA256_MANIFEST.txt` | 25 | 16 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 18 | `TESTS/test_e2e_hooks_and_secrets.py` | 474 | 103 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 19 | `THIRD_PARTY_NOTICES` | 22 | 3 | WORKFLOW_MANIFEST_DEPENDENCY_OR_DOCUMENT_DELTA_REVIEW |
| 20 | `flutter/lib/dauverse/bridge/dauverse_bridge.dart` | 165 | 56 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 21 | `flutter/lib/dauverse/dauverse_shell.dart` | 26 | 0 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 22 | `flutter/lib/dauverse/screens/dashboard_screen.dart` | 1 | 1 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 23 | `flutter/lib/dauverse/screens/devices_and_session_screens.dart` | 1 | 1 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 24 | `flutter/lib/dauverse/screens/power_security_ops_screens.dart` | 69 | 24 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 25 | `flutter/lib/dauverse/widgets/floating_toolbar.dart` | 1 | 1 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 26 | `flutter/test/dauverse_ui_test.dart` | 44 | 8 | TEST_OR_DEVELOPER_EVIDENCE_REVIEW; not independently rerun candidate suites |
| 27 | `installer/nsis/dauverse_setup.nsi` | 122 | 22 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 28 | `installer/nsis/dauverse_setup_helper.ps1` | 154 | 0 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 29 | `libs/base/src/fs.rs` | 84 | 7 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 30 | `scripts/hooks/claude_code_hook.py` | 41 | 9 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 31 | `scripts/hooks/codex_notify_hook.py` | 37 | 7 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 32 | `scripts/hooks/dauverse_job_wrapper.ps1` | 72 | 7 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 33 | `scripts/windows/build_windows_release.ps1` | 175 | 34 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 34 | `scripts/windows/package_complete_rc2_qa_archive.ps1` | 299 | 0 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 35 | `scripts/windows/rollback_windows_release.ps1` | 218 | 20 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 36 | `scripts/windows/verify_and_package_windows_rc.ps1` | 1000 | 334 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 37 | `src/dauverse/ai_bridge.rs` | 384 | 46 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 38 | `src/dauverse/crypto_util.rs` | 328 | 24 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 39 | `src/dauverse/ffi.rs` | 207 | 29 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 40 | `src/dauverse/headless.rs` | 278 | 28 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 41 | `src/dauverse/mod.rs` | 243 | 55 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 42 | `src/dauverse/notifications.rs` | 41 | 8 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 43 | `src/dauverse/performance.rs` | 59 | 12 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 44 | `src/dauverse/security.rs` | 566 | 52 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 45 | `src/dauverse/service_ctrl.rs` | 206 | 24 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 46 | `src/dauverse/session_tools.rs` | 6 | 0 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 47 | `src/dauverse/smart_power.rs` | 72 | 4 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 48 | `src/dauverse/transfer_guard.rs` | 285 | 43 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 49 | `src/dauverse/update_center.rs` | 112 | 19 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |
| 50 | `src/ui_cm_interface.rs` | 33 | 12 | STATIC_SECURITY_AND_CALL_FLOW_REVIEW; runtime NOT_TESTED except explicitly extracted QA helpers |

## 13. SHA256 receipts

### 13.1 Delivery/evidence quan trọng

Hash dưới đây tính lại từ byte đã nhận, không chép nguyên claim developer. Full delivery closure xem root manifest đã được reviewer xác minh hai chiều.

| Path (workspace-relative) | SHA256 |
|---|---|
| `rc2_payload/SHA256_MANIFEST.txt` | `c7c568e3b3ddbb11c7a548a1d123a3706d2f2fcd7a4f77c41fa82d214b415793` |
| `rc2_payload/BUNDLE/DAUVERSE_REMOTE_DESKTOP_V1_RC2.bundle` | `3fd64d094d901efe98fa75ede07d05f1cfbc55961b5f19f98a12653feb1e8efd` |
| `rc2_payload/RELEASE/librustdesk.dll` | `5899b44c1ef2d8f9fe82f3f00858c317749a076342378304e0660a1ba9e1d7fc` |
| `rc2_payload/RELEASE/dylib_virtual_display.dll` | `671dc0b0915957700f9cd7c8ef513fd45d234b83c7540534c9613392cdf97216` |
| `rc2_payload/RELEASE/usbmmidd_v2/x64/usbmmIdd.dll` | `dc135d675127113915a7e5aa9fe57c84edad6be41d0890b265ef124ab26ea9e3` |
| `rc2_payload/RELEASE/usbmmidd_v2/usbmmidd.cat` | `470149c4cf9970ba59070aa7c9409c9f63a15727de99bab53e7e51f55310779f` |
| `rc2_payload/RELEASE/usbmmidd_v2/usbmmIdd.inf` | `a8750ca15a86742f3012886c9932bb974158cd2d9779cf891c730d976a47726a` |
| `rc2_payload/RELEASE/usbmmidd_v2_License.txt` | `44c73fc4110979899dbb5054662de581f7d4350939f19bb2d50574f613314ba2` |
| `rc2_payload/RELEASE/BUILD_PROVENANCE.json` | `3a6a2ab8b2653102b2565842fb01e4eadd1c00fccd11190d7b70dc89c5d6fb30` |
| `rc2_payload/RELEASE/DRIVER_PROVENANCE_AND_LICENSE.json` | `58bfacff8a56feb2dbab49ef0c32c282430bfc20bb7e23b619084c614421b351` |
| `rc2_payload/RELEASE/INITIAL_BUILD_SHA256_MANIFEST.txt` | `cd5438e98c216ff1fd86e880ab4e61de45fb42d352a7551f1d6301a8294d0333` |
| `rc2_payload/RELEASE/SIGNING_STATUS.txt` | `edc6fd0b97c62240c63f0da1a3f2f6579c60e0c791572a143dc2b31e2c8de893` |
| `rc2_payload/QA/FINDINGS_REMEDIATION_MATRIX.md` | `f7f9bc977e57fce6abeac2ccd60575a1cbc75cf849a88089f2c10dc45f1332ba` |
| `rc2_payload/QA/CODEX_REQA_WINDOWS_RC2_HANDOFF.md` | `e17fed39a89d18fcd0551487ed52ac87a69a9a3862baaa2f4ea03d5b03cdbb3d` |
| `rc2_payload/DOCS/FEATURE_ACCEPTANCE_MATRIX.md` | `9746c2e4fbdaea2f966e7f48d4c9ca8e5a10d258378738b15b6151153a97543f` |
| `rc2_payload/EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json` | `ef901ed719ee3e63a61581d835a18519ab294f166eb104e1e9139a204734246e` |
| `rc2_payload/EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.md` | `92e150114875614620162d6ba6bb747155f4011408aa2b20284ef800564b2255` |
| `rc2_payload/EVIDENCE/QA_HARNESS_NEGATIVE_SELFTEST.json` | `d86db46c54c8ff0951544e3390e564ec35eea10719314da0b7e9f811498bc168` |
| `rc2_payload/LOGS/WINDOWS_NATIVE_BUILD.log` | `af2c2b1638f8e4fbdcaa030bce32a0b0ffad28ded484f127235473b7e7d2d745` |
| `rc2_payload/LOGS/WINDOWS_RC_VERIFICATION.log` | `e7334913816bbd6a4d41729f9f63be0c932e579c36db28af99a3ac2767666215` |
| `rc2_payload/LOGS/GITHUB_ACTIONS_BUILD_CONSOLE.log` | `89d693c8038caea872e2e9a924f72b51cf8329a853941493923e489280ec921f` |
| `rc2_payload/LOGS/GITHUB_ACTIONS_VERIFY_CONSOLE.log` | `ba650addcd359b104f0ad95060bcfec3501e12dbe6467070f60bcd4b3c791d99` |
| `rc2_payload/LICENSES/SBOM.spdx.json` | `154b2c1089c2f7aff2b08f8121804dd24cf1c403b866074afcbc3297161b2eae` |

### 13.2 Reviewer receipts và scripts

| Path (workspace-relative) | SHA256 |
|---|---|
| `independent_audit/outer_zip_audit.json` | `62bdf97fb4c214e6334de1f77712fcec6415788b67cb1e7147177ffd751fa106` |
| `independent_audit/payload_zip_audit.json` | `512e6b79d7823057ce211b34e664553d397ed291461a67f5c40b55bd65eb71d0` |
| `independent_audit/manifest_verification.json` | `e550aaba3793e27bb1018839f79fb9261c29d9004fb8c6fb70e9f78bdc3605c0` |
| `independent_audit/source_snapshot_verification.json` | `71d78faf5f9daebf9448d9faf3c71669f2876cf491a26426b9ee278de9877027` |
| `independent_audit/submodule_verification.json` | `7cb9b4f03bd3c0905bb9ad0cace43c20b2278cee4bc6f4f9c35565d247fdf5e6` |
| `independent_audit/github_run_45720572543.json` | `6583fe57add299c7440779eccf468739c8b5f4afafc055d2e4595a38a55f94c4` |
| `independent_audit/github_jobs_45720572543.json` | `42e8e96df0f7c54c8dc0c40ec18e0835ca5aad9ce6e7f5a7a3441aab4885d4dd` |
| `independent_audit/github_artifacts_45720572543.json` | `8527a40ffc25caae5af6404fdd053cdaad97bbea366202a75bfe3ad87c0becaa` |
| `independent_audit/provider_logs_access_status.txt` | `75c363de1ca2a69bf369fa63abd1f4d6b026c6ba1bad641875f083d4f1317350` |
| `independent_audit/authenticode_readonly.json` | `f0e6cf8a1e30b6a4ac39c4e75e71b9b82d384f7d21996262300e938252bd02e8` |
| `independent_audit/catalog_membership_readonly.json` | `181ed00f976dcc9a2c51269ca0ef16bcd6e48b745343bf3a2a1b8de3cae5bf23` |
| `independent_audit/pe_static_inspection.json` | `f741021ccaaa7d2b9e2a5630d3527e8ec5f007d5e08d40017020552539eb2dd9` |
| `independent_audit/independent_helper_tests.json` | `4fa479fa310ebd1f3e56bb19020c3490c5e91a48679933c52f262895972aeeda` |
| `independent_audit/rollback_helper_probe.json` | `7455f4b2c455900b8c5e9c1e0842626284374fdd96f6951b6d6be03aa004aa0c` |
| `independent_audit/independent_source_models.json` | `0fbbcce6aa16249bc17fb88558c164e55fd50f13273c6d201093a5d1829f3ac5` |
| `independent_audit/additional_verification.json` | `4755c38e43391ceadb1d8bd68ec85886718b5dcc88b3a0164834ce954c9f795c` |
| `independent_audit/final_recovery_verification.json` | `812a1aa92439a914f2d0754017a08f6de26f2e36e8e5cbd3332afdcc3fc79891` |
| `independent_audit/whole_diff_review_ledger.json` | `dff65459b8436cd7822be3361df8f0ffbd0f0a926c917f8da70fe59f1dd2113f` |
| `independent_audit/final_input_recheck.json` | `567ef9225c55deba1b603922568f81cc8cc64bfefc005dc9b98bc3058fc869d0` |
| `additional_verification.py` | `e40f44f9721822625fba2cfa2c03abd81d503734cc02c16ff9cf8a65f8670630` |
| `audit_corrections.py` | `27986430e6e80604e4100f387afbac21bfa06a592ccba8031187d25bc36c5d5e` |
| `audit_extended.py` | `b7c84eefa465477126b2f520d40247f03881f073f6803f3b35a618f33473ae5b` |
| `audit_integrity.py` | `3ff265840903ca8ea25a9905f88366a76749c5b98f67b6ea897570c898851e88` |
| `audit_zip.py` | `149b307af1c703d773e121c39a326c65193fe3f2727a42139427c1ba9399e05e` |
| `finalize_audit.py` | `d30a776e9e2d9715f6344a34512225d4e25254242f0383b7f20250d8a752c56d` |
| `finalize_report_receipt.py` | `9239d2e2ee23d80bd78ddfd42063c1b259e0db228561771e47151d1faf6dd4f2` |
| `independent_catalog.py` | `311f3e9585655e605b76fb1d356845f00f2ca187ce8cb674046179b92feb1ef0` |
| `independent_helpers.ps1` | `c6ac42bee64f9967e0c1c0350d3c70215d92daad5826818f0a9e2a2213ed3a39` |
| `independent_models.py` | `6382078b1227f1129cff22844e06e2f4ab80a446269940f06212777ef5b600bf` |
| `independent_pe.py` | `8da734f2d398e54493e77908645b7dd4fd3ecbeb19529cfe75b7e24cbfd228eb` |
| `read_lines.py` | `5b10cb123fb738d1633a4c4902ca67031745c28738c52e07579c0dbfa29b1229` |

`REVIEW_EVIDENCE_SHA256_MANIFEST.txt` gồm **95 files** (reviewer records/per-file diffs/scripts), SHA256 **`005a6abcdb4c235f699154a5f4e1582ee2827550233561f41632c36b8565723b`**. Loại bare Git object store và fixture directories để tránh nhiễu; input delivery có manifest riêng. Manifest reviewer không bao gồm chính nó hoặc báo cáo để tránh checksum vòng. Không có ý nghĩa chữ ký số.

Báo cáo hoàn chỉnh có checksum ngoài file: `DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md.sha256`. Không nhúng self-hash vào chính báo cáo; checksum đó được tính **sau khi** chốt toàn bộ nội dung. Người nhận có thể dùng `Get-FileHash -Algorithm SHA256` cho báo cáo/receipts và so manifest. Không cần chạy executable để kiểm tra hash.

## 14. Final verdict / sign-off

# FAIL

**RC2 chưa đạt independent acceptance để cho controlled Windows pilot. Production tiếp tục LOCKED.**

- **Đạt IV:** expected inner archive/SETUP/PORTABLE/original-report hashes; safe archive checks; manifest hai chiều; bundle/object integrity; exact source/submodule content; final recovery chỉ workflow/manifests; provider CI identity; signature/catalog observations trong scope đọc-only.
- **Chưa đạt:** residual F01/F07/F08/F09/F11/F14/F16 và giới hạn acceptance F02; N01/P2 mới. Không tự đóng những finding khác có source fix nhưng thiếu native proof.
- **Không được suy diễn:** DEV 7/7 không phải independently executed product PASS; helper/model không phải native exploit hoặc remote-session test; catalog Valid không phải monitorless runtime certification; CI success không phải Production Approved.
- **Vẫn BLOCKED/NOT_TESTED:** hai máy, NVENC, Headless native, unattended/reboot, Smart Power thực tế, signed-update positives/fault tests và các scope cụ thể trong mục9.

Không sửa source, không rebuild, không chạy/cài candidate EXE trên máy thật, không cài service/driver, không đổi BIOS/firewall/router, không tác động DAUVERSE AI, không tạo workspace ổ C và không sử dụng dịch vụ trả phí. Chỉ có review/readonly verification/helper-model execution trong phạm vi nêu trên. Yêu cầu tiếp theo là developer nộp candidate khắc phục cùng evidence phù hợp, sau đó independent review lại; **không phải cho phép triển khai production**.
