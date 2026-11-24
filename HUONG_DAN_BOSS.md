# HƯỚNG DẪN SỬ DỤNG & VẬN HÀNH DÀNH CHO BOSS
## DAUVERSE REMOTE DESKTOP V1.0 (`DAUVERSE REMOTE`)

---

## 1. Tổng quan nhanh cho Boss

**DAUVERSE REMOTE DESKTOP V1.0** được thiết kế chuyên biệt để Boss ngồi tại công ty và điều khiển toàn diện dàn máy AI tại nhà (**Intel Core i5-12400F • ASUS PRIME H610M-K D4 • NVIDIA RTX 3060 12GB • 16GB RAM • Windows 11 Pro**) mà:
- **Không cần bật màn hình vật lý ở nhà** (Headless Mode với `RustDeskIddDriver` v0.4).
- **Không cần người ở nhà bấm xác nhận** sau khi Boss đã ghép nối thiết bị vào **Trusted Devices Allowlist**.
- **Không làm gián đoạn công việc tại công ty** nhờ cửa sổ nổi **Mini Control** (tự hạ FPS khi rảnh, không cướp bàn phím) và **Thông báo nổi góc màn hình (Corner Toast 5–8 giây)** báo ngay khi Claude, Codex, Antigravity hoặc ComfyUI hoàn thành tác vụ.
- **Hoàn toàn tách biệt với `DAUVERSE AI` production** (chỉ đọc trạng thái qua Event Bridge đã ký xác thực HMAC-SHA256, tuyệt đối không can thiệp Controller hay tranh chấp workspace).

---

## 2. Cách tạo Bộ cài Windows (`.exe`) bằng 1 lệnh duy nhất

Do Antigravity Remote Agent vận hành trên máy ảo Linux đám mây để đảm bảo cô lập tuyệt đối với máy tính của Boss, mã nguồn tích hợp đã được kiểm thử đầy đủ trên Linux và chuẩn bị sẵn **2 cách tạo file `.exe` Windows chính thức** để Boss chọn cách thuận tiện nhất:

### Cách 1 — Chạy GitHub Actions trên kho `DAUVERSE_REMOTE_DESKTOP` (Không cần cài công cụ build trên máy Boss)
1. Mở kho GitHub `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP` -> tab **Actions**.
2. Chọn workflow **`DAUVERSE Windows Release Build (Manual Dispatch Only)`** trên nhánh `develop/dauverse-remote-v1`.
3. Nhấn **Run workflow** -> sau khi hoàn tất, tải gói artifact `DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_UNSIGNED` gồm:
   - `DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe` (Bộ cài đặt đầy đủ + Uninstaller + Rollback)
   - `DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe` (Bản chạy ngay không cần cài đặt cho máy công ty)
   - `SHA256_MANIFEST.txt` (Mã băm kiểm tra toàn vẹn)

### Cách 2 — Build trực tiếp trên máy Windows của Boss vào ổ `E:\` (1 lệnh PowerShell)
Mở PowerShell tại thư mục mã nguồn `E:\DAUVERSE_REMOTE_DESKTOP\SOURCE`:
```powershell
.\scripts\windows\build_windows_release.ps1 -WorkspaceRoot "E:\DAUVERSE_REMOTE_DESKTOP"
```
Toàn bộ thư mục trung gian (`BUILD`, `CACHE`, `TEMP`, `STAGING`, `RELEASE`) được tự động lưu sang ổ **`E:\DAUVERSE_REMOTE_DESKTOP\`**, không làm đầy ổ `C:\`.

---

## 3. Thiết lập lần đầu tại máy ở nhà (Home AI Rig)

1. **Cấu hình BIOS ASUS PRIME H610M-K D4 (Bật máy từ xa qua ổ cắm thông minh / Wake-on-LAN):**
   - Khởi động máy bấm `Del` -> `F7 (Advanced Mode)` -> `Advanced > APM Configuration`:
     - `Restore AC Power Loss` -> **`Power On`** *(Lưu ý: Boss kiểm tra đúng tên mục trên phiên bản BIOS thực tế trước khi nhấn F10 lưu)*.
     - `Power On By PCI-E` -> **`Enabled`**, `ErP Ready` -> **`Disabled`**.
   - Xem chi tiết tại [`DOCS/SMART_POWER_AND_BIOS_GUIDE.md`](DOCS/SMART_POWER_AND_BIOS_GUIDE.md).
2. **Cài đặt Host & Ghép nối Thiết bị Tin cậy (Device Shield):**
   - Chạy `DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe` trên máy nhà (ưu tiên đường dẫn `E:\Program Files\DAUVERSE Remote Desktop`).
   - Mở mục **Khiên bảo mật (Security Center)** -> ghép nối mã định danh máy công ty vào **Device Allowlist** và phân quyền chi tiết (Remote Control, Clipboard, File Transfer, Audio, Smart Power, AI Notification).
   - Bật **Unattended Access** có xác thực. Nếu cần ngắt quyền ngay lập tức bất kỳ lúc nào, nhấn nút đỏ **Thu hồi khẩn cấp mọi truy cập (Emergency Revoke All Access)**.
3. **Kết nối Hook thông báo AI thật (Claude Code / Codex / Build / ComfyUI):**
   - Xem hướng dẫn cấu hình 3 bước tại [`DOCS/AI_INTEGRATION_AND_NOTIFICATION_GUIDE.md`](DOCS/AI_INTEGRATION_AND_NOTIFICATION_GUIDE.md).

---

## 4. Sử dụng hàng ngày tại Công ty

1. **Mở phiên nhanh hoặc chạy bản Portable:** Mở `DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe` -> tại **Dashboard**, nhấn **Kết nối một chạm** vào `BOSS-HOME-AI-RIG`.
2. **Chế độ hiệu năng khi máy nhà đang chạy nặng ComfyUI / AI:**
   - Trên **Floating Toolbar** (thanh nổi phía trên phiên Remote), chọn **`Auto Adaptive`** hoặc **`AI Workload Priority`** để ưu tiên tối đa nhân CUDA & 12GB VRAM của RTX 3060 cho ComfyUI.
3. **Thu nhỏ sang Mini Control để làm việc công ty:**
   - Nhấn nút **Mini Control** trên thanh nổi (hoặc menu trái).
   - Kéo thả, ghim góc màn hình (**Snap góc**), chỉnh độ trong suốt, hoặc bật **Chỉ hiện trạng thái (Tắt truyền hình)** để chỉ theo dõi Ping, CPU/GPU/VRAM/Nhiệt độ và số tác vụ AI mà không tốn băng thông.
   - **Nháy đúp (Double-click)** vào Mini Control để phóng to lại phiên điều khiển đầy đủ ngay lập tức.
4. **Nhận thông báo AI góc màn hình:**
   - Khi Antigravity, Claude, Codex hoặc ComfyUI hoàn tất lệnh/nhiệm vụ hoặc cần Boss duyệt, hộp thoại nhỏ xuất hiện ở góc phải dưới màn hình trong 5–8 giây mà **không làm mất con trỏ bàn phím** đang gõ dở của Boss.
   - Vì lý do an toàn, thông báo không bao giờ tự ý bấm Approve thay Boss — Boss nhấn **Mở Remote** trên Toast để kiểm tra và phê duyệt trực tiếp.
5. **Tắt máy an toàn cuối ngày:**
   - Vào mục **Điều khiển nguồn thông minh (Smart Power)** -> nhấn **Safe Windows Shutdown**.
   - Hệ thống sẽ tự động kiểm tra: nếu **AI đang chạy**, **ComfyUI đang render** hoặc **File đang truyền dở**, phần mềm sẽ chặn lệnh tắt và hiện cảnh báo rõ ràng để bảo vệ dữ liệu của Boss!
