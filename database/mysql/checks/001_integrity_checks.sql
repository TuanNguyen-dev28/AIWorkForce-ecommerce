-- Read-only integrity diagnostics for a database administrator.
-- These deliberately inspect all tenants. Do not expose them as Agent tools.
-- A zero discrepancy count is evidence for this snapshot, not a substitute for
-- transactional backend enforcement, authorization or concurrency tests.
USE aiworkforce_ecommerce;
SET SESSION time_zone = '+00:00';

SELECT version, description, applied_at
FROM schema_migrations
ORDER BY version;

-- Initial schema has 16 base tables, including schema_migrations.
SELECT COUNT(*) AS base_table_count
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE';

SELECT 'tenants' AS entity, COUNT(*) AS row_count FROM tenants
UNION ALL SELECT 'actors', COUNT(*) FROM actors
UNION ALL SELECT 'actor_roles', COUNT(*) FROM actor_roles
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'warehouses', COUNT(*) FROM warehouses
UNION ALL SELECT 'actor_warehouse_scopes', COUNT(*) FROM actor_warehouse_scopes
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'workflow_runs', COUNT(*) FROM workflow_runs
UNION ALL SELECT 'workflow_checkpoints', COUNT(*) FROM workflow_checkpoints
UNION ALL SELECT 'approval_requests', COUNT(*) FROM approval_requests
UNION ALL SELECT 'idempotency_keys', COUNT(*) FROM idempotency_keys
UNION ALL SELECT 'audit_events', COUNT(*) FROM audit_events
UNION ALL SELECT 'inventory_movements', COUNT(*) FROM inventory_movements;

-- Inspect actual FK column pairs in ordinal order, including workflow/actor
-- binding in write-control records. All tenant-owned parent references must
-- include tenant_id on BOTH sides of the FK.
SELECT table_name, constraint_name, referenced_table_name,
       GROUP_CONCAT(column_name ORDER BY ordinal_position) AS child_columns,
       GROUP_CONCAT(referenced_column_name ORDER BY ordinal_position) AS parent_columns
FROM information_schema.key_column_usage
WHERE constraint_schema = DATABASE() AND referenced_table_name IS NOT NULL
GROUP BY table_name, constraint_name, referenced_table_name
ORDER BY table_name, constraint_name;

SELECT COUNT(*) AS foreign_keys_missing_tenant_pair
FROM (
  SELECT table_name, constraint_name
  FROM information_schema.key_column_usage
  WHERE constraint_schema = DATABASE()
    AND referenced_table_name IS NOT NULL
    AND referenced_table_name <> 'tenants'
  GROUP BY table_name, constraint_name
  HAVING SUM(column_name = 'tenant_id' AND referenced_column_name = 'tenant_id') = 0
) AS invalid_fk;

-- Core orphan checks also match tenant_id; expected discrepancy counts are zero.
SELECT 'inventory_missing_product_or_warehouse' AS check_name, COUNT(*) AS discrepancy_count
FROM inventory AS i
LEFT JOIN products AS p ON p.tenant_id = i.tenant_id AND p.id = i.product_id
LEFT JOIN warehouses AS w ON w.tenant_id = i.tenant_id AND w.id = i.warehouse_id
WHERE p.id IS NULL OR w.id IS NULL
UNION ALL
SELECT 'items_missing_order_or_product', COUNT(*)
FROM order_items AS oi
LEFT JOIN orders AS o ON o.tenant_id = oi.tenant_id AND o.id = oi.order_id
LEFT JOIN products AS p ON p.tenant_id = oi.tenant_id AND p.id = oi.product_id
WHERE o.id IS NULL OR p.id IS NULL
UNION ALL
SELECT 'movements_missing_bound_control_record', COUNT(*)
FROM inventory_movements AS m
LEFT JOIN inventory AS i ON i.tenant_id = m.tenant_id AND i.id = m.inventory_id
LEFT JOIN idempotency_keys AS k
  ON k.tenant_id = m.tenant_id AND k.id = m.idempotency_id
 AND k.workflow_id = m.workflow_id AND k.actor_id = m.actor_id
LEFT JOIN audit_events AS a
  ON a.tenant_id = m.tenant_id AND a.id = m.audit_event_id
 AND a.workflow_id = m.workflow_id AND a.actor_id = m.actor_id
 AND a.idempotency_id = m.idempotency_id
WHERE i.id IS NULL OR k.id IS NULL OR a.id IS NULL;

SELECT COUNT(*) AS order_total_mismatch_count
FROM v_order_total_mismatches;
SELECT * FROM v_order_total_mismatches ORDER BY tenant_id, order_id;

-- Currency consistency is an import/application responsibility in addition to
-- monetary checks. This schema has one currency per order; product currency is
-- current catalog currency, so investigate any mismatch before accepting imports.
SELECT COUNT(*) AS item_product_currency_mismatch_count
FROM order_items AS oi
JOIN orders AS o ON o.tenant_id = oi.tenant_id AND o.id = oi.order_id
JOIN products AS p ON p.tenant_id = oi.tenant_id AND p.id = oi.product_id
WHERE p.currency <> o.currency;

-- Ledger must start at zero and account for both on-hand and reserved balances.
-- This aggregate check additionally catches version gaps and absent movements.
SELECT i.tenant_id, i.id AS inventory_id, i.quantity_on_hand, i.quantity_reserved, i.version,
       COALESCE(SUM(m.quantity_delta), 0) AS ledger_on_hand,
       COALESCE(SUM(m.reserved_delta), 0) AS ledger_reserved,
       COALESCE(MAX(m.inventory_version_after), 0) AS ledger_version,
       COUNT(m.id) AS movement_count
FROM inventory AS i
LEFT JOIN inventory_movements AS m ON m.tenant_id = i.tenant_id AND m.inventory_id = i.id
GROUP BY i.tenant_id, i.id, i.quantity_on_hand, i.quantity_reserved, i.version
HAVING i.quantity_on_hand <> ledger_on_hand
    OR i.quantity_reserved <> ledger_reserved
    OR i.version <> ledger_version
    OR i.version <> movement_count
ORDER BY i.tenant_id, i.id;

-- No rows expected: each movement's before/after balance must connect to its
-- preceding version, with zero opening before-balances at version 1.
WITH movement_sequence AS (
  SELECT tenant_id, inventory_id, id, inventory_version_after, balance_before, reserved_before,
         LAG(inventory_version_after) OVER (PARTITION BY tenant_id, inventory_id ORDER BY inventory_version_after) AS prior_version,
         LAG(balance_after) OVER (PARTITION BY tenant_id, inventory_id ORDER BY inventory_version_after) AS prior_balance,
         LAG(reserved_after) OVER (PARTITION BY tenant_id, inventory_id ORDER BY inventory_version_after) AS prior_reserved
  FROM inventory_movements
)
SELECT * FROM movement_sequence
WHERE (prior_version IS NULL AND (inventory_version_after <> 1 OR balance_before <> 0 OR reserved_before <> 0))
   OR (prior_version IS NOT NULL AND (inventory_version_after <> prior_version + 1
       OR balance_before <> prior_balance OR reserved_before <> prior_reserved))
ORDER BY tenant_id, inventory_id, inventory_version_after;

-- Counts are zero for the demo. For live recovery, investigate discrepancies;
-- do not update audit/ledger rows to make a report appear clean.
SELECT COUNT(*) AS movement_controls_not_successfully_completed
FROM inventory_movements AS m
JOIN idempotency_keys AS k ON k.tenant_id = m.tenant_id AND k.id = m.idempotency_id
JOIN audit_events AS a ON a.tenant_id = m.tenant_id AND a.id = m.audit_event_id
WHERE k.status <> 'COMPLETED' OR a.outcome <> 'SUCCESS' OR k.payload_hash <> a.payload_hash;

SELECT COUNT(*) AS expired_pending_approval_count
FROM approval_requests
WHERE status = 'PENDING' AND expires_at <= UTC_TIMESTAMP(6);

-- This is an honest coverage report, NOT a chain verification result.
-- Demo expected: 2 total, 2 unchained, 0 with hashes. Hash-chain writing and
-- independent verification must be implemented before claiming tamper evidence.
SELECT COUNT(*) AS total_audit_events,
       COALESCE(SUM(record_hash IS NULL), 0) AS unchained_audit_events,
       COALESCE(SUM(record_hash IS NOT NULL), 0) AS events_with_chain_hash
FROM audit_events;
