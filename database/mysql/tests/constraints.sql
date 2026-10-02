-- Database constraint/guard checks for migrations 001 and 002, MySQL 8.0.16+.
-- Run in a dedicated connection, with no transaction containing user work.
-- STOP ON THE FIRST SCRIPT ERROR (do not use mysql --force).
-- No demo seed is required. All business fixtures are rolled back.
-- AUTO_INCREMENT counters may advance even though fixture rows are rolled back.
-- No preexisting table, routine or data is dropped: CREATE fails on a name collision.
-- On failure the procedure remains available for inspection; remove only this test
-- routine deliberately before retrying. On success the final DROP removes it.
USE aiworkforce_ecommerce;
SET NAMES utf8mb4;
SET SESSION time_zone = '+00:00';

DELIMITER $$
CREATE PROCEDURE awf_test_constraints_v1()
SQL SECURITY INVOKER
BEGIN
  DECLARE v_run CHAR(32);
  DECLARE v_tenant_a BIGINT UNSIGNED;
  DECLARE v_tenant_b BIGINT UNSIGNED;
  DECLARE v_actor_a BIGINT UNSIGNED;
  DECLARE v_actor_a2 BIGINT UNSIGNED;
  DECLARE v_actor_b BIGINT UNSIGNED;
  DECLARE v_product_a BIGINT UNSIGNED;
  DECLARE v_product_b BIGINT UNSIGNED;
  DECLARE v_warehouse_a BIGINT UNSIGNED;
  DECLARE v_warehouse_b BIGINT UNSIGNED;
  DECLARE v_inventory_a BIGINT UNSIGNED;
  DECLARE v_order_a BIGINT UNSIGNED;
  DECLARE v_order_b BIGINT UNSIGNED;
  DECLARE v_workflow_a CHAR(36);
  DECLARE v_workflow_a2 CHAR(36);
  DECLARE v_workflow_b CHAR(36);
  DECLARE v_approval BIGINT UNSIGNED;
  DECLARE v_key_in_progress BIGINT UNSIGNED;
  DECLARE v_key_review BIGINT UNSIGNED;
  DECLARE v_key_completed BIGINT UNSIGNED;
  DECLARE v_key_failed BIGINT UNSIGNED;
  DECLARE v_audit BIGINT UNSIGNED;
  DECLARE v_movement BIGINT UNSIGNED;
  DECLARE v_rollback_key BIGINT UNSIGNED;
  DECLARE v_rollback_audit BIGINT UNSIGNED;
  DECLARE v_rollback_movement BIGINT UNSIGNED;
  DECLARE v_payload_hash BINARY(32);
  DECLARE v_case INT UNSIGNED DEFAULT 1;
  DECLARE v_case_count INT UNSIGNED;
  DECLARE v_name VARCHAR(128);
  DECLARE v_sql VARCHAR(4096);
  DECLARE v_expected_errno INT;
  DECLARE v_actual_errno INT DEFAULT 0;
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_message TEXT;
  DECLARE v_failures INT UNSIGNED;
  DECLARE v_observed BIGINT DEFAULT 0;
  DECLARE v_prepared BOOLEAN DEFAULT FALSE;
  DECLARE v_results_created BOOLEAN DEFAULT FALSE;
  DECLARE v_cases_created BOOLEAN DEFAULT FALSE;
  DECLARE v_reported BOOLEAN DEFAULT FALSE;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    IF v_prepared THEN
      DEALLOCATE PREPARE awf_constraint_statement;
    END IF;
    IF v_results_created THEN
      IF NOT v_reported THEN
        SELECT test_name, expected_errno, actual_errno,
               IF(passed, 'PASS', 'FAIL') AS result, observed_sqlstate, detail
        FROM awf_constraint_results_v1 ORDER BY seq;
      END IF;
      DROP TEMPORARY TABLE awf_constraint_results_v1;
    END IF;
    IF v_cases_created THEN
      DROP TEMPORARY TABLE awf_constraint_cases_v1;
    END IF;
    SET @awf_constraint_sql_v1 = NULL;
    RESIGNAL;
  END;

  -- MEMORY keeps diagnostic rows after both savepoint and transaction rollback.
  CREATE TEMPORARY TABLE awf_constraint_results_v1 (
    seq INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    test_name VARCHAR(128) NOT NULL,
    expected_errno INT NOT NULL,
    actual_errno INT NOT NULL,
    observed_sqlstate CHAR(5) NOT NULL,
    detail VARCHAR(512) NOT NULL,
    passed BOOLEAN NOT NULL
  ) ENGINE=MEMORY;
  SET v_results_created = TRUE;

  CREATE TEMPORARY TABLE awf_constraint_cases_v1 (
    seq INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    test_name VARCHAR(128) NOT NULL,
    expected_errno INT NOT NULL,
    sql_text VARCHAR(4096) NOT NULL
  ) ENGINE=MEMORY;
  SET v_cases_created = TRUE;

  SET v_run = REPLACE(UUID(), '-', '');
  SET v_workflow_a = UUID();
  SET v_workflow_a2 = UUID();
  SET v_workflow_b = UUID();
  SET v_payload_hash = UNHEX(SHA2(CONCAT('awf-test-', v_run), 256));
  START TRANSACTION;

  INSERT INTO tenants (code, name)
  VALUES (CONCAT('awf_test_a_', v_run), 'Constraint test tenant A');
  SET v_tenant_a = LAST_INSERT_ID();
  INSERT INTO tenants (code, name)
  VALUES (CONCAT('awf_test_b_', v_run), 'Constraint test tenant B');
  SET v_tenant_b = LAST_INSERT_ID();

  INSERT INTO actors (tenant_id, identity_provider, external_subject, display_name, actor_type)
  VALUES (v_tenant_a, 'AWF_CONSTRAINT_TEST', CONCAT('actor-a-', v_run), 'Fixture operator A', 'HUMAN');
  SET v_actor_a = LAST_INSERT_ID();
  INSERT INTO actors (tenant_id, identity_provider, external_subject, display_name, actor_type)
  VALUES (v_tenant_a, 'AWF_CONSTRAINT_TEST', CONCAT('actor-a2-', v_run), 'Fixture approver A', 'HUMAN');
  SET v_actor_a2 = LAST_INSERT_ID();
  INSERT INTO actors (tenant_id, identity_provider, external_subject, display_name, actor_type)
  VALUES (v_tenant_b, 'AWF_CONSTRAINT_TEST', CONCAT('actor-b-', v_run), 'Fixture operator B', 'HUMAN');
  SET v_actor_b = LAST_INSERT_ID();

  INSERT INTO products (tenant_id, sku, name, unit_price, created_by, updated_by)
  VALUES (v_tenant_a, 'AWF_SHARED_SKU', 'Fixture product A', 50.00, v_actor_a, v_actor_a);
  SET v_product_a = LAST_INSERT_ID();
  INSERT INTO products (tenant_id, sku, name, unit_price, created_by, updated_by)
  VALUES (v_tenant_b, 'AWF_PRODUCT_B', 'Fixture product B', 50.00, v_actor_b, v_actor_b);
  SET v_product_b = LAST_INSERT_ID();

  INSERT INTO warehouses (tenant_id, code, name, created_by, updated_by)
  VALUES (v_tenant_a, 'AWF_WAREHOUSE_A', 'Fixture warehouse A', v_actor_a, v_actor_a);
  SET v_warehouse_a = LAST_INSERT_ID();
  INSERT INTO warehouses (tenant_id, code, name, created_by, updated_by)
  VALUES (v_tenant_b, 'AWF_WAREHOUSE_B', 'Fixture warehouse B', v_actor_b, v_actor_b);
  SET v_warehouse_b = LAST_INSERT_ID();

  INSERT INTO inventory
    (tenant_id, warehouse_id, product_id, quantity_on_hand, quantity_reserved, version, created_by, updated_by)
  VALUES (v_tenant_a, v_warehouse_a, v_product_a, 10, 2, 1, v_actor_a, v_actor_a);
  SET v_inventory_a = LAST_INSERT_ID();

  INSERT INTO orders (tenant_id, order_number, subtotal_amount, created_by, updated_by)
  VALUES (v_tenant_a, 'AWF_ORDER_A', 100.00, v_actor_a, v_actor_a);
  SET v_order_a = LAST_INSERT_ID();
  INSERT INTO orders (tenant_id, order_number, subtotal_amount, created_by, updated_by)
  VALUES (v_tenant_b, 'AWF_ORDER_B', 100.00, v_actor_b, v_actor_b);
  SET v_order_b = LAST_INSERT_ID();
  INSERT INTO order_items
    (tenant_id, order_id, product_id, line_number, sku_snapshot, name_snapshot, quantity, unit_price)
  VALUES (v_tenant_a, v_order_a, v_product_a, 1, 'AWF_SHARED_SKU', 'Fixture order item', 2, 50.00);

  INSERT INTO workflow_runs (id, tenant_id, requested_by, workflow_type, state_json)
  VALUES (v_workflow_a, v_tenant_a, v_actor_a, 'CONSTRAINT_TEST', JSON_OBJECT()),
         (v_workflow_a2, v_tenant_a, v_actor_a, 'CONSTRAINT_TEST', JSON_OBJECT()),
         (v_workflow_b, v_tenant_b, v_actor_b, 'CONSTRAINT_TEST', JSON_OBJECT());

  INSERT INTO approval_requests
    (tenant_id, workflow_id, requested_by, action_key, action_name, payload,
     payload_hash, resource_versions, risk_level, policy_version, risk_version, expires_at)
  VALUES
    (v_tenant_a, v_workflow_a, v_actor_a, 'fixture-action', 'update_stock',
     JSON_OBJECT('inventory_id', v_inventory_a, 'quantity_delta', 1), v_payload_hash,
     JSON_OBJECT('inventory_version', 1), 'HIGH', 'TEST_POLICY_1', 'TEST_RISK_1',
     CURRENT_TIMESTAMP(6) + INTERVAL 1 HOUR);
  SET v_approval = LAST_INSERT_ID();

  INSERT INTO idempotency_keys
    (tenant_id, actor_id, workflow_id, operation_name, idempotency_key, payload_hash)
  VALUES (v_tenant_a, v_actor_a, v_workflow_a, 'update_stock', 'CaseKey', v_payload_hash);
  SET v_key_in_progress = LAST_INSERT_ID();
  INSERT INTO idempotency_keys
    (tenant_id, actor_id, workflow_id, operation_name, idempotency_key, payload_hash, status)
  VALUES (v_tenant_a, v_actor_a, v_workflow_a, 'update_stock', 'review-key', v_payload_hash, 'NEEDS_REVIEW');
  SET v_key_review = LAST_INSERT_ID();
  INSERT INTO idempotency_keys
    (tenant_id, actor_id, workflow_id, operation_name, idempotency_key, payload_hash,
     status, response_snapshot, completed_at)
  VALUES (v_tenant_a, v_actor_a, v_workflow_a, 'update_stock', 'completed-key', v_payload_hash,
          'COMPLETED', JSON_OBJECT('quantity_on_hand', 10, 'version', 1), CURRENT_TIMESTAMP(6));
  SET v_key_completed = LAST_INSERT_ID();
  INSERT INTO idempotency_keys
    (tenant_id, actor_id, workflow_id, operation_name, idempotency_key, payload_hash,
     status, error_code, completed_at)
  VALUES (v_tenant_a, v_actor_a, v_workflow_a, 'update_stock', 'failed-key', v_payload_hash,
          'FAILED', 'FIXTURE_REJECTED', CURRENT_TIMESTAMP(6));
  SET v_key_failed = LAST_INSERT_ID();

  INSERT INTO audit_events
    (tenant_id, workflow_id, actor_id, idempotency_id, event_type, outcome,
     risk_level, policy_version, risk_version, payload_hash)
  VALUES (v_tenant_a, v_workflow_a, v_actor_a, v_key_completed, 'FIXTURE_OPENING_BALANCE',
          'SUCCESS', 'LOW', 'TEST_POLICY_1', 'TEST_RISK_1', v_payload_hash);
  SET v_audit = LAST_INSERT_ID();
  INSERT INTO inventory_movements
    (tenant_id, inventory_id, workflow_id, actor_id, idempotency_id, audit_event_id,
     action_line, quantity_delta, reserved_delta, balance_before, balance_after,
     reserved_before, reserved_after, inventory_version_after, reason_code, reference_type)
  VALUES (v_tenant_a, v_inventory_a, v_workflow_a, v_actor_a, v_key_completed, v_audit,
          1, 10, 2, 0, 10, 0, 2, 1, 'OPENING_BALANCE', 'MOCK');
  SET v_movement = LAST_INSERT_ID();

  -- Dynamic statements contain only controlled fixture IDs and constant SQL.
  -- Expected 0 means the operation must succeed; all other values are MySQL errno.
  INSERT INTO awf_constraint_cases_v1 (test_name, expected_errno, sql_text) VALUES
    ('cross_tenant_product_creator_rejected', 1452,
     CONCAT('INSERT INTO products (tenant_id,sku,name,unit_price,created_by,updated_by) VALUES (',
            v_tenant_a, ',''FOREIGN_CREATOR'',''Invalid creator'',1,', v_actor_b, ',', v_actor_a, ')')),
    ('cross_tenant_inventory_product_rejected', 1452,
     CONCAT('INSERT INTO inventory (tenant_id,warehouse_id,product_id,created_by,updated_by) VALUES (',
            v_tenant_a, ',', v_warehouse_a, ',', v_product_b, ',', v_actor_a, ',', v_actor_a, ')')),
    ('cross_tenant_inventory_warehouse_rejected', 1452,
     CONCAT('INSERT INTO inventory (tenant_id,warehouse_id,product_id,created_by,updated_by) VALUES (',
            v_tenant_a, ',', v_warehouse_b, ',', v_product_a, ',', v_actor_a, ',', v_actor_a, ')')),
    ('negative_stock_rejected', 3819,
     CONCAT('UPDATE inventory SET quantity_on_hand=-1,quantity_reserved=0 WHERE id=', v_inventory_a)),
    ('negative_reservation_rejected', 3819,
     CONCAT('UPDATE inventory SET quantity_reserved=-1 WHERE id=', v_inventory_a)),
    ('reservation_above_stock_rejected', 3819,
     CONCAT('UPDATE inventory SET quantity_reserved=11 WHERE id=', v_inventory_a)),
    ('reservation_equal_to_stock_allowed', 0,
     CONCAT('UPDATE inventory SET quantity_reserved=10 WHERE id=', v_inventory_a)),
    ('duplicate_sku_within_tenant_rejected', 1062,
     CONCAT('INSERT INTO products (tenant_id,sku,name,unit_price,created_by,updated_by) VALUES (',
            v_tenant_a, ',''AWF_SHARED_SKU'',''Duplicate SKU'',1,', v_actor_a, ',', v_actor_a, ')')),
    ('same_sku_in_other_tenant_allowed', 0,
     CONCAT('INSERT INTO products (tenant_id,sku,name,unit_price,created_by,updated_by) VALUES (',
            v_tenant_b, ',''AWF_SHARED_SKU'',''Independent tenant SKU'',1,', v_actor_b, ',', v_actor_b, ')')),
    ('order_item_cross_tenant_order_rejected', 1452,
     CONCAT('INSERT INTO order_items (tenant_id,order_id,product_id,line_number,sku_snapshot,name_snapshot,quantity,unit_price) VALUES (',
            v_tenant_a, ',', v_order_b, ',', v_product_a, ',2,''TEST'',''Cross tenant order'',1,1)')),
    ('order_item_cross_tenant_product_rejected', 1452,
     CONCAT('INSERT INTO order_items (tenant_id,order_id,product_id,line_number,sku_snapshot,name_snapshot,quantity,unit_price) VALUES (',
            v_tenant_a, ',', v_order_a, ',', v_product_b, ',2,''TEST'',''Cross tenant product'',1,1)')),
    ('order_item_zero_quantity_rejected', 3819,
     CONCAT('INSERT INTO order_items (tenant_id,order_id,product_id,line_number,sku_snapshot,name_snapshot,quantity,unit_price) VALUES (',
            v_tenant_a, ',', v_order_a, ',', v_product_a, ',2,''TEST'',''Zero quantity'',0,1)')),
    ('order_item_discount_above_subtotal_rejected', 3819,
     CONCAT('INSERT INTO order_items (tenant_id,order_id,product_id,line_number,sku_snapshot,name_snapshot,quantity,unit_price,discount_amount) VALUES (',
            v_tenant_a, ',', v_order_a, ',', v_product_a, ',2,''TEST'',''Invalid discount'',2,10,21)')),
    ('order_discount_above_subtotal_rejected', 3819,
     CONCAT('UPDATE orders SET discount_amount=101 WHERE id=', v_order_a)),
    ('paid_order_without_payment_timestamp_rejected', 3819,
     CONCAT('UPDATE orders SET payment_status=''PAID'' WHERE id=', v_order_a)),
    ('unpaid_order_with_refund_rejected', 3819,
     CONCAT('UPDATE orders SET refunded_amount=1 WHERE id=', v_order_a)),
    ('full_amount_as_partial_refund_rejected', 3819,
     CONCAT('UPDATE orders SET payment_status=''PARTIALLY_REFUNDED'',paid_at=CURRENT_TIMESTAMP(6),refunded_amount=100 WHERE id=', v_order_a)),
    ('valid_partial_refund_allowed', 0,
     CONCAT('UPDATE orders SET payment_status=''PARTIALLY_REFUNDED'',paid_at=CURRENT_TIMESTAMP(6),refunded_amount=40 WHERE id=', v_order_a)),
    ('duplicate_idempotency_identity_rejected', 1062,
     CONCAT('INSERT INTO idempotency_keys (tenant_id,actor_id,workflow_id,operation_name,idempotency_key,payload_hash) VALUES (',
            v_tenant_a, ',', v_actor_a, ',''', v_workflow_a,
            ''',''update_stock'',''CaseKey'',UNHEX(SHA2(''different-payload'',256)))')),
    ('idempotency_key_case_is_significant', 0,
     CONCAT('INSERT INTO idempotency_keys (tenant_id,actor_id,workflow_id,operation_name,idempotency_key,payload_hash) VALUES (',
            v_tenant_a, ',', v_actor_a, ',''', v_workflow_a,
            ''',''update_stock'',''casekey'',UNHEX(SHA2(''fixture'',256)))')),
    ('same_idempotency_key_for_other_actor_allowed', 0,
     CONCAT('INSERT INTO idempotency_keys (tenant_id,actor_id,workflow_id,operation_name,idempotency_key,payload_hash) VALUES (',
            v_tenant_a, ',', v_actor_a2, ',''', v_workflow_a,
            ''',''update_stock'',''CaseKey'',UNHEX(SHA2(''fixture'',256)))')),
    ('same_idempotency_key_for_other_operation_allowed', 0,
     CONCAT('INSERT INTO idempotency_keys (tenant_id,actor_id,workflow_id,operation_name,idempotency_key,payload_hash) VALUES (',
            v_tenant_a, ',', v_actor_a, ',''', v_workflow_a,
            ''',''reserve_stock'',''CaseKey'',UNHEX(SHA2(''fixture'',256)))')),
    ('approval_wrong_workflow_binding_rejected', 1452,
     CONCAT('INSERT INTO idempotency_keys (tenant_id,actor_id,workflow_id,approval_id,operation_name,idempotency_key,payload_hash) VALUES (',
            v_tenant_a, ',', v_actor_a, ',''', v_workflow_a2, ''',', v_approval,
            ',''update_stock'',''wrong-approval-binding'',UNHEX(SHA2(''fixture'',256)))')),
    ('approval_payload_mutation_rejected', 1644,
     CONCAT('UPDATE approval_requests SET payload=JSON_OBJECT(''quantity_delta'',999) WHERE id=', v_approval)),
    ('approval_hash_mutation_rejected', 1644,
     CONCAT('UPDATE approval_requests SET payload_hash=UNHEX(SHA2(''changed'',256)) WHERE id=', v_approval)),
    ('approval_workflow_rebinding_rejected', 1644,
     CONCAT('UPDATE approval_requests SET workflow_id=''', v_workflow_a2, ''' WHERE id=', v_approval)),
    ('approval_resource_version_mutation_rejected', 1644,
     CONCAT('UPDATE approval_requests SET resource_versions=JSON_OBJECT(''inventory_version'',2) WHERE id=', v_approval)),
    ('pending_approval_direct_execution_rejected', 1644,
     CONCAT('UPDATE approval_requests SET status=''EXECUTED'',decided_by=', v_actor_a2,
            ',decided_at=CURRENT_TIMESTAMP(6),executed_at=CURRENT_TIMESTAMP(6) WHERE id=', v_approval)),
    ('audit_update_rejected', 1644,
     CONCAT('UPDATE audit_events SET event_type=''TAMPERED'' WHERE id=', v_audit)),
    ('audit_delete_rejected', 1644,
     CONCAT('DELETE FROM audit_events WHERE id=', v_audit)),
    ('movement_update_rejected', 1644,
     CONCAT('UPDATE inventory_movements SET reason_code=''CORRECTION'' WHERE id=', v_movement)),
    ('movement_delete_rejected', 1644,
     CONCAT('DELETE FROM inventory_movements WHERE id=', v_movement)),
    ('idempotency_identity_mutation_rejected', 1644,
     CONCAT('UPDATE idempotency_keys SET idempotency_key=''replacement-key'' WHERE id=', v_key_in_progress)),
    ('idempotency_payload_hash_mutation_rejected', 1644,
     CONCAT('UPDATE idempotency_keys SET payload_hash=UNHEX(SHA2(''changed'',256)) WHERE id=', v_key_in_progress)),
    ('completed_idempotency_snapshot_mutation_rejected', 1644,
     CONCAT('UPDATE idempotency_keys SET response_snapshot=JSON_OBJECT(''tampered'',1) WHERE id=', v_key_completed)),
    ('completed_idempotency_reexecution_rejected', 1644,
     CONCAT('UPDATE idempotency_keys SET status=''IN_PROGRESS'',completed_at=NULL,response_snapshot=NULL WHERE id=', v_key_completed)),
    ('failed_idempotency_result_mutation_rejected', 1644,
     CONCAT('UPDATE idempotency_keys SET error_code=''REPLACED_RESULT'' WHERE id=', v_key_failed)),
    ('failed_idempotency_reexecution_rejected', 1644,
     CONCAT('UPDATE idempotency_keys SET status=''IN_PROGRESS'',completed_at=NULL,error_code=NULL WHERE id=', v_key_failed)),
    ('in_progress_key_deletion_rejected', 1644,
     CONCAT('DELETE FROM idempotency_keys WHERE id=', v_key_in_progress)),
    ('needs_review_key_deletion_rejected', 1644,
     CONCAT('DELETE FROM idempotency_keys WHERE id=', v_key_review));

  SELECT COUNT(*) INTO v_case_count FROM awf_constraint_cases_v1;
  WHILE v_case <= v_case_count DO
    SELECT test_name, expected_errno, sql_text
      INTO v_name, v_expected_errno, v_sql
    FROM awf_constraint_cases_v1 WHERE seq = v_case;
    SET v_actual_errno = 0;
    SET v_sqlstate = '00000';
    SET v_message = 'Statement succeeded';
    SET v_prepared = FALSE;
    SET @awf_constraint_sql_v1 = v_sql;
    SAVEPOINT awf_constraint_case_v1;

    BEGIN
      -- EXIT captures the original PREPARE/EXECUTE failure, rather than hiding it
      -- behind a later statement or treating every error as the expected error.
      DECLARE EXIT HANDLER FOR SQLEXCEPTION
        GET DIAGNOSTICS CONDITION 1
          v_actual_errno = MYSQL_ERRNO,
          v_sqlstate = RETURNED_SQLSTATE,
          v_message = MESSAGE_TEXT;
      PREPARE awf_constraint_statement FROM @awf_constraint_sql_v1;
      SET v_prepared = TRUE;
      EXECUTE awf_constraint_statement;
      DEALLOCATE PREPARE awf_constraint_statement;
      SET v_prepared = FALSE;
    END;

    IF v_prepared THEN
      DEALLOCATE PREPARE awf_constraint_statement;
      SET v_prepared = FALSE;
    END IF;
    -- A broken guard may allow a negative case to mutate data. Undo each case
    -- so subsequent checks always see the original fixture.
    ROLLBACK TO SAVEPOINT awf_constraint_case_v1;
    RELEASE SAVEPOINT awf_constraint_case_v1;
    INSERT INTO awf_constraint_results_v1
      (test_name, expected_errno, actual_errno, observed_sqlstate, detail, passed)
    VALUES (v_name, v_expected_errno, v_actual_errno, v_sqlstate,
            LEFT(v_message, 512), v_actual_errno = v_expected_errno);
    SET v_case = v_case + 1;
  END WHILE;

  -- Exercise one complete SQL write unit and roll it back. This checks database
  -- atomic rollback, not backend idempotency replay or concurrent request handling.
  SAVEPOINT awf_atomic_write_v1;
  UPDATE inventory
  SET quantity_on_hand = 15, version = 2, updated_by = v_actor_a
  WHERE tenant_id = v_tenant_a AND id = v_inventory_a;

  INSERT INTO idempotency_keys
    (tenant_id, actor_id, workflow_id, operation_name, idempotency_key, payload_hash,
     status, response_snapshot, completed_at)
  VALUES (v_tenant_a, v_actor_a, v_workflow_a, 'update_stock', 'rollback-write', v_payload_hash,
          'COMPLETED', JSON_OBJECT('quantity_on_hand', 15, 'version', 2), CURRENT_TIMESTAMP(6));
  SET v_rollback_key = LAST_INSERT_ID();
  INSERT INTO audit_events
    (tenant_id, workflow_id, actor_id, idempotency_id, event_type, outcome,
     risk_level, policy_version, risk_version, payload_hash)
  VALUES (v_tenant_a, v_workflow_a, v_actor_a, v_rollback_key, 'ROLLBACK_WRITE',
          'SUCCESS', 'LOW', 'TEST_POLICY_1', 'TEST_RISK_1', v_payload_hash);
  SET v_rollback_audit = LAST_INSERT_ID();
  INSERT INTO inventory_movements
    (tenant_id, inventory_id, workflow_id, actor_id, idempotency_id, audit_event_id,
     action_line, quantity_delta, balance_before, balance_after, reserved_before,
     reserved_after, inventory_version_after, reason_code, reference_type)
  VALUES (v_tenant_a, v_inventory_a, v_workflow_a, v_actor_a, v_rollback_key, v_rollback_audit,
          1, 5, 10, 15, 2, 2, 2, 'RESTOCK', 'MOCK');
  SET v_rollback_movement = LAST_INSERT_ID();

  SELECT COUNT(*) INTO v_observed
  FROM inventory
  WHERE id = v_inventory_a AND quantity_on_hand = 15
    AND quantity_reserved = 2 AND quantity_available = 13 AND version = 2;
  INSERT INTO awf_constraint_results_v1
    (test_name, expected_errno, actual_errno, observed_sqlstate, detail, passed)
  VALUES ('atomic_write_fixture_changed_before_rollback', 0, IF(v_observed = 1, 0, -1),
          '00000', 'The write must exist before rollback; -1 means the assertion failed', v_observed = 1);

  ROLLBACK TO SAVEPOINT awf_atomic_write_v1;
  RELEASE SAVEPOINT awf_atomic_write_v1;
  SELECT
    (SELECT COUNT(*) FROM inventory WHERE id = v_inventory_a
      AND quantity_on_hand = 10 AND quantity_reserved = 2 AND quantity_available = 8 AND version = 1)
    + (SELECT COUNT(*) FROM idempotency_keys WHERE id = v_rollback_key)
    + (SELECT COUNT(*) FROM audit_events WHERE id = v_rollback_audit)
    + (SELECT COUNT(*) FROM inventory_movements WHERE id = v_rollback_movement)
    INTO v_observed;
  -- The count above must be 1, with only the original inventory matching.
  -- Check each inserted row separately too, avoiding an accidental equal sum.
  IF v_observed = 1
     AND NOT EXISTS (SELECT 1 FROM idempotency_keys WHERE id = v_rollback_key)
     AND NOT EXISTS (SELECT 1 FROM audit_events WHERE id = v_rollback_audit)
     AND NOT EXISTS (SELECT 1 FROM inventory_movements WHERE id = v_rollback_movement) THEN
    SET v_actual_errno = 0;
  ELSE
    SET v_actual_errno = -1;
  END IF;
  INSERT INTO awf_constraint_results_v1
    (test_name, expected_errno, actual_errno, observed_sqlstate, detail, passed)
  VALUES ('atomic_inventory_key_audit_movement_rollback', 0, v_actual_errno, '00000',
          'Inventory restored and inserted key/audit/movement absent; -1 means the assertion failed',
          v_actual_errno = 0);

  -- Roll back ALL fixtures, including append-only rows, before reporting results.
  ROLLBACK;
  SELECT COUNT(*) INTO v_observed FROM tenants WHERE id IN (v_tenant_a, v_tenant_b);
  INSERT INTO awf_constraint_results_v1
    (test_name, expected_errno, actual_errno, observed_sqlstate, detail, passed)
  VALUES ('all_fixture_tenants_rolled_back', 0, IF(v_observed = 0, 0, -1), '00000',
          'Neither UUID-scoped fixture tenant remains; -1 means the assertion failed', v_observed = 0);

  SELECT COUNT(*) INTO v_failures FROM awf_constraint_results_v1 WHERE passed = FALSE;
  SELECT test_name, expected_errno, actual_errno,
         IF(passed, 'PASS', 'FAIL') AS result, observed_sqlstate, detail
  FROM awf_constraint_results_v1 ORDER BY seq;
  SELECT COUNT(*) AS total_checks, SUM(passed) AS passed_checks, v_failures AS failed_checks
  FROM awf_constraint_results_v1;
  SET v_reported = TRUE;

  DROP TEMPORARY TABLE awf_constraint_cases_v1;
  SET v_cases_created = FALSE;
  DROP TEMPORARY TABLE awf_constraint_results_v1;
  SET v_results_created = FALSE;
  SET @awf_constraint_sql_v1 = NULL;
  IF v_failures > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Database constraint checks failed; inspect the result set. All fixtures were rolled back.';
  END IF;
END$$
DELIMITER ;

CALL awf_test_constraints_v1();
-- With stop-on-error enabled, reached only after a successful CALL.
DROP PROCEDURE awf_test_constraints_v1;
