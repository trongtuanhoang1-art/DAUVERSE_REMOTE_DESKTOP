# HƯỚNG DẪN SỬ DỤNG & VẬN HÀNH DÀNH CHO BOSS
## DAUVERSE REMOTE DESKTOP V1.0 (`DAUVERSE REMOTE`) — BẢN WINDOWS RC2 (SAU REMEDIATION 16 FINDINGS)

> **Trạng thái Quản trị & Phê duyệt (`DREMOTE-V1-REMEDIATION-005`):**
> - **Production:** **`LOCKED`** (Chưa phê duyệt Production; gói RC2 này dùng để bàn giao **Codex Re-QA độc lập**).
> - **Chữ ký số (`SIGNING_STATUS.txt`):** **`UNSIGNED`** (0 VNĐ — chưa mua chứng chỉ Authenticode thương mại; tính năng Auto-Update tự động bị **KHÓA CỨNG** kể cả khi metadata giả mạo `VERIFIED_TRUSTED_PUBLISHER`).
> - **An toàn Máy thật:** **KHÔNG tự cài đặt** Windows Service, Virtual Display Driver hay tắt Secure Boot / Driver Signature Enforcement. Các bản RustDesk sẵn có trên máy được bảo vệ nguyên vẹn (`F03`).

---

## 1. Tóm tắt các nâng cấp an toàn trọng yếu trong bản Windows RC2

1. **Xác thực toàn vẹn sự kiện AI (`F01`, `F09`):** Nâng cấp lên giao thức ký `DAUVERSE_AI_EVENT_V2` khóa HMAC-SHA256 trên **toàn bộ 22 trường dữ liệu & provenance** đồng bộ giữa Rust, Python (`claude_code_hook.py`, `codex_notify_hook.py`) và PowerShell (`dauverse_job_wrapper.ps1`), kèm sổ nhật ký chống phát lại (`bridge_replay_journal.json`) bền vững qua khởi động lại.
2. **Bảo vệ RustDesk sẵn có & Gỡ cài đặt an toàn (`F03`, `F08`, `F11`):** Bộ cài `SETUP.exe`, `Uninstall.exe` và `rollback_windows_release.ps1` kiểm tra đường dẫn `ImagePath` của Windows Service `RustDesk` và đường dẫn tiến trình trước mọi thao tác — giữ nguyên 100% nếu máy đã có bản RustDesk khác. Sao lưu nâng cấp có `BACKUP_SHA256_MANIFEST.txt` kiểm tra trước và tự khôi phục nếu lỗi.
3. **Step-Up PIN & Kho lưu trữ bền vững (`F05`, `F07`):** Lưu cấu hình bền vững tại `%LOCALAPPDATA%\DAUVERSE\RemoteDesktopV1`; chặn ghi đè PIN trái phép (bắt buộc nhập PIN hiện tại khi đổi PIN), khóa tạm thời sau 5 lần nhập sai và khóa an toàn (`FAIL-CLOSED`) nếu file vault bị hỏng.
4. **FFI Fail-Closed & Truyền file kiểm tra SHA-256 (`F06`, `F14`, `F16`):** Giao diện Flutter hiện cảnh báo đỏ và khóa thao tác nhạy cảm nếu thiếu thư viện native `librustdesk.dll`; luồng nhận file đóng/flush file an toàn không đi theo symlink và đối chiếu kích thước + mã băm SHA-256 trước khi báo hoàn tất.
5. **Headless WHQL & Lưu ý bản quyền `usbmmidd_v2` (`F04`, `A02`):**
   - Gói `RustDeskIddDriver v0.4` (`WDKTestCert` SHA-1) tiếp tục bị **CHẶN CỨNG**.
   - Gói driver `usbmmidd_v2` của **Amyuni Technologies Inc.** (ký Microsoft WHQL hợp lệ, giữ nguyên `usbmmidd_v2\License.txt`) chỉ được đóng gói sẵn ở chế độ **Opt-in thủ công** và chỉ báo `ACTIVE` khi Windows thực sự kích hoạt màn hình ảo thành công.
   - **Lưu ý minh bạch cho Boss:** Theo giấy phép bản miễn phí của Amyuni (`usbmmidd_v2\License.txt`), khi kích hoạt driver miễn phí có thể hiển thị trang thông báo của nhà phát triển Amyuni. Nếu Boss muốn dùng Headless 4K/60Hz hoàn toàn không cài driver và không có hộp thoại thông báo, giải pháp khuyên dùng số 1 vẫn là **cắm đầu giả lập màn hình phần cứng HDMI 2.0 Dummy Plug** vào cổng HDMI của card RTX 3060.
6. **Ổ cắm `Hunonic SK02`:** Giữ nguyên `DisabledSmartPlugAdapter` (`BLOCKED`) do nhà sản xuất không công bố API công khai chính thức; Boss bật/tắt nguồn trực tiếp trên app Hunonic điện thoại sau khi đã tắt Windows an toàn.

---

## 2. Cách tải và kiểm tra Gói Bàn Giao Đầy Đủ (`COMPLETE_QA.zip` — `0 VNĐ`)

1. Tải trực tiếp file **`DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip`** từ **GitHub Actions Artifact** của Run RC2 trên nhánh `develop/dauverse-remote-v1` (hoặc từ thẻ Artifact đính kèm ngay trong phiên làm việc này).
2. Kiểm tra mã băm SHA-256 của file ZIP khớp với `FINAL_HANDOFF_SHA256_MANIFEST.txt`.
3. Bên trong gói `DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip` đã tích hợp đầy đủ 100%:
   - `RELEASE/DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe` & `RELEASE/DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe`
   - `SOURCE/` (toàn bộ mã nguồn + submodule `libs/hbb_common`) & `BUNDLE/DAUVERSE_REMOTE_DESKTOP_V1_RC2.bundle` (tự chứa 100% lịch sử Git, `git bundle verify` = `0`)
   - `QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md` (bản gốc báo cáo Codex `f07b61ed...`), `QA/FINDINGS_REMEDIATION_MATRIX.md`, `QA/CODEX_REQA_WINDOWS_RC2_HANDOFF.md`
   - `LOGS/`, `EVIDENCE/`, `LICENSES/` và `SHA256_MANIFEST.txt` kiểm tra đối xứng hai chiều (`0` thiếu, `0` thừa).

---

## 3. Quy trình chuyển tiếp sang Controlled Pilot (Chỉ sau khi Codex Re-QA thông qua)

- **Chưa cài lên máy làm việc chính của Boss** cho tới khi Codex hoàn tất vòng **Independent Re-QA** trên gói RC2 này.
- Các hạng mục cần 2 máy Windows thật (điều khiển phiên trực tiếp P2P/Relay, âm thanh WASAPI, truyền file 2 chiều, test màn hình ảo trên card vật lý không cắm màn hình) được ghi nhận trung thực là **`BLOCKED`** trong CI 1 máy và đã có quy trình kiểm thử 2 máy cách ly tại `QA/CODEX_REQA_WINDOWS_RC2_HANDOFF.md`.
