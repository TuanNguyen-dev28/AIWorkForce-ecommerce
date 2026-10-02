-- MOCK fixtures only. No real customer data, credentials, model training data,
-- production writes or completed approval executions are represented here.
-- Run once AFTER migrations 001 and 002, with stop-on-error enabled.
-- Plain INSERT deliberately fails on a rerun; never use --force / INSERT IGNORE.
-- If any statement fails, issue ROLLBACK in the SAME connection before continuing.
-- All tenant data, stock openings, ledger entries and their control records commit
-- together. Fixed IDs and dates make analytics reproducible.
USE aiworkforce_ecommerce;
SET NAMES utf8mb4;
SET SESSION time_zone = '+00:00';

-- SHA-256 below hashes these exact ASCII JSON strings, including key order and
-- with no whitespace. These demo bytes are explicit fixtures, NOT a general JSON
-- canonicalization algorithm. A backend must define canonicalization separately.
SET @demo_open_1 = '{"action":"mock_opening_balance","rows":[{"inventory_id":1301,"on_hand":40,"reserved":4},{"inventory_id":1302,"on_hand":8,"reserved":2},{"inventory_id":1303,"on_hand":15,"reserved":0},{"inventory_id":1304,"on_hand":5,"reserved":1},{"inventory_id":1305,"on_hand":30,"reserved":0}],"tenant_id":1001}';
SET @demo_open_2 = '{"action":"mock_opening_balance","rows":[{"inventory_id":2301,"on_hand":70,"reserved":3},{"inventory_id":2302,"on_hand":4,"reserved":0}],"tenant_id":1002}';
SET @demo_approval = '{"action":"adjust_inventory","inventory_id":1302,"quantity_delta":12,"tenant_id":1001,"version":1}';

START TRANSACTION;

INSERT INTO tenants
  (id, code, name, default_currency, timezone, created_at, updated_at)
VALUES
  (1001, 'demo_shop', 'MOCK Demo Shop', 'VND', 'Asia/Ho_Chi_Minh', '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (1002, 'isolation_shop', 'MOCK Isolation Shop', 'VND', 'Asia/Ho_Chi_Minh', '2026-09-01 00:00:00', '2026-09-01 00:00:00');

INSERT INTO actors
  (id, tenant_id, identity_provider, external_subject, display_name, actor_type, created_at, updated_at)
VALUES
  (1001, 1001, 'MOCK', 'mock-service-1', 'MOCK Import Service 1', 'SERVICE', '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (1002, 1001, 'MOCK', 'mock-operator-1', 'MOCK Operator 1', 'HUMAN', '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (1003, 1001, 'MOCK', 'mock-approver-1', 'MOCK Approver 1', 'HUMAN', '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (2001, 1002, 'MOCK', 'mock-service-2', 'MOCK Import Service 2', 'SERVICE', '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (2002, 1002, 'MOCK', 'mock-operator-2', 'MOCK Operator 2', 'HUMAN', '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (2003, 1002, 'MOCK', 'mock-approver-2', 'MOCK Approver 2', 'HUMAN', '2026-09-01 00:00:00', '2026-09-01 00:00:00');

-- Demo grants express application roles only; they do not create MySQL users.
INSERT INTO actor_roles (tenant_id, actor_id, role_code, granted_by, created_at)
VALUES
  (1001, 1001, 'INTEGRATION', 1003, '2026-09-01 00:00:00'),
  (1001, 1002, 'OPERATOR', 1003, '2026-09-01 00:00:00'),
  (1001, 1002, 'ANALYST', 1003, '2026-09-01 00:00:00'),
  (1001, 1003, 'ADMIN', 1003, '2026-09-01 00:00:00'),
  (1001, 1003, 'APPROVER', 1003, '2026-09-01 00:00:00'),
  (1002, 2001, 'INTEGRATION', 2003, '2026-09-01 00:00:00'),
  (1002, 2002, 'OPERATOR', 2003, '2026-09-01 00:00:00'),
  (1002, 2002, 'ANALYST', 2003, '2026-09-01 00:00:00'),
  (1002, 2003, 'ADMIN', 2003, '2026-09-01 00:00:00'),
  (1002, 2003, 'APPROVER', 2003, '2026-09-01 00:00:00');

-- Identical SKU values in separate tenants are deliberate isolation fixtures.
INSERT INTO products
  (id, tenant_id, sku, name, unit_price, currency, source_system, external_product_id, created_by, updated_by, created_at, updated_at)
VALUES
  (1101, 1001, 'MUG-001', 'MOCK Ceramic Mug', 120000, 'VND', 'MOCK', 'mock-p-1101', 1001, 1001, '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (1102, 1001, 'BOOK-001', 'MOCK Notebook', 80000, 'VND', 'MOCK', 'mock-p-1102', 1001, 1001, '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (1103, 1001, 'BOTTLE-001', 'MOCK Water Bottle', 200000, 'VND', 'MOCK', 'mock-p-1103', 1001, 1001, '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (1104, 1001, 'POUCH-001', 'MOCK Pouch', 50000, 'VND', 'MOCK', 'mock-p-1104', 1001, 1001, '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (2101, 1002, 'MUG-001', 'MOCK Isolation Mug', 150000, 'VND', 'MOCK', 'mock-p-2101', 2001, 2001, '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (2102, 1002, 'BOOK-001', 'MOCK Isolation Notebook', 90000, 'VND', 'MOCK', 'mock-p-2102', 2001, 2001, '2026-09-01 00:00:00', '2026-09-01 00:00:00');

INSERT INTO warehouses
  (id, tenant_id, code, name, source_system, created_by, updated_by, created_at, updated_at)
VALUES
  (1201, 1001, 'MAIN', 'MOCK Main Warehouse', 'MOCK', 1001, 1001, '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (1202, 1001, 'AUX', 'MOCK Auxiliary Warehouse', 'MOCK', 1001, 1001, '2026-09-01 00:00:00', '2026-09-01 00:00:00'),
  (2201, 1002, 'MAIN', 'MOCK Isolation Warehouse', 'MOCK', 2001, 2001, '2026-09-01 00:00:00', '2026-09-01 00:00:00');

INSERT INTO actor_warehouse_scopes
  (tenant_id, actor_id, warehouse_id, can_read, can_write, can_approve, granted_by, created_at)
VALUES
  (1001, 1001, 1201, 1, 1, 0, 1003, '2026-09-01 00:00:00'),
  (1001, 1001, 1202, 1, 1, 0, 1003, '2026-09-01 00:00:00'),
  (1001, 1002, 1201, 1, 1, 0, 1003, '2026-09-01 00:00:00'),
  (1001, 1002, 1202, 1, 0, 0, 1003, '2026-09-01 00:00:00'),
  (1001, 1003, 1201, 1, 0, 1, 1003, '2026-09-01 00:00:00'),
  (1001, 1003, 1202, 1, 0, 1, 1003, '2026-09-01 00:00:00'),
  (1002, 2001, 2201, 1, 1, 0, 2003, '2026-09-01 00:00:00'),
  (1002, 2002, 2201, 1, 1, 0, 2003, '2026-09-01 00:00:00'),
  (1002, 2003, 2201, 1, 0, 1, 2003, '2026-09-01 00:00:00');

INSERT INTO workflow_runs
  (id, tenant_id, requested_by, workflow_type, status, current_step, state_json, result_json, started_at, finished_at, created_at, updated_at)
VALUES
  ('00001001-0000-4000-8000-000000000001', 1001, 1001, 'MOCK_OPENING_IMPORT', 'COMPLETED', 'completed',
   JSON_OBJECT('source', 'MOCK', 'fixture', '001_demo'), JSON_OBJECT('inventory_rows', 5, 'ledger_rows', 5),
   '2026-10-02 00:00:00', '2026-10-02 00:00:01', '2026-10-02 00:00:00', '2026-10-02 00:00:01'),
  ('00001002-0000-4000-8000-000000000001', 1002, 2001, 'MOCK_OPENING_IMPORT', 'COMPLETED', 'completed',
   JSON_OBJECT('source', 'MOCK', 'fixture', '001_demo'), JSON_OBJECT('inventory_rows', 2, 'ledger_rows', 2),
   '2026-10-02 00:00:00', '2026-10-02 00:00:01', '2026-10-02 00:00:00', '2026-10-02 00:00:01'),
  ('00001001-0000-4000-8000-000000000002', 1001, 1002, 'INVENTORY_ADJUSTMENT', 'WAITING_FOR_APPROVAL', 'approval',
   JSON_OBJECT('source', 'MOCK', 'approval_id', 1701, 'inventory_id', 1302), NULL,
   '2026-10-02 01:00:00', NULL, '2026-10-02 01:00:00', '2026-10-02 01:00:00');

INSERT INTO workflow_checkpoints
  (id, tenant_id, workflow_id, checkpoint_sequence, schema_version, checkpoint_json, created_at)
VALUES
  (1501, 1001, '00001001-0000-4000-8000-000000000001', 1, 1, JSON_OBJECT('source', 'MOCK', 'status', 'COMPLETED'), '2026-10-02 00:00:01'),
  (2501, 1002, '00001002-0000-4000-8000-000000000001', 1, 1, JSON_OBJECT('source', 'MOCK', 'status', 'COMPLETED'), '2026-10-02 00:00:01'),
  (1502, 1001, '00001001-0000-4000-8000-000000000002', 1, 1, JSON_OBJECT('source', 'MOCK', 'status', 'WAITING_FOR_APPROVAL', 'approval_id', 1701), '2026-10-02 01:00:00');

-- Pending fixture only; no stock change has been made for this proposal.
-- Fixed expiry keeps the dataset deterministic and is future-dated as of creation.
INSERT INTO approval_requests
  (id, tenant_id, workflow_id, requested_by, action_key, action_name, payload, payload_hash,
   resource_versions, risk_level, policy_version, risk_version, status, expires_at, created_at, updated_at)
VALUES
  (1701, 1001, '00001001-0000-4000-8000-000000000002', 1002, 'mock-adjust-1302', 'adjust_inventory',
   @demo_approval, UNHEX(SHA2(@demo_approval, 256)), JSON_OBJECT('inventory:1302', 1),
   'HIGH', 'MOCK-policy-v1', 'MOCK-risk-v1', 'PENDING', '2030-01-01 00:00:00', '2026-10-02 01:00:00', '2026-10-02 01:00:00');

INSERT INTO idempotency_keys
  (id, tenant_id, actor_id, workflow_id, operation_name, idempotency_key, payload_hash,
   status, response_snapshot, completed_at, created_at, updated_at)
VALUES
  (1601, 1001, 1001, '00001001-0000-4000-8000-000000000001', 'mock_opening_balance', 'mock-opening-1001-v1',
   UNHEX(SHA2(@demo_open_1, 256)), 'COMPLETED', JSON_OBJECT('source', 'MOCK', 'inventory_rows', 5, 'movement_ids', JSON_ARRAY(1901,1902,1903,1904,1905)),
   '2026-10-02 00:00:01', '2026-10-02 00:00:00', '2026-10-02 00:00:01'),
  (2601, 1002, 2001, '00001002-0000-4000-8000-000000000001', 'mock_opening_balance', 'mock-opening-1002-v1',
   UNHEX(SHA2(@demo_open_2, 256)), 'COMPLETED', JSON_OBJECT('source', 'MOCK', 'inventory_rows', 2, 'movement_ids', JSON_ARRAY(2901,2902)),
   '2026-10-02 00:00:01', '2026-10-02 00:00:00', '2026-10-02 00:00:01');

-- Hash-chain fields intentionally remain NULL. These are unchained audit records;
-- payload_hash fingerprints only the fixture bytes, not a tamper-evident chain.
INSERT INTO audit_events
  (id, tenant_id, workflow_id, actor_id, idempotency_id, event_type, tool_name, tool_version,
   outcome, risk_level, policy_version, risk_version, payload_hash, redacted_input, redacted_output, occurred_at)
VALUES
  (1801, 1001, '00001001-0000-4000-8000-000000000001', 1001, 1601, 'MOCK_OPENING_IMPORTED', 'mock_seed', '1',
   'SUCCESS', 'LOW', 'MOCK-policy-v1', 'MOCK-risk-v1', UNHEX(SHA2(@demo_open_1, 256)), @demo_open_1,
   JSON_OBJECT('source', 'MOCK', 'inventory_rows', 5, 'ledger_rows', 5), '2026-10-02 00:00:01'),
  (2801, 1002, '00001002-0000-4000-8000-000000000001', 2001, 2601, 'MOCK_OPENING_IMPORTED', 'mock_seed', '1',
   'SUCCESS', 'LOW', 'MOCK-policy-v1', 'MOCK-risk-v1', UNHEX(SHA2(@demo_open_2, 256)), @demo_open_2,
   JSON_OBJECT('source', 'MOCK', 'inventory_rows', 2, 'ledger_rows', 2), '2026-10-02 00:00:01');

INSERT INTO inventory
  (id, tenant_id, warehouse_id, product_id, quantity_on_hand, quantity_reserved, reorder_point,
   version, source_system, last_synced_at, created_by, updated_by, created_at, updated_at)
VALUES
  (1301, 1001, 1201, 1101, 40, 4, 10, 1, 'MOCK', '2026-10-02 00:00:01', 1001, 1001, '2026-10-02 00:00:01', '2026-10-02 00:00:01'),
  (1302, 1001, 1201, 1102, 8, 2, 10, 1, 'MOCK', '2026-10-02 00:00:01', 1001, 1001, '2026-10-02 00:00:01', '2026-10-02 00:00:01'),
  (1303, 1001, 1201, 1103, 15, 0, 5, 1, 'MOCK', '2026-10-02 00:00:01', 1001, 1001, '2026-10-02 00:00:01', '2026-10-02 00:00:01'),
  (1304, 1001, 1202, 1101, 5, 1, 5, 1, 'MOCK', '2026-10-02 00:00:01', 1001, 1001, '2026-10-02 00:00:01', '2026-10-02 00:00:01'),
  (1305, 1001, 1202, 1104, 30, 0, 10, 1, 'MOCK', '2026-10-02 00:00:01', 1001, 1001, '2026-10-02 00:00:01', '2026-10-02 00:00:01'),
  (2301, 1002, 2201, 2101, 70, 3, 10, 1, 'MOCK', '2026-10-02 00:00:01', 2001, 2001, '2026-10-02 00:00:01', '2026-10-02 00:00:01'),
  (2302, 1002, 2201, 2102, 4, 0, 5, 1, 'MOCK', '2026-10-02 00:00:01', 2001, 2001, '2026-10-02 00:00:01', '2026-10-02 00:00:01');

INSERT INTO inventory_movements
  (id, tenant_id, inventory_id, workflow_id, actor_id, idempotency_id, audit_event_id, action_line,
   quantity_delta, reserved_delta, balance_before, balance_after, reserved_before, reserved_after,
   inventory_version_after, reason_code, reference_type, reference_id, created_at)
VALUES
  (1901, 1001, 1301, '00001001-0000-4000-8000-000000000001', 1001, 1601, 1801, 1, 40, 4, 0, 40, 0, 4, 1, 'OPENING_BALANCE', 'MOCK', '001_demo:1301', '2026-10-02 00:00:01'),
  (1902, 1001, 1302, '00001001-0000-4000-8000-000000000001', 1001, 1601, 1801, 2, 8, 2, 0, 8, 0, 2, 1, 'OPENING_BALANCE', 'MOCK', '001_demo:1302', '2026-10-02 00:00:01'),
  (1903, 1001, 1303, '00001001-0000-4000-8000-000000000001', 1001, 1601, 1801, 3, 15, 0, 0, 15, 0, 0, 1, 'OPENING_BALANCE', 'MOCK', '001_demo:1303', '2026-10-02 00:00:01'),
  (1904, 1001, 1304, '00001001-0000-4000-8000-000000000001', 1001, 1601, 1801, 4, 5, 1, 0, 5, 0, 1, 1, 'OPENING_BALANCE', 'MOCK', '001_demo:1304', '2026-10-02 00:00:01'),
  (1905, 1001, 1305, '00001001-0000-4000-8000-000000000001', 1001, 1601, 1801, 5, 30, 0, 0, 30, 0, 0, 1, 'OPENING_BALANCE', 'MOCK', '001_demo:1305', '2026-10-02 00:00:01'),
  (2901, 1002, 2301, '00001002-0000-4000-8000-000000000001', 2001, 2601, 2801, 1, 70, 3, 0, 70, 0, 3, 1, 'OPENING_BALANCE', 'MOCK', '001_demo:2301', '2026-10-02 00:00:01'),
  (2902, 1002, 2302, '00001002-0000-4000-8000-000000000001', 2001, 2601, 2801, 2, 4, 0, 0, 4, 0, 0, 1, 'OPENING_BALANCE', 'MOCK', '001_demo:2302', '2026-10-02 00:00:01');

-- Historical MOCK sales and the opening stock above are independent imported
-- snapshots. These orders do not assert shipment/reservation ledger integration.
-- Header subtotal/discount/tax equal the sums of their item amounts; shipping is
-- an order-level amount. All timestamps are UTC.
INSERT INTO orders
  (id, tenant_id, order_number, customer_ref, source_system, external_order_id, status, payment_status,
   currency, subtotal_amount, discount_amount, tax_amount, shipping_amount, refunded_amount,
   placed_at, paid_at, created_by, updated_by, created_at, updated_at)
VALUES
  (1401, 1001, 'MOCK-1001', 'mock-customer-A', 'MOCK', 'mock-o-1401', 'COMPLETED', 'PAID', 'VND', 320000, 20000, 0, 30000, 0,
   '2026-09-30 01:50:00', '2026-09-30 02:00:00', 1001, 1001, '2026-09-30 01:50:00', '2026-09-30 02:00:00'),
  (1402, 1001, 'MOCK-1002', 'mock-customer-B', 'MOCK', 'mock-o-1402', 'FULFILLED', 'PAID', 'VND', 200000, 0, 20000, 0, 0,
   '2026-09-30 04:50:00', '2026-09-30 05:00:00', 1001, 1001, '2026-09-30 04:50:00', '2026-09-30 05:00:00'),
  (1403, 1001, 'MOCK-1003', 'mock-customer-A', 'MOCK', 'mock-o-1403', 'COMPLETED', 'PARTIALLY_REFUNDED', 'VND', 240000, 0, 0, 10000, 50000,
   '2026-10-01 02:50:00', '2026-10-01 03:00:00', 1001, 1001, '2026-10-01 02:50:00', '2026-10-01 06:00:00'),
  (1404, 1001, 'MOCK-1004', 'mock-customer-C', 'MOCK', 'mock-o-1404', 'PLACED', 'UNPAID', 'VND', 120000, 0, 0, 20000, 0,
   '2026-10-01 03:30:00', NULL, 1001, 1001, '2026-10-01 03:30:00', '2026-10-01 03:30:00'),
  (1405, 1001, 'MOCK-1005', 'mock-customer-D', 'MOCK', 'mock-o-1405', 'CANCELLED', 'PAID', 'VND', 100000, 0, 0, 0, 0,
   '2026-10-01 03:50:00', '2026-10-01 04:00:00', 1001, 1001, '2026-10-01 03:50:00', '2026-10-01 04:30:00'),
  (1406, 1001, 'MOCK-1006', 'mock-customer-E', 'MOCK', 'mock-o-1406', 'COMPLETED', 'REFUNDED', 'VND', 100000, 0, 0, 0, 100000,
   '2026-10-01 04:50:00', '2026-10-01 05:00:00', 1001, 1001, '2026-10-01 04:50:00', '2026-10-01 07:00:00'),
  (2401, 1002, 'MOCK-1001', 'mock-customer-A', 'MOCK', 'mock-o-2401', 'COMPLETED', 'PAID', 'VND', 150000, 0, 0, 20000, 0,
   '2026-09-30 01:50:00', '2026-09-30 02:00:00', 2001, 2001, '2026-09-30 01:50:00', '2026-09-30 02:00:00'),
  (2402, 1002, 'MOCK-1002', 'mock-customer-B', 'MOCK', 'mock-o-2402', 'COMPLETED', 'PAID', 'VND', 180000, 0, 0, 0, 0,
   '2026-10-01 02:50:00', '2026-10-01 03:00:00', 2001, 2001, '2026-10-01 02:50:00', '2026-10-01 03:00:00');

INSERT INTO order_items
  (id, tenant_id, order_id, product_id, line_number, sku_snapshot, name_snapshot, quantity, unit_price, discount_amount, tax_amount, created_at)
VALUES
  (1451, 1001, 1401, 1101, 1, 'MUG-001', 'MOCK Ceramic Mug', 2, 120000, 20000, 0, '2026-09-30 01:50:00'),
  (1452, 1001, 1401, 1102, 2, 'BOOK-001', 'MOCK Notebook', 1, 80000, 0, 0, '2026-09-30 01:50:00'),
  (1453, 1001, 1402, 1103, 1, 'BOTTLE-001', 'MOCK Water Bottle', 1, 200000, 0, 20000, '2026-09-30 04:50:00'),
  (1454, 1001, 1403, 1102, 1, 'BOOK-001', 'MOCK Notebook', 3, 80000, 0, 0, '2026-10-01 02:50:00'),
  (1455, 1001, 1404, 1101, 1, 'MUG-001', 'MOCK Ceramic Mug', 1, 120000, 0, 0, '2026-10-01 03:30:00'),
  (1456, 1001, 1405, 1104, 1, 'POUCH-001', 'MOCK Pouch', 2, 50000, 0, 0, '2026-10-01 03:50:00'),
  (1457, 1001, 1406, 1104, 1, 'POUCH-001', 'MOCK Pouch', 2, 50000, 0, 0, '2026-10-01 04:50:00'),
  (2451, 1002, 2401, 2101, 1, 'MUG-001', 'MOCK Isolation Mug', 1, 150000, 0, 0, '2026-09-30 01:50:00'),
  (2452, 1002, 2402, 2102, 1, 'BOOK-001', 'MOCK Isolation Notebook', 2, 90000, 0, 0, '2026-10-01 02:50:00');

COMMIT;

-- Fixture expectations for tenant 1001 and [2026-09-30, 2026-10-02) UTC:
-- 4 eligible paid/refunded orders; net_revenue = 750000 VND; AOV = 187500 VND.
-- 2026-09-30: 2 orders, 550000 net, 275000 AOV.
-- 2026-10-01: 2 orders, 200000 net, 100000 AOV.
-- Inventory: 5 rows, on_hand 98, reserved 7, available 91, 2 low-stock rows.
-- Tenant 1002: 2 eligible orders, net 350000 VND, AOV 175000 VND;
-- inventory on_hand 74, reserved 3, available 71, 1 low-stock row.
-- Global: 2 audit events intentionally UNCHAINED; no verified chain exists.
