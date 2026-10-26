# Quản trị hành chính — Hệ thống quản trị nội bộ

© 2026 Quản trị hành chính.

Ứng dụng nội bộ quản lý tài sản, thiết bị, bảo trì, dịch vụ thuê ngoài, điện nước và tài khoản người dùng. Giao diện web tĩnh dùng Supabase Auth, PostgreSQL/RLS và Supabase Edge Functions cho các thao tác quản trị đặc quyền.

## Hiện đã có trong bộ mã nguồn
- `index.html`: giao diện Quản trị hành chính, đăng nhập Supabase Auth, danh mục tài sản và trang quản lý tài khoản chỉ dành cho Admin.
- `supabase/schema.sql`: schema PostgreSQL và RLS cho các bảng nghiệp vụ; vai trò `admin`, `editor`, `viewer`.
- `supabase/migrations/20261028_admin_user_management.sql`: khóa quyền tự nâng vai trò, chỉ Admin được quản trị bảng vai trò.
- `supabase/functions/admin-users/index.ts`: Edge Function bảo vệ bằng JWT + kiểm tra vai trò Admin, dùng service-role key chỉ ở phía server để tạo tài khoản, đổi vai trò, vô hiệu hóa/kích hoạt và liệt kê tài khoản.
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

### 2. Cấp quyền Admin đầu tiên
1. Tạo tài khoản đầu tiên trong **Supabase → Authentication → Users → Add user**.
2. Trong SQL Editor, cấp vai trò Admin bằng email đã tạo (thay email mẫu):
   ```sql
   insert into public.user_roles(user_id, role)
   select id, 'admin' from auth.users where lower(email) = lower('admin@example.com')
   on conflict (user_id) do update set role = 'admin';
   ```
3. Chỉ thực hiện bootstrap này cho tài khoản quản trị tin cậy đầu tiên. Không cho người dùng tự đăng ký hoặc tự cập nhật vai trò.
4. Chạy migration `supabase/migrations/20261028_admin_user_management.sql` trong **SQL Editor** của project hiện có.

### 3. Triển khai Edge Function quản lý tài khoản
1. Cài đặt và đăng nhập Supabase CLI, liên kết đúng project ID.
2. Đảm bảo secret `SUPABASE_SERVICE_ROLE_KEY` có trong môi trường Edge Functions của project. Lấy key từ Supabase Dashboard; **không commit key vào repository, không đưa vào `index.html`**.
3. Từ thư mục repository, triển khai:
   ```bash
   supabase functions deploy admin-users
   ```
4. Xác nhận Function `admin-users` đã deploy thành công trong Supabase Dashboard.
5. Đăng nhập bằng Admin trên website để mở **Tài khoản người dùng**. Admin có thể tạo user với email, mật khẩu ban đầu (tối thiểu 8 ký tự) và vai trò Admin/Editor/Viewer.
6. Gửi mật khẩu ban đầu qua kênh riêng an toàn và yêu cầu người dùng đổi mật khẩu sau lần đăng nhập đầu tiên. Hiện ứng dụng không tự gửi email mời hoặc tự ép đổi mật khẩu.

**Lưu ý bảo mật:** không tạo chức năng đăng ký công khai. Chỉ Admin được phép cấp vai trò. RLS phải được kiểm thử trên dữ liệu thật; không bật đọc công khai mặc định cho dữ liệu nội bộ.
1. Giải nén ZIP.
2. Trong repository `longak83/longit-equipment-management`, upload `index.html`, `README.md` và thư mục `supabase` (các file nằm ở root repository, không để lồng thêm thư mục `longit-v2`).
3. Commit lên nhánh `main`.
4. Vào **Settings → Pages → Deploy from a branch → `main` → `/(root)` → Save**.
5. Địa chỉ dự kiến: `https://longak83.github.io/longit-equipment-management/`. Trang quản lý tài khoản chỉ hiện với Admin; thao tác đặc quyền được xác thực lại trong Edge Function.

## Mô hình dữ liệu
- `assets`: dữ liệu tài sản chung; mã tài sản duy nhất.
- `asset_categories`, `asset_attribute_definitions`, `asset_attribute_values`: nhóm và thuộc tính mở rộng.
- `maintenance_records`: sự cố, sửa chữa, bảo trì, kiểm định.
- `asset_assignments`, `asset_transfers`: bàn giao và điều chuyển.
- `departments`, `locations`: danh mục tổ chức/vị trí.
- `profiles`, `user_roles`: hồ sơ và phân quyền người dùng.
- `audit_logs`: nhật ký thay đổi cho bảng tài sản.
- `module_permissions`: phân quyền theo module và thao tác; hiện triển khai cho module phương tiện (xem/thêm/sửa/xóa mềm/xuất báo cáo).
- Nhật ký bất biến cho tài sản, đăng kiểm/bảo hiểm, hồ sơ sửa chữa và thay đổi phân quyền module; lưu dữ liệu trước/sau và actor.
- Xóa mềm hồ sơ xe và hồ sơ sửa chữa; Admin có thể xem hồ sơ xe đã xóa và khôi phục từ danh mục tài sản.

### 4. Phân quyền module phương tiện và nhật ký thao tác
1. Chạy migration `supabase/migrations/20261029_vehicle_permissions_audit_soft_delete.sql` trong **Supabase SQL Editor** sau khi các migration về tài sản, tài khoản và `vehicle_details` đã được áp dụng.
2. Trong **Tài khoản người dùng**, bấm **Quyền phương tiện** ở tài khoản cần phân công, rồi chọn quyền xem/thêm/sửa/xóa mềm/xuất báo cáo. Khi đã có cấu hình riêng cho module `vehicles`, các quyền này thay thế quyền Editor mặc định đối với dữ liệu ô tô.
3. Xóa hồ sơ xe là xóa mềm; dữ liệu vẫn còn trong database và audit log. Admin có thể bật **Hiện hồ sơ đã xóa** để khôi phục.
4. Hồ sơ sửa chữa của xe cũng hỗ trợ xóa mềm; nhật ký lưu người thao tác, thời điểm và bản ghi trước/sau. Không cấp quyền ghi trực tiếp vào `audit_logs`.
5. Migration chỉ được thêm vào repository; **chưa tự chạy trên Supabase**. Chạy migration trên đúng project trước khi sử dụng các nút mới.

## Kiểm tra trước khi sử dụng thật
- Thử bằng ba tài khoản `admin`, `editor`, `viewer`; xác nhận viewer không thể ghi dữ liệu ngay cả khi gọi API trực tiếp.
- Xác nhận người không phải Admin nhận HTTP 403 từ Edge Function; không thể tự nâng vai trò qua REST API.
- Kiểm tra tạo tài khoản, email trùng, mật khẩu yếu, đổi vai trò, vô hiệu hóa/kích hoạt và bảo vệ Admin cuối cùng.
- Kiểm tra audit log, sao lưu và khôi phục dữ liệu.
- Tên hiển thị hiện tại là **Quản trị hành chính**; tên repository/URL GitHub vẫn là `longit-equipment-management` để không làm hỏng đường dẫn website.
