# Longit — Quản lý thiết bị văn phòng

© 2026 Longit — All rights reserved.

## Nội dung hiện tại
- `index.html`: giao diện dashboard, danh mục thiết bị, nhật ký sự cố và lý lịch thiết bị dựa trên bản demo.
- `supabase/schema.sql`: khung database bảo vệ bằng Row Level Security cho bước tích hợp tiếp theo.

## Lưu ý quan trọng
Bản `index.html` hiện là bản giao diện demo: dữ liệu mẫu đang nằm trong mã nguồn và nút đăng nhập quản lý chỉ là placeholder, CHƯA có xác thực thật hoặc lưu dữ liệu lên database. Không đưa file này lên hosting công khai nếu dữ liệu bên trong là dữ liệu thật/nội bộ. Trước khi dùng thật, cần thay dữ liệu mẫu bằng dữ liệu phù hợp, kết nối Supabase Auth + database, và bật RLS.

## Đưa lên GitHub
1. Tải ZIP này và giải nén.
2. Trong repository đã tạo, chọn **Add file → Upload files**.
3. Tải lên `index.html`, `README.md` và thư mục `supabase` (hoặc tải từng file nếu giao diện web không nhận thư mục).
4. Commit changes.
5. Vào **Settings → Pages**, chọn **Deploy from a branch**, branch `main`, folder `/ (root)`, rồi Save.
6. Địa chỉ website thường có dạng `https://USERNAME.github.io/REPOSITORY/`.

## Bước tiếp theo để dùng thật
Tạo project Supabase, chạy `supabase/schema.sql` trong SQL Editor, bật Email Auth và tạo tài khoản admin. Sau đó cần tích hợp frontend với Supabase bằng Project URL và publishable/anon key (không phải service-role key), cùng RLS policies. Không bao giờ nhúng mật khẩu hay service-role key vào `index.html`.
