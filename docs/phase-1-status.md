# Bàn giao Phase 1

Ngày kiểm tra: 2026-10-03 (Asia/Saigon).
Phạm vi: nền tảng phát triển local/mock theo `PlanPhase.txt`; không đóng gate Phase 0 hoặc Phase 2–5.

| Deliverable | Trạng thái / artifact |
|---|---|
| Cấu trúc thư mục theo kiến trúc | Đã tạo đầy đủ package/layer theo Phase 1; module phase sau là placeholder rõ trách nhiệm. |
| Runtime và dependency lock | Python 3.11, `pyproject.toml`, `uv.lock`, `.python-version`; [ADR-005](decisions/ADR-005-phase-1-tooling.md). |
| Formatter/linter/type checker | Ruff format/lint, mypy strict. |
| Cấu hình dev/staging/production | `.env.example`, `config/*.env.example`, settings validation và Git ignore secret. |
| API / Database / LLM health | `/health/live`, `/health/database`, `/health/llm`, `/health/ready`; LLM mock/disabled. |
| Structured logging và correlation | JSON, validated correlation ID, workflow context, metadata allowlist, sanitized driver/config errors. |
| Migration framework | Python runner, checksum chuẩn hóa newline, advisory lock, pending/status, recovery khi partial DDL. |
| CI | `.github/workflows/ci.yml`: lint, format, type check, unit/security/evaluation, secret/dependency scan, MySQL integration. |
| Secret/dependency scanning | Không có baseline; scan runtime/dev dependency đã khóa; test chứng minh detector bắt secret giả. |
| Cost accounting | Protocol + stub trong RAM; tách workflow/currency; chưa có pricing hoặc durable storage. |
| Test harness | Contracts và fake cho authorization, policy, idempotency, audit; không phải implementation runtime. |
| Docker local | Dockerfile, Compose với MySQL và migration service; cấu hình đã kiểm tra, chưa chạy container. |
| Hướng dẫn cài đặt/vận hành | [README](../README.md), [MySQL README](../database/mysql/README.md), [migration runbook](runbooks/migrations.md). |

## Bằng chứng kiểm tra local

- `ruff check .` và `ruff format --check .`: pass.
- `mypy`: pass.
- `pytest -m "not integration"`: 35 test unit/security/evaluation pass.
- `python -m scripts.verify_mysql`: 1 test integration pass; fresh installation, no-op replay, checksum mismatch,
  partial DDL failure và chặn retry được kiểm chứng trên instance MySQL 8.0.46 riêng.
- `database/mysql/scripts/verify_schema.py`: bootstrap, seed, constraints, integrity checks,
  doanh thu/AOV, order totals và 16 bảng của schema cũ pass.
- `python -m scripts.secret_scan`: không có findings. Hai dòng allowlist cụ thể chỉ là flag
  allow-empty-password của service CI disposable và giá trị synthetic trong test logging.
- `pip-audit` trên toàn bộ dependency được export từ lockfile: không có lỗ hổng đã biết.
- `docker compose config --quiet`: pass với credentials giả; Docker Engine hiện chưa chạy.
- Cài một virtualenv mới bằng `uv sync --locked --offline` từ cache dependency đã tải;
  tests và mypy pass trong môi trường mới. API Uvicorn thực tế được khởi động trên loopback,
  cả bốn health endpoint và correlation/JSON log được kiểm tra, sau đó dừng process.
- Có một deprecation warning từ Starlette TestClient về HTTPX; test vẫn pass.

## Gate chưa đóng

1. CI chưa chạy trên GitHub vì thay đổi còn trong workspace. Bật required checks
   `Quality (Python 3.11)` và `MySQL migration integration` trong branch protection/ruleset
   của repository trước merge; YAML không tự bật remote setting này.
2. Chưa có kết quả build/run Docker Engine. Cấu hình Compose đã được parse thành công;
   cần chạy `docker compose up --build` khi Docker Engine sẵn sàng.
3. LLM provider thật chưa được chọn ở Phase 0. Probe hiện chỉ xác nhận mock/disabled, không
   xác nhận kết nối provider ngoài. Cost accounting và security harness đúng phạm vi stub.

Chủ sở hữu/người nghiệm thu, effort và ngày mục tiêu trong issue tracker vẫn cần thông tin
được chốt theo quy ước 0.4; không tự gán người phụ trách, thời hạn hoặc ngưỡng chất lượng.
Trạng thái này không tuyên bố Phase 1 đã đóng toàn bộ gate trên remote hoặc production-ready.
