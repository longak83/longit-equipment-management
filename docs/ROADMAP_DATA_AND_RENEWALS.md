# Longit — Lộ trình dữ liệu và nghiệp vụ

## Nguyên tắc triển khai

- Giữ nguyên `public.assets` và dữ liệu hiện có; không chạy lại schema nền trên database đang sử dụng.
- Mọi thay đổi cấu trúc mới được thêm bằng migration riêng trong `supabase/migrations/`.
- Kiểm thử trên nhánh phát triển trước; không nhập dữ liệu Excel hàng loạt khi chưa đối chiếu mã tài sản.
- Các chức năng ghi dữ liệu tiếp tục dùng Supabase Auth + RLS; không đưa service-role/secret key vào frontend.
- Ngày cảnh báo được tính theo `expiry_date - current_date` trong database, tránh lưu trạng thái cảnh báo bị cũ.

## Phân hệ Bản quyền & Gia hạn

Migration: `supabase/migrations/20261020_license_renewals.sql`

### `license_records` — hồ sơ bản quyền/dịch vụ

- Mã hồ sơ duy nhất, tên phần mềm/chữ ký số/dịch vụ, loại hồ sơ.
- Nhà cung cấp, số hợp đồng, ngày bắt đầu hợp đồng, ngày hết hạn.
- Chi phí năm, số lượng, phòng ban, người phụ trách và email liên hệ.
- Trạng thái nghiệp vụ, ghi chú và mốc nhắc 90/60/30/7 ngày.
- `created_by`, `updated_by` và `audit_logs` phục vụ truy vết.

### `license_renewal_history` — lịch sử gia hạn

Mỗi lần gia hạn là một dòng độc lập, lưu ngày hết hạn cũ/mới, ngày gia hạn, chi phí, nhà cung cấp, hợp đồng/chứng từ tham chiếu và người xử lý. Không ghi đè mất lịch sử các kỳ trước.

### `license_expiry_overview` — trạng thái hạn

View tính số ngày còn lại và nhóm cảnh báo theo ngày hiện tại: quá hạn, hết hạn hôm nay, còn 7/30/60/90 ngày trở xuống, hoặc còn hiệu lực. Đây là dữ liệu để dashboard hiển thị; thông báo email/tự động là hạng mục riêng cần cấu hình dịch vụ chạy định kỳ.

### Quyền truy cập

- Viewer: đọc hồ sơ và lịch sử.
- Editor/admin: tạo/cập nhật hồ sơ, thêm lịch sử gia hạn.
- Admin: xóa hồ sơ.
- RLS bật trên cả hai bảng; audit log được ghi từ trigger phía database.

## Lộ trình

### Giai đoạn A — Sự cố/sửa chữa (sheet `03_SU_CO_SUA_CHUA`)
1. Chuẩn hóa 13 dòng lịch sử nguồn.
2. Thêm mã sự cố nguồn (`source_record_code`) để giữ `SC-0001`... và chống nhập lặp.
3. Ánh xạ mã máy sang `assets.id`; không nhập nếu mã không tồn tại.
4. Bổ sung loại hồ sơ `Kiểm tra`; ánh xạ trạng thái `Đã xử lý` thành `Đã hoàn thành` sau khi xác nhận.
5. Thử nhập một số dòng, đối chiếu số lượng/chi phí/ngày, rồi mới nhập phần còn lại.

### Giai đoạn B — Bản quyền & Gia hạn
1. Chạy migration trên môi trường Supabase sau khi kiểm tra.
2. Thêm mục điều hướng và màn hình danh sách: tên, loại, nhà cung cấp, người phụ trách, ngày hết hạn, chi phí, trạng thái cảnh báo.
3. Thêm tạo/sửa hồ sơ và ghi nhận gia hạn; khi gia hạn, ghi lịch sử và cập nhật ngày hết hạn trong cùng một luồng thao tác.
4. Dashboard đếm hồ sơ trong các mốc 90/60/30/7 ngày và quá hạn.
5. Kiểm thử RLS với admin/editor/viewer; chưa bật gửi email cho đến khi có cơ chế chạy định kỳ và người nhận được xác định.

### Giai đoạn C — Linh kiện/kho
- Danh mục linh kiện, nhập/xuất, tồn kho và đơn giá.
- Chi tiết sử dụng linh kiện gắn với hồ sơ sửa chữa.
- Lưu dấu vết nhập/xuất và ngăn tồn kho âm.

### Giai đoạn D — Báo cáo và cảnh báo
- Báo cáo sự cố/chi phí, lịch sử tài sản, chi phí gia hạn và danh sách đến hạn.
- Xuất Excel/CSV.
- Nếu cần email tự động, dùng Supabase Edge Function + cron hoặc dịch vụ tương đương; không giả lập thông báo khi chưa cấu hình.

## Lưu ý bảo mật

Không lưu PIN token, mật khẩu, private key, OTP hoặc bí mật ký số. Chỉ lưu metadata quản lý và tham chiếu hợp đồng/chứng từ được phép lưu nội bộ.
