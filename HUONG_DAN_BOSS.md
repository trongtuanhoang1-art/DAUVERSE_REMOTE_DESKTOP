# HƯỚNG DẪN SỬ DỤNG & VẬN HÀNH DÀNH CHO BOSS
## DAUVERSE REMOTE DESKTOP V1.0 (`DAUVERSE REMOTE`) — BẢN CẬP NHẬT RC1 REMEDIATED

> **Trạng thái Phê duyệt Hệ thống (`Section 7` — `DREMOTE-V1-RC1-NEXT-002`):**
> - Bản phát hành hiện tại là **Bản thử nghiệm kỹ thuật `UNSIGNED` (Chưa ký chứng chỉ Code Signing thương mại)**, phục vụ **Codex QA độc lập** và kiểm tra an toàn.
> - **Chưa cài đặt** Windows Service, Virtual Display Driver, Unattended Access hoặc khởi động lại trên máy tính thật của Boss khi chưa có phê duyệt tiếp theo của Boss.
> - **Auto-update tự động** đối với gói `UNSIGNED` đã bị khóa cứng (`HARD-BLOCKED`) để đảm bảo an toàn tuyệt đối.

---

## 1. Tổng quan nhanh cho Boss

**DAUVERSE REMOTE DESKTOP V1.0** kế thừa trực tiếp nhân truyền hình/điều khiển RustDesk `v1.5.3` và tích hợp lớp điều hành chuyên biệt cho dàn máy AI tại nhà (**Intel Core i5-12400F • ASUS PRIME H610M-K D4 • NVIDIA RTX 3060 12GB • 16GB RAM • Windows 11 Pro**):
- **Kết nối phiên Remote & Truyền File thật:** Bấm **Kết nối nhanh** hoặc **Truyền File 2 ngăn** tại Dashboard / My Devices / File Transfer sẽ gọi trực tiếp nhân kết nối P2P/Relay mã hóa đầu-cuối của RustDesk (`connect()`), được kiểm soát bởi chính sách **Clipboard Guard** và **Transfer Guard** ngay trong đường ống dữ liệu.
- **Cửa sổ nổi Mini Control thật (`window_manager`):** Ghim nổi (`Always-On-Top`), thu phóng kích thước, Snap 4 góc màn hình, chỉnh độ trong suốt (`Opacity`), hạ xung nhịp khi rảnh và chế độ **Compact Status Mode** không chiếm bàn phím khi Boss làm việc công ty.
- **Thông báo AI xác thực HMAC-SHA256 (`127.0.0.1:21188`):** Tự động lắng nghe sự kiện thật từ Claude Code, Codex CLI, script build và ComfyUI mà **không can thiệp `DAUVERSE AI` production** và **không bao giờ tự ý bấm Approve thay Boss**.
- **An toàn Driver Headless (`Section 7`):** Qua kiểm định mật mã học X.509/PKCS#7, gói `RustDeskIddDriver v0.4` dùng chứng chỉ tự ký `WDKTestCert` (SHA-1) đã bị **CHẶN CỨNG (`BLOCKED_DO_NOT_INSTALL`)**. Khi Boss phê duyệt Headless sau này, chỉ sử dụng **`usbmmidd_v2` có chữ ký Microsoft WHQL chính hãng** (giữ nguyên Secure Boot & Driver Signature Enforcement) hoặc **HDMI 2.0 Dummy Plug** (không cần cài driver).
- **Ổ cắm thông minh `Hunonic SK02` (`Section 6`):** Hunonic không công bố API công khai chính thức (HTTP/MQTT/OpenAPI). Tuân thủ nguyên tắc an toàn, phần mềm giữ **`DisabledSmartPlugAdapter` (`BLOCKED`)**, không dùng API dịch ngược và không thu thập tài khoản Hunonic của Boss.

---

## 2. Cách tạo Bộ cài Windows (`.exe` `UNSIGNED`) không tốn chi phí (`0 VNĐ`)

### Cách 1 — Chạy GitHub Actions miễn phí trên kho công khai `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP`
1. Sau khi đồng bộ nhánh `develop/dauverse-remote-v1` lên kho `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP`, mở tab **Actions**.
2. Chọn workflow **`DAUVERSE Windows Release Build (Manual Dispatch Only)`** -> nhấn **Run workflow** trên nhánh `develop/dauverse-remote-v1`.
3. Tải artifact `DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_UNSIGNED` gồm:
   - `DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe` (Bộ cài đặt NSIS đầy đủ + Uninstaller + Rollback, không tự cài driver)
   - `DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe` (Bản chạy độc lập cho máy công ty)
   - `SHA256_MANIFEST.txt` (Mã băm kiểm tra toàn vẹn)

### Cách 2 — Build native trực tiếp trên máy Windows vào ổ `E:\` (1 lệnh PowerShell)
Mở PowerShell tại thư mục mã nguồn `E:\DAUVERSE_REMOTE_DESKTOP\SOURCE`:
```powershell
.\scripts\windows\build_windows_release.ps1 -WorkspaceRoot "E:\DAUVERSE_REMOTE_DESKTOP"
```
- Mọi thư mục trung gian (`BUILD`, `CACHE`, `TEMP`, `STAGING`, `RELEASE`) đều ghi vào `E:\DAUVERSE_REMOTE_DESKTOP\`, không làm đầy ổ `C:\`.
- Bộ cài NSIS kiểm tra ổ đĩa cố định (`DRIVE_FIXED`), từ chối đường dẫn mạng UNC/ổ đĩa rời và đồng bộ chính xác thư mục sao lưu với `rollback_windows_release.ps1`.

---

## 3. Quy trình vận hành an toàn với `Hunonic SK02` & ASUS PRIME H610M-K D4

1. **Bật máy từ xa:**
   - Sau khi Boss tự kiểm tra và bật `Restore AC Power Loss = Power On` + `Power On By PCI-E = Enabled` + `ErP Ready = Disabled` trong BIOS `ASUS PRIME H610M-K D4` (chi tiết tại [`DOCS/SMART_POWER_AND_BIOS_GUIDE.md`](DOCS/SMART_POWER_AND_BIOS_GUIDE.md)), Boss có thể bật nguồn qua **Wake-on-LAN** hoặc bật ổ cắm **`Hunonic SK02`** ngay trên ứng dụng điện thoại Hunonic chính thức (không bị văng phiên đăng nhập).
2. **Làm việc hàng ngày & Theo dõi AI:**
   - Nhập Peer ID tại **Dashboard** -> nhấn **Kết nối nhanh** (mở phiên điều khiển thật) hoặc **Truyền File** (mở trình quản lý file 2 ngăn thật).
   - Chọn chế độ **`AI Workload Priority`** khi máy nhà đang render video ComfyUI trên RTX 3060 12GB.
   - Chuyển sang **Mini Control** để cửa sổ thu nhỏ ghim góc màn hình khi làm việc tại công ty.
3. **Tắt máy an toàn cuối ngày:**
   - Sử dụng **Safe Windows Shutdown** trong mục **Smart Power** (có khóa xác thực Step-Up và tự động chặn nếu phát hiện AI đang chạy, ComfyUI đang render hoặc File đang truyền dở). Chỉ tắt nguồn ổ cắm `Hunonic SK02` sau khi xác nhận Windows đã tắt hoàn toàn.
