# AI Workforce — E-commerce B2C

Nền tảng phát triển Phase 1: Python 3.11, FastAPI, MySQL 8.0.16+, uv,
Ruff, mypy, pytest, detect-secrets và pip-audit. Phiên bản dependency chính xác nằm trong
`uv.lock`. Phạm vi và thứ tự triển khai nằm trong [PlanPhase.txt](PlanPhase.txt).

## Cài đặt từ repository mới

Cần Git, Python 3.11 và uv 0.12.22. Có thể cài uv bằng
`py -3.11 -m pip install uv==0.12.22` trên Windows hoặc
`python3.11 -m pip install uv==0.12.22` trên Linux/macOS.

```powershell
git clone https://github.com/TuanNguyen-dev28/AIWorkForce-ecommerce.git
Set-Location AIWorkForce-ecommerce
uv sync --locked
Copy-Item .env.example .env
uv run --locked pytest -m "not integration"
uv run --locked uvicorn api.main:factory --factory --host 127.0.0.1 --port 8000 --no-access-log
```

Linux/macOS dùng `cd` thay `Set-Location`, `cp .env.example .env` thay `Copy-Item`.
Chạy các lệnh từ thư mục gốc repo. Uvicorn access log được tắt để không ghi query string
hoặc PII vào log. API có JSON logging riêng. Trong môi trường dev, xem OpenAPI tại
`http://127.0.0.1:8000/docs`.

| Endpoint | Ý nghĩa |
|---|---|
| `GET /health/live` | API còn hoạt động; không gọi DB/LLM. |
| `GET /health/database` | Kết nối MySQL và `SELECT 1`; lỗi trả 503 cùng mã lỗi cố định. |
| `GET /health/llm` | Provider mock trả 200 và `mode=mock`; disabled trả 503. |
| `GET /health/ready` | 200 khi DB và provider probe đều ổn; còn lại 503. |

Mặc định DB bị tắt, vì vậy liveness trả 200, readiness trả 503. Đây là cấu hình dev hợp lệ.
DB health chỉ kiểm tra kết nối, không xác nhận schema hay khả năng phục vụ nghiệp vụ.
Provider thật chưa được chọn; health LLM hiện chỉ có mock/disabled, không gọi model tính phí.
Không có API nghiệp vụ hay endpoint ghi tồn kho trong Phase 1.

## Cấu hình và secret

- `.env.example` chứa giá trị mẫu không có secret; file `.env` và `.env.*` bị Git bỏ qua.
- `config/dev.env.example`, `config/staging.env.example`, `config/production.env.example`
  là template. Có thể chọn file bằng biến `ENV_FILE`; biến môi trường luôn ưu tiên hơn file.
- Staging/production cần credentials DB, từ chối account `root` và provider mock.
  `LLM_PROVIDER=disabled` giữ readiness không sẵn sàng cho đến khi triển khai provider thật.
- Inject secret từ hệ thống triển khai; không đưa credentials vào source, command line,
  fixture, log hoặc báo lỗi. Hạ tầng secret manager sẽ được chốt ở Phase 0.
- Thay đổi `.env` cần khởi động lại API. Settings được cố định cho mỗi instance.

## Chất lượng mã nguồn

```powershell
uv run --locked ruff check .
uv run --locked ruff format --check .
uv run --locked mypy
uv run --locked pytest -m "not integration"
uv run --locked pytest -m security
uv run --locked pytest -m evaluation
uv run --locked python -m scripts.secret_scan
uv export --locked --no-emit-project --format requirements-txt --output-file .local/audit-requirements.txt --quiet
uv run --locked pip-audit --strict --no-deps --disable-pip -r .local/audit-requirements.txt --cache-dir .local/pip-audit-cache
```

Tạo thư mục `.local` trước lệnh export nếu chưa có (`New-Item -ItemType Directory .local`
trên Windows; `mkdir -p .local` trên Linux). Secret scan kiểm tra cả file tracked và file
chưa tracked nhưng không bị ignore; findings chỉ in đường dẫn/dòng/loại, không in giá trị.
Secret scan tắt credential verification qua mạng. Dependency scan cần truy cập PyPI,
kiểm tra cả dependency runtime và development trong lockfile.
Không có baseline cho phép bỏ qua secret hoặc lỗ hổng đã biết.

Workflow [CI](.github/workflows/ci.yml) chạy trên PR, push vào main/master và khi kích hoạt thủ công,
gồm quality, security/evaluation harness và integration MySQL trống. Repository admin cần
bật branch protection/ruleset với hai required checks `Quality (Python 3.11)` và
`MySQL migration integration` trước merge. File workflow không tự bật cài đặt GitHub này.

## MySQL và migration

Xem [README MySQL](database/mysql/README.md) và [migration runbook](docs/runbooks/migrations.md).
Không chạy integration test lên server có dữ liệu thật. Trên Windows có MySQL Server đã cài:

```powershell
uv run --locked python -m scripts.verify_mysql
```

Lệnh tạo instance tạm riêng, bind loopback trên port ngẫu nhiên, chạy test và dừng instance.
Data/log giữ trong `.local/phase1-mysql-*` để kiểm tra. Không dùng datadir của service MySQL80.
SQL constraints/seed có runner riêng:

```powershell
uv run --locked python database/mysql/scripts/verify_schema.py
```

## Docker cho local

Cần Docker Engine/Compose đang chạy. Tự tạo `MYSQL_APP_PASSWORD` và `MYSQL_ROOT_PASSWORD`
trong môi trường local hoặc `.env` bị ignore, sau đó:

```powershell
docker compose up --build
```

MySQL lưu trong volume `mysql_dev`, không publish port DB; migration service chạy trước API.
API chỉ publish trên `127.0.0.1:8000`. MySQL dev tắt binary log để account migration có thể tạo
trigger mà không cần quyền SUPER toàn server. Account dev được quyền tạo schema objects; đây không phải
permission model production. Compose không seed tự động. `docker compose down` dừng container
và giữ volume. Không dùng `down -v` khi cần giữ dữ liệu.

## Ranh giới các module

| Module | Trách nhiệm |
|---|---|
| `api`, `schemas`, `config` | HTTP entry point, contract và settings. |
| `observability`, `llm` | Correlation, logging, cost accounting stub và provider health. |
| `database` | Connection và migration; SQL hiện có nằm ở `database/mysql`. |
| `security`, `business`, `audit` | Protocol cho test harness; runtime xây ở Phase 2–5. |
| `fixtures`, `tests`, `evaluation` | Dữ liệu giả và các suite; không import fixture vào runtime. |
| `agents`, `tools`, `orchestration`, `approvals`, `services`, `ui` | Package giữ chỗ cho phase sau. |

`TrustedContext` trong harness chỉ là contract giả, chưa có authentication. Fake authorization,
policy, idempotency và audit không chứng minh ứng dụng đã có các boundary production.
Cost accounting là stub trong RAM, không bền vững, không có bảng giá provider hoặc ngân sách giả định.
`workflow_id` có trong log schema; health request chưa có workflow nên giá trị là null.
Migration và cost event có workflow ID thật do thành phần deterministic đặt.

Theo dõi bàn giao và phần gate còn mở tại [Phase 1 status](docs/phase-1-status.md).
