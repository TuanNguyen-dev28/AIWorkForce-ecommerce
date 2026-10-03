# ADR-005 — Tooling và runtime cho Phase 1

- Ngày: 2026-10-03.
- Trạng thái: triển khai cho môi trường phát triển; không đóng các gate nghiệp vụ Phase 0.

Dùng Python 3.11 (range `>=3.11,<3.12`), FastAPI, Pydantic Settings và PyMySQL.
Python 3.11 đã có trên máy và hỗ trợ cùng runtime trên CI/Docker. Dùng uv 0.12.22 để tạo
lockfile đa nền tảng; `uv sync --locked` kiểm tra lockfile khớp với project metadata.
Ruff format/lint, mypy strict và pytest tạo kiểm tra tối thiểu trước khi mở thêm domain.

Giữ cấu trúc package ở root theo kiến trúc và tiếp tục dùng SQL numbered migrations đã có.
Runner Python xử lý DELIMITER, checksum, advisory lock, trạng thái chạy và partial DDL failure.
Không đưa Alembic/ORM vào chỉ để quản lý schema hiện chưa có models; lựa chọn ORM có thể xem lại
khi xây Repository ở Phase 2. Phạm vi runner hiện tại chỉ dev/test và tên DB đã chốt trong ADR-003.

LLM health có mock và disabled. Chưa chọn provider, model, LangGraph, queue, UI framework,
source of truth hay write permission. Staging/production template chưa thể dùng như triển khai
production hoàn chỉnh. Secret manager và đọc DB theo tenant vẫn là gate còn mở.

Health/live không phụ thuộc tài nguyên bên ngoài; readiness fail khi DB/provider chưa sẵn sàng.
Log chỉ chứa fixed event và metadata theo allowlist; không log URL, body, headers, message
hay nội dung exception. CostAccounting là Protocol với implementation stub trong RAM.

CI chạy secret scan không baseline và dependency audit toàn bộ dependency đã khóa.
GitHub required status checks cần ruleset phía remote, không thể được thực thi chỉ từ YAML.

MySQL trong Compose local tắt binary log để tạo trigger bằng account dev có quyền schema,
không phải cấp SUPER toàn server; xem [MySQL CREATE TRIGGER](https://dev.mysql.com/doc/refman/8.0/en/create-trigger.html).

Tham khảo: [uv lock và sync](https://docs.astral.sh/uv/concepts/projects/sync/),
[FastAPI lifespan](https://fastapi.tiangolo.com/advanced/events/),
[pip-audit](https://pypi.org/project/pip-audit/).
