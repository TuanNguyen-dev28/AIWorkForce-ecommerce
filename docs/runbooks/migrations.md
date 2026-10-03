# Vận hành migration local/test

Runner: `uv run --locked python -m database.migrate apply`.
Đặt `APP_ENV=dev` hoặc `test`, `DATABASE_ENABLED=true`, host/port/user/password trong `.env`
hoặc biến môi trường. Account migration cần CREATE trên DB dự án và quyền DDL/DML cho schema.
Không dùng runner Phase 1 trên production; production migration role và TLS còn cần triển khai.

## Fresh installation

1. Chọn server local/disposable. Không chọn server có dữ liệu chưa sao lưu.
2. Chạy `python -m database.migrate apply` trong môi trường uv. Runner tạo DB nếu chưa tồn tại,
   sau đó áp `001`, `002` và ghi `_migration_runs`. Nó không seed hoặc cấp quyền.
3. Chạy `python -m database.migrate status`; khi đầy đủ, hiển thị `Pending: none`.
4. Chạy lại apply là no-op. Migration đã áp mà đổi nội dung sẽ bị checksum mismatch.

Checksum dùng UTF-8 không BOM, normalize newline qua `read_text` để clone Windows/Linux tương đương.
SQL được parse trước khi execute; hỗ trợ chuỗi, quoted identifier, comment thường và DELIMITER.
Executable MySQL version comments (`/*! ... */`) bị từ chối. Mỗi SQL file phải ghi marker vào
`schema_migrations` khi hoàn thành, theo pattern migrations hiện tại.

## SQL chạy trước bằng Workbench

`bootstrap.sql` và migrations cũ ghi `schema_migrations` nhưng không có checksum/history runner.
Runner từ chối tự đánh dấu schema này là đã kiểm chứng. Không thêm checksum thủ công chỉ để bỏ qua
lỗi. Giữ database hiện có, dùng instance/volume dev trống cho runner; đối với DB cần bảo tồn,
backup, đối chiếu schema và thiết kế baseline adoption ở Phase 2 trước khi chuyển công cụ.

## Failure và rollback

MySQL DDL implicit commit; runner không hứa rollback bằng transaction. `_migration_runs` ghi
STARTED trước execute; lỗi chuyển FAILED nếu còn kết nối, hoặc giữ STARTED nếu mất kết nối.
Cả hai trạng thái đều chặn rerun. Advisory lock ngăn hai runner cùng áp migration trên server.

Khi thất bại: dừng mọi thay đổi schema, kiểm tra version/history và objects đã tạo, lưu log,
backup dữ liệu cần giữ. Với instance disposable có thể tạo instance mới và chạy lại từ đầu.
Với DB cần giữ phải lập corrective migration hoặc restore từ backup đã xác nhận; không tự xóa
bảng/history, không sửa numbered migration đã áp và không auto-retry DDL không rõ trạng thái.
RPO/RTO và quy trình restore production chưa được chốt ở Phase 0.

Docker Compose chạy migration service trước API và giữ MySQL volume khi dừng. Runner Windows
`scripts.verify_mysql` tạo datadir riêng `.local`, dùng PID path ASCII để tương thích tên máy
có Unicode, dừng process do chính nó tạo sau test và giữ artifact để điều tra.
