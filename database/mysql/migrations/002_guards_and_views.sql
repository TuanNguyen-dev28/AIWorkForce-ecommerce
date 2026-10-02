-- Migration 002. Run after 001, before importing demo data.
-- Guards supplement backend authorization; a DBA can still alter/drop triggers.
USE aiworkforce_ecommerce;
SET NAMES utf8mb4;
SET SESSION time_zone = '+00:00';

DELIMITER $$
CREATE TRIGGER audit_events_no_update BEFORE UPDATE ON audit_events
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'audit_events is append-only';
END$$

CREATE TRIGGER audit_events_no_delete BEFORE DELETE ON audit_events
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'audit_events is append-only';
END$$

CREATE TRIGGER inventory_movements_no_update BEFORE UPDATE ON inventory_movements
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'inventory_movements is append-only';
END$$

CREATE TRIGGER inventory_movements_no_delete BEFORE DELETE ON inventory_movements
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'inventory_movements is append-only';
END$$

CREATE TRIGGER approval_requests_guard BEFORE UPDATE ON approval_requests
FOR EACH ROW
BEGIN
  IF NOT (OLD.tenant_id <=> NEW.tenant_id)
     OR NOT (OLD.id <=> NEW.id)
     OR NOT (OLD.workflow_id <=> NEW.workflow_id)
     OR NOT (OLD.requested_by <=> NEW.requested_by)
     OR NOT (OLD.action_key <=> NEW.action_key)
     OR NOT (OLD.action_name <=> NEW.action_name)
     OR NOT (OLD.payload_hash <=> NEW.payload_hash)
     OR NOT (CAST(OLD.payload AS BINARY) <=> CAST(NEW.payload AS BINARY))
     OR NOT (CAST(OLD.resource_versions AS BINARY) <=> CAST(NEW.resource_versions AS BINARY))
     OR NOT (OLD.risk_level <=> NEW.risk_level)
     OR NOT (OLD.policy_version <=> NEW.policy_version)
     OR NOT (OLD.risk_version <=> NEW.risk_version)
     OR NOT (OLD.expires_at <=> NEW.expires_at)
     OR NOT (OLD.created_at <=> NEW.created_at) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Approval payload and binding are immutable; create a new approval';
  END IF;
  IF OLD.status <> 'PENDING' AND (
       NOT (OLD.decided_by <=> NEW.decided_by)
       OR NOT (OLD.decided_at <=> NEW.decided_at)
       OR NOT (OLD.decision_reason <=> NEW.decision_reason)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Approval decision is immutable';
  END IF;
  IF OLD.status <> NEW.status AND NOT (
       (OLD.status = 'PENDING' AND NEW.status IN ('APPROVED','REJECTED','EXPIRED','CANCELLED'))
       OR (OLD.status = 'APPROVED' AND NEW.status IN ('EXECUTED','EXPIRED','CANCELLED'))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid approval status transition';
  END IF;
END$$

CREATE TRIGGER idempotency_keys_guard BEFORE UPDATE ON idempotency_keys
FOR EACH ROW
BEGIN
  IF OLD.status IN ('COMPLETED','FAILED') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Terminal idempotency result is immutable';
  END IF;
  IF NOT (OLD.tenant_id <=> NEW.tenant_id)
     OR NOT (OLD.id <=> NEW.id)
     OR NOT (OLD.actor_id <=> NEW.actor_id)
     OR NOT (OLD.workflow_id <=> NEW.workflow_id)
     OR NOT (OLD.approval_id <=> NEW.approval_id)
     OR NOT (OLD.operation_name <=> NEW.operation_name)
     OR NOT (OLD.idempotency_key <=> NEW.idempotency_key)
     OR NOT (OLD.payload_hash <=> NEW.payload_hash)
     OR NOT (OLD.created_at <=> NEW.created_at) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Idempotency identity and payload hash are immutable';
  END IF;
END$$

CREATE TRIGGER idempotency_keys_no_unresolved_delete BEFORE DELETE ON idempotency_keys
FOR EACH ROW
BEGIN
  IF OLD.status IN ('IN_PROGRESS','NEEDS_REVIEW') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot delete unresolved idempotency record';
  END IF;
END$$
DELIMITER ;

-- These views intentionally include tenant_id and use invoker privileges.
-- They are convenience reports, NOT database row-level access control.
CREATE SQL SECURITY INVOKER VIEW v_inventory_availability AS
SELECT i.tenant_id, i.id AS inventory_id, i.warehouse_id, w.code AS warehouse_code,
       i.product_id, p.sku, p.name AS product_name,
       i.quantity_on_hand, i.quantity_reserved, i.quantity_available,
       i.reorder_point, (i.quantity_available <= i.reorder_point) AS is_low_stock,
       i.version
FROM inventory AS i
JOIN warehouses AS w ON w.tenant_id = i.tenant_id AND w.id = i.warehouse_id
JOIN products AS p ON p.tenant_id = i.tenant_id AND p.id = i.product_id;

-- Development metric: paid gross order total (including tax/shipping) minus
-- recorded refunds, attributed to original paid date in UTC. No FX conversion.
CREATE SQL SECURITY INVOKER VIEW v_daily_sales AS
SELECT tenant_id, DATE(paid_at) AS sales_date, currency,
       COUNT(*) AS paid_order_count,
       SUM(total_amount - refunded_amount) AS net_revenue,
       CAST(AVG(total_amount - refunded_amount) AS DECIMAL(18,2)) AS aov
FROM orders
WHERE payment_status IN ('PAID','PARTIALLY_REFUNDED','REFUNDED')
  AND status <> 'CANCELLED'
GROUP BY tenant_id, DATE(paid_at), currency;

CREATE SQL SECURITY INVOKER VIEW v_order_total_mismatches AS
SELECT o.tenant_id, o.id AS order_id, o.order_number,
       o.subtotal_amount AS declared_subtotal, COALESCE(item_totals.actual_subtotal, 0) AS actual_subtotal,
       o.discount_amount AS declared_discount, COALESCE(item_totals.actual_discount, 0) AS actual_discount,
       o.tax_amount AS declared_tax, COALESCE(item_totals.actual_tax, 0) AS actual_tax
FROM orders AS o
LEFT JOIN (
  SELECT tenant_id, order_id, SUM(line_subtotal) AS actual_subtotal,
         SUM(discount_amount) AS actual_discount, SUM(tax_amount) AS actual_tax
  FROM order_items GROUP BY tenant_id, order_id
) AS item_totals ON item_totals.tenant_id = o.tenant_id AND item_totals.order_id = o.id
WHERE o.subtotal_amount <> COALESCE(item_totals.actual_subtotal, 0)
   OR o.discount_amount <> COALESCE(item_totals.actual_discount, 0)
   OR o.tax_amount <> COALESCE(item_totals.actual_tax, 0);

INSERT INTO schema_migrations (version, description)
VALUES ('002', 'Append-only, approval/idempotency guards and scoped reporting views');
