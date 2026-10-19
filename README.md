# Longit — Quản lý tài sản & thiết bị

© 2026 Longit — All rights reserved.

Đây là bộ nền tảng MVP mở rộng từ dashboard Longit: giao diện responsive, đăng nhập Supabase Auth, danh mục tài sản dùng chung, tìm kiếm/lọc, thêm/sửa/xóa có phân quyền tại database và schema cho nghiệp vụ mở rộng.

## Hiện đã có trong bộ mã nguồn
- `index.html`: giao diện Longit, dashboard, danh mục tài sản, đăng nhập thật qua Supabase Auth, CRUD tài sản, lọc theo nhóm/trạng thái.
- `supabase/schema.sql`: schema PostgreSQL, RLS, vai trò admin/editor/viewer, danh mục nhóm thiết bị, hồ sơ tài sản, sự cố/bảo trì, bàn giao, điều chuyển, thuộc tính mở rộng và audit log cho bảng assets.
- Không nhúng dữ liệu tài sản thật vào mã nguồn. Khi chưa cấu hình Supabase, ứng dụng không ghi dữ liệu và không giả lập đăng nhập.

## Triển khai

### 1. Tạo Supabase project
1. Tạo project tại https://supabase.com/.
2. Mở **SQL Editor → New query**, dán toàn bộ `supabase/schema.sql`, chạy một lần.
3. Vào **Project Settings → API** (hoặc Connect), lấy **Project URL** và **publishable key/anon key**.
4. Mở `index.html`, tìm hai dòng đầu phần script:
   ```js
   const SUPABASE_URL='';
   const SUPABASE_ANON_KEY='';
   ```
   Điền URL và publishable/anon key. Chỉ dùng key công khai dành cho frontend; tuyệt đối không dùng `service_role`/secret key trong trình duyệt.

### 2. Tạo tài khoản admin
1. Trong Supabase, vào **Authentication → Users → Add user**, tạo user với email và mật khẩu của bà.
2. Sao chép UUID của user vừa tạo.
3. Trong SQL Editor, chạy câu lệnh dưới đây, thay UUID mẫu bằng UUID thật:
   ```sql
   insert into public.user_roles(user_id, role)
   values ('00000000-0000-0000-0000-000000000000', 'admin')
   on conflict (user_id) do update set role = excluded.role;
   ```
4. Đăng nhập từ nút **Đăng nhập quản lý** trên web.

**Lưu ý bảo mật:** không tạo chức năng đăng ký công khai. Chỉ admin được phép cấp vai trò. Chính sách RLS mặc định yêu cầu đăng nhập để đọc dữ liệu tài sản và chỉ admin/editor được thêm/sửa; chỉ admin được xóa. Đây là lựa chọn an toàn cho dữ liệu nội bộ. Nếu muốn trang tra cứu không cần đăng nhập, hãy chỉ bật quyền đọc công khai sau khi xác nhận toàn bộ trường dữ liệu trong `assets` được phép công khai; không bật một cách mặc định cho dữ liệu nội bộ.

### 3. Đưa lên GitHub Pages
1. Giải nén ZIP.
2. Trong repository `longak83/longit-equipment-management`, upload `index.html`, `README.md` và thư mục `supabase` (các file nằm ở root repository, không để lồng thêm thư mục `longit-v2`).
3. Commit lên nhánh `main`.
4. Vào **Settings → Pages → Deploy from a branch → `main` → `/(root)` → Save**.
5. Địa chỉ dự kiến: `https://longak83.github.io/longit-equipment-management/`.

## Mô hình dữ liệu
- `assets`: dữ liệu tài sản chung; mã tài sản duy nhất.
- `asset_categories`, `asset_attribute_definitions`, `asset_attribute_values`: nhóm và thuộc tính mở rộng.
- `maintenance_records`: sự cố, sửa chữa, bảo trì, kiểm định.
- `asset_assignments`, `asset_transfers`: bàn giao và điều chuyển.
- `departments`, `locations`: danh mục tổ chức/vị trí.
- `profiles`, `user_roles`: hồ sơ và phân quyền người dùng.
- `audit_logs`: nhật ký thay đổi cho bảng tài sản.

## Phạm vi MVP và các bước tiếp theo
MVP hiện hoàn thiện kết nối Auth + danh mục tài sản CRUD. Các màn hình sự cố/bảo trì, bàn giao/điều chuyển, tải tệp, import Excel/CSV và báo cáo nâng cao được thiết kế trong schema/lộ trình nhưng chưa có UI nghiệp vụ hoàn chỉnh. Trước khi dùng dữ liệu thật, kiểm tra login, RLS bằng tài khoản không có role, quyền editor/admin, mã tài sản trùng, sao lưu và khôi phục dữ liệu.
