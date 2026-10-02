-- Read-only application query examples. SET changes this session only.
-- A trusted backend must bind tenant/actor/warehouse scope after authorization.
-- MySQL views do NOT provide per-tenant row-level access control automatically.
USE aiworkforce_ecommerce;
SET SESSION time_zone = '+00:00';
SET @tenant_id = 1001;
SET @from_utc = '2026-09-30 00:00:00';
SET @to_utc = '2026-10-02 00:00:00';

-- Revenue contract: eligible payment_status IN (PAID, PARTIALLY_REFUNDED,
-- REFUNDED), status <> CANCELLED; group by currency, use paid_at in [from,to).
-- net_revenue = SUM(total_amount - refunded_amount).
-- total_amount includes tax and shipping and subtracts discount.
-- AOV = net_revenue / eligible order count, including fully refunded orders.
-- This reports the CURRENT refunded amount against the ORIGINAL payment date.
-- It is not a historical cashflow/refund-event report; that needs payment events.
-- Demo expected: VND, 4, 750000.00, 187500.00.
SELECT o.currency,
       COUNT(*) AS paid_order_count,
       SUM(o.total_amount - o.refunded_amount) AS net_revenue,
       ROUND(SUM(o.total_amount - o.refunded_amount) / NULLIF(COUNT(*), 0), 2) AS aov
FROM orders AS o
WHERE o.tenant_id = @tenant_id
  AND o.payment_status IN ('PAID', 'PARTIALLY_REFUNDED', 'REFUNDED')
  AND o.status <> 'CANCELLED'
  AND o.paid_at >= @from_utc
  AND o.paid_at < @to_utc
GROUP BY o.currency
ORDER BY o.currency;

-- Daily UTC buckets: use the raw timestamp predicate so a partial-day requested
-- range is handled correctly. The daily view is useful for whole UTC day ranges.
SELECT DATE(o.paid_at) AS sales_date, o.currency,
       COUNT(*) AS paid_order_count,
       SUM(o.total_amount - o.refunded_amount) AS net_revenue,
       ROUND(SUM(o.total_amount - o.refunded_amount) / NULLIF(COUNT(*), 0), 2) AS aov
FROM orders AS o
WHERE o.tenant_id = @tenant_id
  AND o.payment_status IN ('PAID', 'PARTIALLY_REFUNDED', 'REFUNDED')
  AND o.status <> 'CANCELLED'
  AND o.paid_at >= @from_utc
  AND o.paid_at < @to_utc
GROUP BY DATE(o.paid_at), o.currency
ORDER BY sales_date, o.currency;

-- Whole UTC calendar days ONLY for this view example. Use the prior query if
-- either endpoint is not midnight UTC. Do not sum currencies together.
SELECT sales_date, currency, paid_order_count, net_revenue, aov
FROM v_daily_sales
WHERE tenant_id = @tenant_id
  AND sales_date >= DATE(@from_utc)
  AND sales_date < DATE(@to_utc)
ORDER BY sales_date, currency;

-- Stock availability; production callers also apply authorized warehouse scope.
SELECT inventory_id, warehouse_code, sku, product_name,
       quantity_on_hand, quantity_reserved, quantity_available, reorder_point,
       is_low_stock, version
FROM v_inventory_availability
WHERE tenant_id = @tenant_id
ORDER BY warehouse_code, sku;

-- Demo tenant 1001: MAIN/BOOK-001 available 6; AUX/MUG-001 available 4.
SELECT inventory_id, warehouse_code, sku, quantity_available, reorder_point
FROM v_inventory_availability
WHERE tenant_id = @tenant_id
  AND is_low_stock = 1
ORDER BY warehouse_code, sku;

-- Pending approvals are only proposals. The backend must enforce actor role,
-- warehouse scope, requester/approver separation, expiry and resource versions.
SELECT ar.id, ar.workflow_id, ar.action_name, ar.risk_level, ar.status,
       ar.resource_versions, ar.expires_at
FROM approval_requests AS ar
WHERE ar.tenant_id = @tenant_id
  AND ar.status = 'PENDING'
  AND ar.expires_at > UTC_TIMESTAMP(6)
ORDER BY ar.expires_at, ar.id;

-- Audit drilldown is tenant-scoped even though workflow IDs are globally unique.
SET @workflow_id = '00001001-0000-4000-8000-000000000001';
SELECT ae.id, ae.actor_id, ae.event_type, ae.outcome, ae.idempotency_id,
       HEX(ae.payload_hash) AS payload_hash_hex,
       ae.chain_sequence, ae.record_hash IS NOT NULL AS has_chain_hash,
       ae.occurred_at
FROM audit_events AS ae
WHERE ae.tenant_id = @tenant_id
  AND ae.workflow_id = @workflow_id
ORDER BY ae.occurred_at, ae.id;

-- Header/item reconciliation: no rows expected in the untouched demo fixture.
SELECT *
FROM v_order_total_mismatches
WHERE tenant_id = @tenant_id
ORDER BY order_id;
