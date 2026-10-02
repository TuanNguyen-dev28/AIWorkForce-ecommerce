# ADR-003 — MySQL cho nền dữ liệu AI Workforce

- Ngày: 2026-10-02.
- Trạng thái: đã chọn MySQL và tên database local; các giả định nghiệp vụ và gate production bên dưới còn cần hoàn tất.
- Database local: `aiworkforce_ecommerce`.
- Công cụ quản trị: MySQL Workbench.
- Môi trường đã phát hiện: MySQL Server 8.0.46, MySQL Workbench 8.0. Việc phần mềm đã được cài không xác nhận service đang chạy hoặc migrations đã chạy thành công.

## Bối cảnh và quyết định

Người dùng chọn MySQL và MySQL Workbench để bắt đầu xây cơ sở dữ liệu. Kế hoạch MVP yêu cầu dữ liệu sản phẩm, đơn hàng, tồn kho cùng nền workflow, idempotency, approval và audit trước khi xây Agent.

Dùng InnoDB, `utf8mb4`, timestamps UTC, foreign keys, unique constraints và CHECK constraints. Migrations yêu cầu MySQL 8.0.16 trở lên vì các phiên bản trước chưa thực thi CHECK constraints. Workbench dùng để chạy và quan sát SQL; migration có version trong repository là nguồn chuẩn của schema.

Quyết định này chỉ chốt nền database. Queue/background worker, LLM provider, runtime framework, identity provider và kết nối hệ thống thương mại thật chưa được quyết định bởi ADR này.

## Schema và giả định khởi đầu

| Phần | Quyết định cho nền local/mock | Phần còn phải chốt |
|---|---|---|
| Tenant và actor | Có tenant từ đầu; mỗi actor thuộc một tenant và tham chiếu external identity subject. | Identity provider, role/permission và mô hình một người tham gia nhiều tenant. |
| Sản phẩm | Một product biểu diễn một SKU bán được. | Nhóm sản phẩm, biến thể, đơn vị quy đổi và mapping SKU từ nguồn thật. |
| Tồn kho | Số nguyên theo SKU/kho; không backorder; `0 <= reserved <= on_hand`. | Source of truth, reservation workflow, đơn vị hàng lẻ và reconciliation. |
| Tiền | DECIMAL và mã currency; số liệu đơn hàng có snapshot để giữ lịch sử. | Thuế, phí, hoàn tiền, multi-currency, quy tắc doanh thu và AOV. |
| Approval | Có `approval_requests` về mặt cấu trúc để phục vụ MVP. | Authentication, quyền duyệt, risk thresholds, policy versions, SLA và runtime workflow. |
| Dữ liệu | Seed chỉ chứa mock/demo, không phải dữ liệu từ hệ thống vận hành. | Hợp đồng tích hợp, failure semantics, quyền write và vận hành nguồn thật. |

Schema MVP gồm `tenants`, `actors`, `products`, `warehouses`, `inventory`, `orders`, `order_items`, `inventory_movements`, `idempotency_keys`, `workflow_runs`, `audit_events` và `approval_requests`. Cấu trúc persistence bổ trợ không đồng nghĩa đã có LangGraph checkpoint adapter. `customers`, `shipments`, `returns` và `support_tickets` thuộc Phase 11.

Mọi liên kết giữa các bảng thuộc tenant phải dùng composite foreign key có `tenant_id` cùng ID thực thể; parent có khóa unique tương ứng. Ràng buộc này ngăn gắn đơn hàng, sản phẩm, kho, actor hoặc workflow của tenant khác. Unique theo tenant áp dụng cho các định danh nghiệp vụ phù hợp.

## Ranh giới cách ly dữ liệu

MySQL không cung cấp native row-level policy tương đương PostgreSQL. Ba trách nhiệm cần phân biệt rõ:

1. Application/Repository phải áp `tenant_id` lấy từ RequestContext đã xác thực cho mọi query. LLM không quyết định danh tính hoặc scope. Connection pool và worker phải tránh reuse sai context.
2. Composite tenant foreign keys bảo vệ quan hệ dữ liệu. Least privilege tách quyền migration/quản trị khỏi quyền runtime; app không dùng tài khoản root. FK không giới hạn tập kết quả SELECT, và grants thông thường không tự áp bộ lọc theo từng tenant.
3. Nếu nhiều tenant dùng chung DB account có SELECT trên base tables, database vẫn cho phép account đó đọc nhiều tenant. Gate cách ly đọc database cho production còn mở: cần chọn và kiểm chứng tách database/account theo tenant hoặc một boundary routine/view không cấp base-table access trực tiếp, có danh tính tin cậy và không cho người gọi tự chọn tenant tùy ý.

Session variable như `@tenant_id` không tự tạo RLS; reset context cũng không biến một account quyền rộng thành account được cách ly theo tenant. MySQL view không thể tham chiếu trực tiếp user/system variables; `CURRENT_USER()` trong definer view trả danh tính definer theo mặc định. Vì vậy, không coi một view có bộ lọc giả định là lời giải đã kiểm chứng cho production.

Đợt nền database chưa cung cấp Repository/RequestContext/auth runtime. Customer-facing authorization chưa được triển khai; `customer_id` từ authenticated context và kiểm thử cross-customer là yêu cầu khi mở Phase 11. Không tuyên bố ứng dụng đã ngăn cross-tenant/cross-customer access chỉ vì SQL constraints hoặc kiểm tra FK chạy đúng.

## Trách nhiệm của database và Service

CHECK constraints kiểm tra bất biến trong một row, ví dụ số lượng không âm và reserved không lớn hơn on_hand. Không dùng CHECK để kiểm tra tổng đơn hàng với toàn bộ order items, quyền actor, approval hết hạn theo thời điểm thực thi hoặc nguồn dữ liệu bên ngoài. Các trường bắt buộc cần NOT NULL; CHECK có thể chấp nhận kết quả UNKNOWN khi dữ liệu NULL.

Service tương lai phải phối hợp khóa dòng hoặc optimistic concurrency, canonical payload hash, kiểm tra idempotency, mutation, inventory movement và business audit trong transaction đúng ranh giới. Cùng idempotency key/payload phải trả lại kết quả đã lưu; payload khác phải conflict. Schema có khóa và trường lưu trạng thái không tự hoàn thành các hành vi này.

Approval runtime phải ràng buộc payload/hash, tenant/workflow/action, policy/risk version và resource version; kiểm tra lại quyền, expiry và trạng thái tài nguyên trước khi execute. Có bảng approval không có nghĩa hành động đã được phê duyệt.

Audit và inventory movement được thiết kế append-only cho truy cập thông thường. Guards và least privilege không bảo đảm chống sửa bởi DBA. Trường hash/checkpoint chỉ là nền lưu trữ: append hash chain có serialization, kiểm chứng hash, audit atomic cùng mutation, retention và khôi phục checkpoint vẫn cần implementation và kiểm thử riêng.

## Artifact và thứ tự sử dụng

| Artifact | Vai trò |
|---|---|
| [001_initial_schema.sql](../../database/mysql/migrations/001_initial_schema.sql) | Migration cấu trúc đầu tiên. |
| [002_guards_and_views.sql](../../database/mysql/migrations/002_guards_and_views.sql) | Guards và views sau schema. |
| [001_demo.sql](../../database/mysql/seeds/001_demo.sql) | Seed demo/mock tùy môi trường local. |
| [bootstrap.sql](../../database/mysql/bootstrap.sql) | Entry point chạy trong MySQL Workbench theo hướng dẫn. |
| [README MySQL](../../database/mysql/README.md) | Cách kết nối, áp migrations, seed và dùng các SQL kiểm tra. |

Theo thứ tự `001_initial_schema.sql` rồi `002_guards_and_views.sql`, sau đó seed demo khi cần. SQL checks chỉ kiểm tra phần database nằm trong phạm vi của chúng; chúng không chứng minh authorization, service concurrency, workflow recovery hoặc cách ly đọc production. Không sửa schema bằng Workbench mà bỏ qua migration version trong repository.

Đợt này bàn giao nền database: schema, guards/views, seeds, SQL checks và bootstrap. Những phần chưa bàn giao gồm Repository, runtime policy/authentication, service concurrency/idempotency, checkpoint adapter và hash-chain verification. Không dùng các artifact này để đánh dấu Phase 0–5 đã hoàn tất.

## Điều kiện trước khi mở dữ liệu và write thật

- Chốt source of truth theo từng domain, quyền write, stale data, duplicate/out-of-order events, external failure semantics và reconciliation.
- Hoàn thiện RequestContext/Repository, permission matrix và kiểm thử tenant/warehouse scope; giải quyết gate cách ly đọc database khi có nhiều tenant.
- Triển khai service transaction, concurrency, idempotency recovery, approval execution và audit atomic; kiểm chứng bằng các gate trong PlanPhase.
- Chốt ngưỡng rủi ro, owner/người nghiệm thu, vận hành backup/restore và các tiêu chí nghiệm thu bằng thông tin nghiệp vụ thực tế. ADR không tự đặt ngưỡng, SLA hoặc ước lượng.

Trong khi các điều kiện này chưa đạt, nền local sử dụng mock; integration thật chỉ được mở ở phạm vi đọc đã được cấp quyền và kiểm chứng. Không tự bật inventory write thật từ việc đã tạo được schema.

## Tài liệu liên quan

- [PlanPhase.txt](../../PlanPhase.txt) là nguồn chuẩn về phạm vi, thứ tự và gate.
- [Kế hoạch kiến trúc](../../KẾ%20HOẠCH%20TRIỂN%20KHAI%20ĐỒ%20ÁN%20AI%20WORKFO.txt).
- [MySQL CHECK constraints](https://dev.mysql.com/doc/refman/8.0/en/create-table-check-constraints.html).
- [MySQL CREATE VIEW](https://dev.mysql.com/doc/refman/8.0/en/create-view.html).
- [MySQL foreign keys](https://dev.mysql.com/doc/refman/8.0/en/create-table-foreign-keys.html).
