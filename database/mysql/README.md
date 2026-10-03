# Nền dữ liệu MySQL

Database: `aiworkforce_ecommerce`; MySQL >= 8.0.16; InnoDB, utf8mb4 và UTC.
Quyết định và giới hạn tại [ADR-003](../../docs/decisions/ADR-003-mysql.md).

Fresh dev dùng migration runner có checksum/history:

```powershell
uv run --locked python -m database.migrate apply
uv run --locked python -m database.migrate status
```

Đặt database credentials trong `.env` bị ignore. Xem [migration runbook](../../docs/runbooks/migrations.md)
để xử lý lỗi DDL hoặc database đã được tạo bằng Workbench.

Nếu chọn Workbench cho installation mới, mở `bootstrap.sql` và Execute All trên connection local
đúng mục tiêu, dừng khi có lỗi. File được build bằng `scripts/build_bootstrap.py`, gồm tạo DB,
`001_initial_schema.sql`, `002_guards_and_views.sql`. Không chạy lại bootstrap trên schema đã có.
Chỉ chọn một đường installation; Workbench bootstrap không có checksum ledger của Python runner.

Seed mock tùy chọn: `seeds/001_demo.sql`. Kiểm tra: `checks/001_integrity_checks.sql` và
`tests/constraints.sql`. Ví dụ báo cáo trong `queries/analytics_examples.sql`.
Trên Windows, `uv run --locked python database/mysql/scripts/verify_schema.py` tự tạo instance
MySQL shared-memory, networking disabled, để chạy SQL/seed/constraints riêng với service MySQL80.

SQL constraints không thay thế Repository, authentication, policy, service transaction,
idempotency runtime, approval hoặc audit hash-chain. Không mở write thật bằng việc có schema.
