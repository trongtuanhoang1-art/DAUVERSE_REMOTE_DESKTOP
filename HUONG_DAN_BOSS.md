# HƯỚNG DẪN SỬ DỤNG & VẬN HÀNH THỰC TẾ DÀNH CHO BOSS
## DAUVERSE REMOTE DESKTOP V1.0 (`RC4.3` • Phiên bản `1.0.0-rc4.3` • Engine `1.5.3`)

> **Trạng thái Quản trị (`DREMOTE-V1-FINAL-INTEGRATION-016`):**
> - **Production:** **`LOCKED`** (Hoàn toàn độc lập 100%, không chạm tới `DAUVERSE AI` Production).
> - **Chữ ký số (`SIGNING_STATUS.txt`):** **`UNSIGNED`** (`0 VNĐ` — tính năng tự động cập nhật ngầm bị **KHÓA CỨNG**; chỉ cập nhật thủ công khi kiểm tra khớp mã băm `SHA-256`).
> - **An toàn Hệ thống:** Giữ nguyên mật khẩu đăng nhập Windows của Boss, **KHÔNG** bật tự động đăng nhập Windows (`AutoAdminLogon`), **KHÔNG** tự mở cổng mạng hay tự bật `Direct IP Access`, và bảo toàn nguyên vẹn bản RustDesk sẵn có nếu máy đang cài ngoài thư mục DAUVERSE (`F03`).

---

## 1. Những khắc phục cốt lõi trong bản `RC4.3`

1. **Khắc phục triệt để lỗi màn hình đen & văng ứng dụng (`0xc0000005` trong `flutter_windows.dll`):**
   - Nguyên nhân gốc từ nhật ký Windows Event Viewer của Boss (`Fault offsets: 0xc2c668, 0xc2d108` trên `flutter_windows.dll`) là lỗi tranh chấp ngữ cảnh đồ họa đa cửa sổ `ANGLE D3D11` của bản Flutter `3.50.0` nguyên bản khi mở cửa sổ phiên điều khiển từ xa.
   - Bản `RC4.3` đã khóa cứng sang **Flutter `3.24.5` + `rustdesk/engine` (`windows-x64-release`)** chuẩn đa cửa sổ, đồng thời đặt mặc định chế độ kết xuất **`PixelBuffer Safe`** để hoạt động ổn định trên cả máy có card rời NVIDIA lẫn máy văn phòng chỉ dùng card tích hợp Intel/AMD hoặc CPU.
   - Bản `PORTABLE.exe` nay giải nén độc lập vào `%LOCALAPPDATA%\dauverse_remote\` (không còn đè vào `%LOCALAPPDATA%\rustdesk\`).
   - Đã sửa lỗi khởi động dịch vụ nhận kết nối khi mở `--dauverse-ui` và sửa lỗi crash `TabbarTheme` khi bấm nút **`Engine Gốc`**.

2. **Khu vực Kết nối Trung tâm mới trên Dashboard (Chuẩn chữ lớn, 1-Click):**
   - **ID Kết nối của máy này (`36px`):** Hiển thị rõ nét, có nút **`Sao chép`** riêng (1 lần nhấn -> hiện thông báo **`"Đã sao chép"`**).
   - **Địa chỉ IP LAN thực tế (`26px`):** Tự động lấy từ card mạng đang hoạt động thực tế của máy, mỗi IP có nút **`Sao chép`** riêng. Tách biệt rõ với **IP Public** (chỉ truy vấn khi Boss bấm nút kiểm tra).
   - **Mật khẩu tạm thời:** Có đủ 3 nút **`Hiện/Ẩn`**, **`Sao chép`** và **`Tạo mới`** (xoay mật khẩu tức thì).
   - **Kết nối tới máy tính khác:** Ô nhập ID/IP kích thước lớn, có nút **`Dán`** từ Clipboard, nút **`KẾT NỐI NGAY`** nổi bật và nút **`Truyền File`** hai chiều.
   - **Trạng thái kết nối trực quan:** Hiển thị rõ 4 trạng thái thực tế **`Online`**, **`Offline`**, **`Connecting`**, **`Connected`**.

---

## 2. Hướng dẫn kết nối điều khiển từ xa giữa 2 máy Windows của Boss

1. Cài đặt **`DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe`** (hoặc chạy **`DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe`**) trên cả **Máy Nhà (Host)** và **Máy Văn Phòng / Laptop (Client)** cùng phiên bản **`V1.0 RC4.3`**.
2. Kiểm tra góc trên Dashboard của cả 2 máy hiện trạng thái xanh **`Online`**.
3. Trên **Máy Nhà**:
   - Nhấn nút **`Sao chép`** cạnh **ID Kết nối** và gửi ID (kèm **Mật khẩu tạm thời** hoặc mật khẩu cố định) sang Máy Văn Phòng.
4. Trên **Máy Văn Phòng**:
   - Nhấn nút **`Dán`** tại ô nhập thiết bị đích, sau đó nhấn **`KẾT NỐI NGAY`** và nhập mật khẩu để vào phiên điều khiển.
5. **Nếu một trong hai máy dùng card đồ họa tích hợp cũ hoặc máy ảo không có GPU:**
   - Vào mục **`Cài đặt hệ thống`** -> phần **Chế độ Kết xuất Video Phiên Từ xa**:
     - Mặc định đã ở **`PixelBuffer Safe (Mặc định an toàn)`**.
     - Nếu máy hoàn toàn không có tăng tốc phần cứng video, chọn **`Software Canvas Fallback`**.
     - Nếu cả 2 máy đều có GPU rời ổn định và muốn độ trễ thấp nhất, có thể chọn **`GPU D3D11 Zero-Copy`**.

---

## 3. Hướng dẫn bật Truy cập từ Màn hình khóa & Trước khi đăng nhập Windows (`Winlogon`)

Để điều khiển được Máy Nhà ngay sau khi bật nguồn (khi đang ở màn hình nhập mật khẩu Windows, màn hình khóa hoặc hộp thoại UAC) mà **vẫn giữ nguyên mật khẩu Windows**:

1. Mở **`DAUVERSE Remote Desktop`** trên Máy Nhà -> vào **`Cài đặt hệ thống`**.
2. Tạo **Mã Step-Up PIN chủ máy** (tối thiểu 6 ký tự) nếu chưa tạo, sau đó nhập PIN vào ô xác thực.
3. Nhấn nút **`Cài đặt & Bật Windows Service (UAC)`** và bấm **Yes** trên hộp thoại xác nhận quyền Quản trị viên (UAC) của Windows:
   - Nếu máy đang có sẵn dịch vụ `RustDesk` cài từ phần mềm ngoài thư mục DAUVERSE, hệ thống sẽ tự động báo **`EXTERNAL COLLISION (F03)`** và giữ nguyên dịch vụ cũ để an toàn tuyệt đối.
4. Bật công tắc **`Cho phép Truy cập Không giám sát (Unattended Access)`** (và đặt mật khẩu cố định trong trình cấu hình bảo mật).
5. Kiểm tra 2 huy hiệu trạng thái chuyển sang màu xanh:
   - **`Trước Đăng nhập (Winlogon): SẴN SÀNG`**
   - **`Màn hình khóa & UAC: SẴN SÀNG`**
6. **Khi cần ngắt khẩn cấp mọi quyền truy cập từ xa:**
   - Nhấn nút đỏ **`Thu hồi Khẩn cấp 1-Click`** (tại **Khiên bảo mật** hoặc **Cài đặt hệ thống**): hệ thống sẽ lập tức ngắt toàn bộ phiên đang kết nối, dừng dịch vụ thuộc quyền sở hữu DAUVERSE, tắt Unattended Access, xoay mật khẩu tạm và khóa toàn bộ đầu vào.

---

## 4. Lưu ý Màn hình ảo Headless & Ổ cắm thông minh

- **Máy không cắm màn hình vật lý (Headless):** Khuyên dùng số 1 là cắm **HDMI 2.0 Dummy Plug** vào card RTX 3060 (0 cài đặt driver). Nếu cần dùng phần mềm, gói **`usbmmidd_v2`** (ký Microsoft WHQL hợp lệ của Amyuni) đã được đóng gói sẵn ở chế độ thủ công Opt-in tại `Cài đặt hệ thống` (bản miễn phí của Amyuni có thể hiện trang giới thiệu nhà sản xuất theo `usbmmidd_v2\License.txt`). Gói tự ký `RustDeskIddDriver v0.4` tiếp tục bị chặn cứng.
- **Ổ cắm `Hunonic SK02`:** Giữ trạng thái **`BLOCKED`** trung thực do nhà sản xuất không công bố API nội bộ/công khai; Boss dùng tính năng **Wake-on-LAN** kết hợp cấu hình BIOS `Restore AC Power Loss = [Power On]`.
