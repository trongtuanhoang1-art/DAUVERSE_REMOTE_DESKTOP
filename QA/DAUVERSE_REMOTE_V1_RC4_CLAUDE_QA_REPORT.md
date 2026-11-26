# DAUVERSE REMOTE DESKTOP V1 — RC4 Targeted Independent QA Report

- **Task ID:** DREMOTE-V1-CLAUDE-QA-012
- **Reviewer:** Claude (independent QA & security reviewer, thay Codex theo chỉ đạo của Boss)
- **Developer:** ANTIGRAVITY CLOUD
- **Production:** LOCKED (báo cáo này KHÔNG tuyên bố Production Approved)
- **Phạm vi:** delta RC3 `821f1dab…` → RC4 `98037347…` (32 file, +5223/−900)
- **Phương pháp:** đọc nguồn tĩnh toàn bộ delta ưu tiên theo B01–B05/Q01–Q03/F01; kiểm tra toàn vẹn hash; PowerShell 5.1 AST parse. Không build, không chạy EXE, không CI, không sửa mã, không commit/push.
- **Giới hạn:** workspace này không có Rust toolchain → test Rust của Developer được đánh giá qua log đã commit, KHÔNG được chạy lại độc lập.

---

## 1. FINAL VERDICT

# **FAIL_SOURCE_GATE**

Chín hạng mục mục tiêu (B01–B05, Q01–Q03, F01) đều **đã được đóng ở mức source**, nhưng review độc lập phát hiện **1 lỗi hồi quy mới P2 (RC4-N01)** nằm ngay trong đường mã mà B02 đã sửa: **resume phía người gửi (reader job) bị hỏng**. Lỗi không phá tính toàn vẹn dữ liệu (SHA-256 vẫn chặn file hỏng) nhưng làm hỏng chức năng resume upload/serve-download, và là lỗi do chính RC4 đưa vào (RC3 không có). Sửa nhỏ (vài dòng + 1 test). Đề nghị RC5 chỉ gồm delta nhỏ này; tôi (hoặc Codex) review lại **chỉ delta** là đủ để chuyển PASS — các phần còn lại không cần kiểm lại.

Không có source blocker nào khác. Không có build blocker nào được xác định bằng phân tích tĩnh (xem §8).

---

## 2. Baseline integrity — PASS

| Mục | Kết quả |
|---|---|
| Repo / branch | `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP`, clone vào `E:\DAUVERSE_REMOTE_DESKTOP\QA\RC4_CLAUDE_QA_012\src` |
| HEAD | `980373472ae17b869f273b7544336b133ca3ce86` — khớp |
| Submodule `libs/hbb_common` | `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb` (gitlink trong tree) — khớp; không có diff submodule |
| Cargo.toml / Cargo.lock / libs/base/Cargo.toml | 0 thay đổi → không thêm crate; `winapi` đã có feature `fileapi` cho code Windows mới |
| RC4 Handoff SHA-256 | `271c1311…9b9462` — **khớp** |
| `SHA256_MANIFEST.txt` (= `ARTIFACTS/SHA256_MANIFEST.txt`, giống hệt) | `f84136d3…04bc92` — **khớp** |
| Codex RC3 report SHA-256 | `d7bf8f93…8e61ad` — **khớp** (cả bản trong repo và bản lịch sử RC3_SOURCE_REVIEW_008, không bị ghi đè) |
| Manifest 75 dòng | **75/75 khớp** khi đối chiếu với blob Git (LF) |

Lưu ý phương pháp: working tree Windows của tôi có CRLF do `core.autocrlf=true` cấp hệ thống, nên đối chiếu manifest với file trên đĩa cho 60/75 "lệch". Đây là hiện tượng CRLF, không phải lỗi gói; đối chiếu theo blob thì 75/75. Các file được khóa `-text` (3 báo cáo QA, 2 handoff, 2 manifest) khớp cả trên đĩa. Workflow chỉ kiểm hash các file `-text`, nên không bị ảnh hưởng.

---

## 3. B01–B05 disposition

| ID | Disposition (độc lập) | Căn cứ |
|---|---|---|
| **B01** manifest Windows | **CLOSED-SOURCE** | `New-ReleaseManifestLines` sinh manifest `Initial` (loại 2 manifest) và `Final` (chỉ loại `SHA256_MANIFEST.txt`); `Assert-ManifestFileValid` có `ManifestRole`, ở `Final` bắt buộc `INITIAL_BUILD_SHA256_MANIFEST.txt` được liệt kê và hash-verify; bộ sinh của `build_windows_release.ps1` bước 11 và bước [7/7] của verify cùng dùng layout Final → hết lệch đếm 2≠1. Có test dương (3 entry) và âm (thiếu initial manifest, bad hash, duplicate, extra). Final manifest được sinh **sau** khi copy mọi transcript vào ReleaseDir. |
| **B02** confinement/staging | **CLOSED-SOURCE cho phạm vi hardlink/staging — kèm lỗi hồi quy mới RC4-N01 (§6)** | `prepare_clean_exclusive_staging_slot` kiểm `links==1` read-only **trước** khi unlink; `create_exclusive_staging_file_no_follow` dùng `create_new` + `O_NOFOLLOW`/`FILE_FLAG_OPEN_REPARSE_POINT` rồi kiểm lại single-link + confinement trên handle đã mở; `.digest` cũng đi đường exclusive; `ensure_destination_safe_for_overwrite` chặn đích hardlink/reparse; fresh/resume download cùng helper; `remove_download_file` không xóa staging hardlink. Test victim 43 byte có trong log (`27 passed`). Kịch bản truncate victim của Codex nay bị từ chối trước khi chạm byte nào. |
| **B03** emergency revoke | **CLOSED-SOURCE** | Registry `live_engine_registry` + `LiveEngineConnectionGuard` giữ trong `Connection::start` (Drop = ACK qua `Condvar`); `revoke_all_local_engine_connections` đặt cờ, gửi `SwitchPermission(false)` + `Close`, kick CM, fail ledger, **chờ ACK** hoặc trả `ENGINE_REVOKE_DISCONNECT_TIMEOUT` + latch từ chối. Latch được đặt **trước** snapshot và `register_live_engine_connection` đọc latch → không có khe race đăng ký muộn. Cổng kiểm tra `is_dauverse_revoked()` ở keyboard/clipboard/audio/file/`on_message`/`handle_input`/port-forward/authorize. IPC `DauverseEmergencyRevoke` có ACK đồng bộ; dịch vụ SCM chỉ dừng khi `owned==Some(true)`, dịch vụ ngoài giữ nguyên (F03 được bảo toàn). |
| **B04** cấu hình bền | **CLOSED-SOURCE** | `read_durable_config2_at` đọc từ đĩa (no-follow), lỗi stat/UTF-8/TOML/schema/`trusted_devices_v2` sai kiểu → Err + latch; chỉ sửa bảng `options`, giữ nguyên `unlock_pin`/`trusted_devices(_v2)`/`socks` và **xác minh lại sau ghi**; ghi tạm `0o600`+fsync+rename; readback đĩa + `Config2::get_for_sync()`; rollback bộ nhớ khi `!conservative_deny`. Nay `status()`/dashboard/clipboard policy cũng đi qua đường này. |
| **B05** transfer identity | **CLOSED-SOURCE** | `EngineTransferIdentity{session_scope, conn_id>0, direction, engine_job_id}` + `generation` đơn điệu; `validate()` từ chối `conn_id<=0`; không còn helper unscoped nào trong mã (grep sạch); verify chụp snapshot rồi commit bằng `commit_engine_job_with_cas` (từ chối nếu có generation mới hơn/hủy); phiên cũ bị đánh dấu superseded; `try_finalize_write_files() -> Result` được kiểm **trước** `fs::new_done`; CM kiểm `cm_conn_id` khớp payload; client có scope riêng theo `Remote` + guard premature `Done`. E2E C-ABI (peer A hỏng/peer B hợp lệ cùng job id 1) có trong test. Xem N03 về default FFI. |

## 4. Q01–Q03 disposition

| ID | Disposition | Ghi chú |
|---|---|---|
| **Q01** build evidence | **SOURCE_HARDENED — raw-log gate vẫn bắt buộc** | `Invoke-Checked` pipe native stdout/stderr qua `Write-Host` để transcript bắt được; validator yêu cầu theo thứ tự `Finished \`release\` profile` ×2 và `Output: "` của NSIS, có test âm "đủ marker nhưng không có output compiler". Đây vẫn là kiểm tra **cấu trúc**, không chứng minh được nguồn gốc; việc đối chiếu với log gốc của GitHub Actions là bắt buộc khi có CI (Developer cũng khai như vậy). Không nâng lên PASS tuyệt đối. |
| **Q02** NSIS | **CLOSED-SOURCE** | Workflow ghi đường dẫn đã xác minh v3.11 ra file, truyền `-MakensisPath` + `DAUVERSE_MAKENSIS_PATH`; `Resolve-PinnedMakensisExecutable` từ chối đường dẫn sai phiên bản (không rơi âm thầm sang PATH) và kiểm lại version ngay trước khi gọi; fallback portable chỉ khi không có pin và có cờ rõ ràng. `Set-Content -Encoding UTF8` chạy trong `pwsh` 7 (không BOM) nên `cat` trong bash an toàn. |
| **Q03** trạng thái transfer | **CLOSED (scoped)** | Upload ra ngoài ghi `SENDER_STREAM_EOF_CHECKED_UNVERIFIED_RECEIVER`, `verified_sha256=None`, không bao giờ gắn `SENDER_SHA256_VERIFIED`; sender cũ thiếu SHA bị từ chối trước khi ghi; yêu cầu nâng cấp đồng bộ RC4↔RC4 được nêu rõ. |
| **F01** chữ ký | **CLOSED-SOURCE (preserved + tightened)** | `sign_event_envelope_checked` kiểm nonce ≥8 và dùng `canonical_signing_bytes_checked`; `sign_with_runtime_secret` trả `Result`; hai hàm raw chỉ còn `#[cfg(test)]` và mọi nơi gọi chúng đều trong test → không phá build thường. |

---

## 5. Regression assessment

- **10 finding CLOSED-SOURCE (F01, F03–F06, F09, F10, F12, F13, N01):** diff chạm duy nhất F01 (đã xét). Các file F03/F04/F05/F09/F10/F12/F13 không đổi trong delta (service ownership giữ nguyên trong revoke). Không thấy hồi quy.
- **7 finding còn cần xác minh (F02, F07, F08, F11, F14, F15, F16):** F02/F07/F08/F14/F15 → SOURCE_REMEDIATED theo B01/Q01/B04/B03/B02/Q02 như trên. **F16 bị ảnh hưởng bởi RC4-N01** (resume). F11 giữ nguyên `PARTIAL-NATIVE`: handoff gán nhãn trung thực `SIMULATED_BINARY_OVERLAY` / `PASS_SIMULATED_BINARY_OVERLAY_PARTIAL_NATIVE`; đồng ý, không được nâng thành A/B thật.
- Số lượng test: base 27/27 và dauverse 33/33 **khớp log đã commit** (có đủ tên test ft010_b02/b03/b04/b05). Linux E2E, secret scan 1197 file (`PASS_ZERO_SECRETS`), manifest 75/75: nhất quán. **Tôi không chạy lại các test này.**
- PowerShell 5.1: 6 file `.ps1` parse bằng `Parser.ParseFile` trên Windows PowerShell 5.1.26100 → **0 lỗi cú pháp/6 file** (kiểm độc lập, không thực thi).
- Linux PASS **không** được tính là Windows native PASS.

---

## 6. Finding mới

### RC4-N01 — P2 — BLOCKING — Resume phía reader bị hỏng do chọn nhánh theo `is_remote` (hồi quy RC4, liên quan B02/F16)

**Vị trí:** `libs/base/src/fs.rs`, `TransferJob::set_stream_offset` (~dòng 1814, 1879, 1890).

**Cơ chế.** RC3 chọn vai trò theo trạng thái file: có cả `.download`+`.digest` → mở writer; ngược lại nếu file nguồn tồn tại → mở reader rồi seek. RC4 đổi sang chọn theo `self.is_remote`: `!is_remote` ⇒ writer, `is_remote` ⇒ reader. Nhưng `is_remote` **không** phân biệt reader/writer:
- Client upload: `io_loop.rs` nhánh `SendFiles` với `is_remote=false` → `new_read(..., false, …)`.
- Host/Connection phục vụ download: `server/connection.rs` gọi `new_read(…, false, …)` cố định.
- CM nhận upload: `new_write(…, false, …)` (writer, đúng như RC4 giả định).

Khi host trả `OffsetBlk(offset>0)` để resume, reader `is_remote=false` rơi vào nhánh cuối: nếu không có `.download/.digest` cục bộ thì `resume_failed_err` được đặt (reader không bao giờ đọc cờ này — chỉ `write()` đọc) rồi `return` **mà không mở/seek stream**. Reader sau đó đọc từ byte 0 và gửi toàn bộ file trong khi receiver đang chờ phần từ `offset` → ghép sai → kiểm SHA-256/size cuối bị từ chối (fail-closed), nhưng **resume upload (client→host) và resume phục vụ download phía Connection không còn dùng được**. Nếu phía gửi tình cờ có `<file>.download`/`.digest` cục bộ thì reader bị mở nhầm theo nhánh writer (ghi vào file khác).

**Vì sao là blocker.** Đây là đường legacy bị sửa không cần thiết (vi phạm quy tắc regression-surface của AGENTS.md) và làm hỏng chức năng RC3 đang hoạt động; Windows CI một-host không bắt được, và F16 pilot (resume, cả hai chiều) sẽ lộ lỗi sau khi đã tốn một vòng build. Test B02 của Developer chỉ dùng `new_write(is_remote=false)` nên không phủ reader.

**Mức độ chắc chắn:** xác nhận bằng đọc nguồn (call-site + diff); chưa chạy được vì không có toolchain. Developer nên chứng minh bằng test.

**Acceptance cho bản sửa (RC5):**
1. Phân nhánh theo **vai trò job** (writer/reader), không theo `is_remote` — hoặc khôi phục vị từ RC3 (`.download`&`.digest` tồn tại ⇒ writer; ngược lại file nguồn tồn tại ⇒ reader) và chỉ áp dụng open hardened + `resume_failed_err` bên trong nhánh writer.
2. Thêm 1 test hồi quy: `new_read(..., is_remote=false)` + `confirm(OffsetBlk>0)` ⇒ stream được seek đúng offset, `read()` trả dữ liệu từ offset; và giữ nguyên test B02 hiện có (victim 43 byte).
3. Không đụng phần còn lại của delta.

### Quan sát không chặn (non-blocking)

| ID | Mức | Nội dung |
|---|---|---|
| **N02** | P3 evidence | Test `server::connection::test::ft010_b03_real_engine_connection_capability_and_port_forward_cutoff_on_revoke` **không có log bằng chứng được commit** (handoff ghi "Verified in RC4 test pipeline"); log dauverse chỉ chứa 1/2 test B03 (filter `dauverse::` không bao gồm module `server::connection`). Cần đính kèm log `cargo test … ft010_b03` ở lần bàn giao tới. Mã test tồn tại và hợp lý. |
| **N03** | P3 | Handoff nói FFI `transfer_track_receive/finalize_receive` "yêu cầu positive `conn_id` + `session_scope`", nhưng thực tế khi thiếu tham số mặc định `conn_id=1`, `session_scope="ffi-conn-1"`. Đường engine thật dùng identity thật nên không bị ảnh hưởng; FFI chỉ dùng cho E2E. Nên từ chối khi thiếu `conn_id`, hoặc sửa lại câu chữ handoff. |
| **N04** | P3 | `commit_security_config2_options_at` khi `!conservative_deny_on_error` chỉ rollback bộ nhớ, đĩa đã ghi giá trị mới → lệch bộ nhớ/đĩa trong nhánh lỗi hiếm; không ảnh hưởng đường revoke (luôn `conservative=true`). |
| **N05** | P3 style | `handle_input` bị thụt lề lại toàn khối (~60 dòng) chỉ để thêm một guard; hành vi giữ nguyên (đã so với RC3) nhưng trái quy tắc diff tối thiểu của AGENTS.md. `verify_staging_file_sha256` còn lại thành wrapper không ai gọi ngoài test (cảnh báo dead-code, không phải lỗi trừ khi CI dùng `-D warnings` — chưa xác nhận). |
| **N06** | P3 cosmetic | Tên workflow/artifact vẫn ghi "RC2"; `Finished` trong validator Q01 gắn với định dạng cargo hiện tại. |
| **N07** | info | Manifest `Initial` ở bước build dùng `$_.Name` (không đệ quy) ở build, còn bộ sinh `Final` đệ quy — nhất quán chỉ khi ReleaseDir phẳng, đúng với layout hiện tại. |

---

## 7. Phân loại theo yêu cầu Boss

| Loại | Mục |
|---|---|
| **Source blocker** | RC4-N01 (duy nhất) |
| **Build blocker** | Không xác định được bằng phân tích tĩnh (xem §8) |
| **Non-blocking finding** | N02–N07, Q01 (raw-log gate) |
| **Native verification pending** | Xem §9 |

## 8. Windows build readiness

- Cú pháp 6 script PS 5.1 sạch; workflow truyền đúng đường dẫn NSIS; manifest B01 nhất quán giữa build và verify; phần phụ thuộc `winapi` (`fileapi`) và `std::os::windows::prelude` đã có cho `GetFileInformationByHandle`, `custom_flags`, `file_attributes`.
- **Chưa kiểm chứng:** biên dịch các nhánh `#[cfg(windows)]` mới (`query_std_handle_link_count`, `ensure_raw_pipe_server`, `windows_service` stop, `write_atomic_bytes` cho Config2 trên Windows — nhánh Windows của B04 **không** có test fault-injection, test B04 chỉ chạy trên Unix). Đây là rủi ro build/native, chỉ lộ khi có CI.
- Kết luận: không có Build blocker đã chứng minh; Windows build **chưa đủ điều kiện** chỉ vì Source blocker RC4-N01.

## 9. Remaining native verification (sau khi có bản Windows build)

1. Biên dịch Windows (Rust/Flutter AOT/NSIS 3.11) + đối chiếu **log gốc GitHub Actions** (Q01).
2. NTFS: hardlink/junction/ADS staging; oplock/path-swap giữa verify và rename vẫn không được chứng minh (thừa nhận trong handoff).
3. Revoke trực tiếp với phiên portable/SCM đang có keyboard/clipboard/file/port-forward; cùng tồn tại dịch vụ RustDesk ngoài.
4. `RustDesk2.toml` trên NTFS: ACL, đầy đĩa, reboot; DPAPI/vault (F05/F07/F09).
5. Transfer 2 PC RC4↔RC4 hai chiều, resume (sẽ phủ RC4-N01 sau khi sửa), cancel, tamper, trùng job id, nâng cấp đồng bộ.
6. F11 A→B→A thật; F04/F10/F12/F13 phần cứng/PKI/WoL.

## 10. Đề xuất bước tiếp theo (không phải phê duyệt CI)

Verdict hiện tại **không** đề xuất chạy Windows CI. Quy trình đề nghị:
1. Antigravity sửa RC4-N01 theo acceptance §6 (+ đính kèm log N02, sửa N03 nếu tiện) thành **một commit nhỏ** trên RC4.
2. Reviewer chỉ kiểm delta đó (đọc diff + test hồi quy reader-resume), các phần B01–B05/Q/F01 đã đóng ở trên được tái sử dụng, không kiểm lại.
3. Nếu PASS: đề xuất **đúng một lượt** Windows CI (`workflow_dispatch`, `run_tests` theo quyết định của Boss) trên commit RC5 đã ghim — Boss phê duyệt.

## 11. Governance compliance

Không sửa mã ứng viên; không commit/push; không kích hoạt GitHub Actions; không chạy/cài EXE, service, driver; không đổi BIOS/firewall/router; không tác động DAUVERSE AI hay workspace khác; không phát sinh chi phí API. Ghi duy nhất trong `E:\DAUVERSE_REMOTE_DESKTOP\QA\RC4_CLAUDE_QA_012\` (clone `src\` + báo cáo này). Evidence lịch sử `RC3_SOURCE_REVIEW_008` chỉ đọc. Production LOCKED.

## 12. SHA-256 báo cáo

Do báo cáo không thể chứa hash của chính nó, SHA-256 được ghi trong file đi kèm `DAUVERSE_REMOTE_V1_RC4_CLAUDE_QA_REPORT.md.sha256` cùng thư mục và nêu trong thông báo bàn giao.
