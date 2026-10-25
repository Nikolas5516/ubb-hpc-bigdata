-- ============================================================================
-- 06_advanced_a1.sql
-- Advanced A1 bonus: MySQL triggers + stored procedures for bitemporal integrity.
--
-- Adds BEFORE UPDATE / BEFORE DELETE triggers to the three bitemporal tables
-- that forbid any mutation except closing tx_to on a currently-believed row.
-- Adds stored procedures that encapsulate the common bitemporal write patterns.
--
-- Depends on 01-05 having run. Re-runnable (DROPs first).
-- Does NOT modify any existing data. The existing timeline continues to work
-- because every UPDATE in 03_timeline.sql only sets tx_to on currently-believed
-- rows — which the triggers permit.
--
-- Effect on the decision guide (report §11): tamper resistance moves from
-- weak to medium. The ceiling is a DBA with ALTER TABLE privileges who could
-- drop the triggers themselves — an unavoidable limit of in-engine protection.
-- ============================================================================

USE football;

-- ----------------------------------------------------------------------------
-- Clean slate (idempotent re-run)
-- ----------------------------------------------------------------------------
DROP TRIGGER   IF EXISTS trg_contract_bu;
DROP TRIGGER   IF EXISTS trg_contract_bd;
DROP TRIGGER   IF EXISTS trg_loan_bu;
DROP TRIGGER   IF EXISTS trg_loan_bd;
DROP TRIGGER   IF EXISTS trg_hc_bu;
DROP TRIGGER   IF EXISTS trg_hc_bd;

DROP PROCEDURE IF EXISTS p_tx_begin;
DROP PROCEDURE IF EXISTS p_contract_insert;
DROP PROCEDURE IF EXISTS p_contract_close;
DROP PROCEDURE IF EXISTS p_contract_close_at;
DROP PROCEDURE IF EXISTS p_loan_insert;
DROP PROCEDURE IF EXISTS p_loan_close;
DROP PROCEDURE IF EXISTS p_loan_close_at;
DROP PROCEDURE IF EXISTS p_hc_insert;
DROP PROCEDURE IF EXISTS p_hc_close;
DROP PROCEDURE IF EXISTS p_hc_close_at;
DROP PROCEDURE IF EXISTS p_demo_tamper_update;
DROP PROCEDURE IF EXISTS p_demo_tamper_delete;

-- ============================================================================
-- SECTION 1 · TRIGGERS
-- ----------------------------------------------------------------------------
-- Each table gets a BEFORE UPDATE trigger that enforces:
--   (1) No business column may change (only tx_to).
--   (2) The row being modified must be currently-believed (OLD.tx_to = sentinel).
--   (3) The new tx_to must be a finite closing time, strictly > tx_from and
--       strictly < the sentinel.
-- Plus a BEFORE DELETE trigger that unconditionally SIGNALs — history is
-- append-only; close tx_to to retire a belief, never DELETE.
-- ============================================================================

DELIMITER $$

-- -- contract_version -------------------------------------------------------
CREATE TRIGGER trg_contract_bu BEFORE UPDATE ON contract_version
FOR EACH ROW
BEGIN
    IF OLD.player_id   <> NEW.player_id
    OR OLD.club_id     <> NEW.club_id
    OR OLD.salary_eur  <> NEW.salary_eur
    OR OLD.valid_from  <> NEW.valid_from
    OR OLD.valid_to    <> NEW.valid_to
    OR OLD.tx_from     <> NEW.tx_from
    OR OLD.tx_id       <> NEW.tx_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'contract_version: only tx_to may change (business columns are immutable)';
    END IF;

    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'contract_version: cannot modify an already-closed row (tx_to != sentinel)';
    END IF;

    IF NEW.tx_to >= '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'contract_version: tx_to must close to a finite time < sentinel';
    END IF;

    IF NEW.tx_to <= NEW.tx_from THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'contract_version: tx_to must be strictly > tx_from';
    END IF;
END$$

CREATE TRIGGER trg_contract_bd BEFORE DELETE ON contract_version
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'contract_version: DELETE forbidden (append-only history; close tx_to instead)';
END$$

-- -- loan_version -----------------------------------------------------------
CREATE TRIGGER trg_loan_bu BEFORE UPDATE ON loan_version
FOR EACH ROW
BEGIN
    IF OLD.player_id    <> NEW.player_id
    OR OLD.from_club_id <> NEW.from_club_id
    OR OLD.to_club_id   <> NEW.to_club_id
    OR OLD.valid_from   <> NEW.valid_from
    OR OLD.valid_to     <> NEW.valid_to
    OR OLD.tx_from      <> NEW.tx_from
    OR OLD.tx_id        <> NEW.tx_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'loan_version: only tx_to may change';
    END IF;

    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'loan_version: cannot modify an already-closed row';
    END IF;

    IF NEW.tx_to >= '9999-12-31 23:59:59.999999' OR NEW.tx_to <= NEW.tx_from THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'loan_version: tx_to must be strictly between tx_from and sentinel';
    END IF;
END$$

CREATE TRIGGER trg_loan_bd BEFORE DELETE ON loan_version
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'loan_version: DELETE forbidden (append-only history; close tx_to instead)';
END$$

-- -- head_coach_version -----------------------------------------------------
CREATE TRIGGER trg_hc_bu BEFORE UPDATE ON head_coach_version
FOR EACH ROW
BEGIN
    IF OLD.club_id    <> NEW.club_id
    OR OLD.coach_id   <> NEW.coach_id
    OR OLD.valid_from <> NEW.valid_from
    OR OLD.valid_to   <> NEW.valid_to
    OR OLD.tx_from    <> NEW.tx_from
    OR OLD.tx_id      <> NEW.tx_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'head_coach_version: only tx_to may change';
    END IF;

    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'head_coach_version: cannot modify an already-closed row';
    END IF;

    IF NEW.tx_to >= '9999-12-31 23:59:59.999999' OR NEW.tx_to <= NEW.tx_from THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'head_coach_version: tx_to must be strictly between tx_from and sentinel';
    END IF;
END$$

CREATE TRIGGER trg_hc_bd BEFORE DELETE ON head_coach_version
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'head_coach_version: DELETE forbidden (append-only history; close tx_to instead)';
END$$

-- ============================================================================
-- SECTION 2 · STORED PROCEDURES
-- ----------------------------------------------------------------------------
-- Encapsulate the common write patterns so timeline code never touches raw
-- INSERT/UPDATE on the version tables. Three procedures per table:
--   p_<t>_insert     — insert a new version row stamped with sim_now, tx_id
--   p_<t>_close      — close all currently-believed rows for a business key
--   p_<t>_close_at   — close one specific row by version_id (surgical E4)
-- Plus p_tx_begin which opens a tx_registry entry and hands back the tx_id.
-- ============================================================================

CREATE PROCEDURE p_tx_begin(
    IN  p_author  VARCHAR(100),
    IN  p_reason  VARCHAR(255),
    IN  p_sim_now DATETIME(6),
    OUT p_tx_id   BIGINT)
BEGIN
    INSERT INTO tx_registry (tx_time, author, reason)
    VALUES (p_sim_now, p_author, p_reason);
    SET p_tx_id = LAST_INSERT_ID();
END$$

-- -- contract_version -------------------------------------------------------
CREATE PROCEDURE p_contract_insert(
    IN p_player_id  INT,
    IN p_club_id    INT,
    IN p_salary     DECIMAL(12,2),
    IN p_valid_from DATE,
    IN p_valid_to   DATE,
    IN p_sim_now    DATETIME(6),
    IN p_tx_id      BIGINT)
BEGIN
    INSERT INTO contract_version
        (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id)
    VALUES
        (p_player_id, p_club_id, p_salary, p_valid_from, p_valid_to, p_sim_now, p_tx_id);
END$$

CREATE PROCEDURE p_contract_close(
    IN p_player_id INT,
    IN p_sim_now   DATETIME(6))
BEGIN
    UPDATE contract_version
       SET tx_to = p_sim_now
     WHERE player_id = p_player_id
       AND tx_to    = '9999-12-31 23:59:59.999999';
END$$

CREATE PROCEDURE p_contract_close_at(
    IN p_version_id BIGINT,
    IN p_sim_now    DATETIME(6))
BEGIN
    UPDATE contract_version
       SET tx_to = p_sim_now
     WHERE version_id = p_version_id
       AND tx_to      = '9999-12-31 23:59:59.999999';
END$$

-- -- loan_version -----------------------------------------------------------
CREATE PROCEDURE p_loan_insert(
    IN p_player_id    INT,
    IN p_from_club_id INT,
    IN p_to_club_id   INT,
    IN p_valid_from   DATE,
    IN p_valid_to     DATE,
    IN p_sim_now      DATETIME(6),
    IN p_tx_id        BIGINT)
BEGIN
    INSERT INTO loan_version
        (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id)
    VALUES
        (p_player_id, p_from_club_id, p_to_club_id, p_valid_from, p_valid_to, p_sim_now, p_tx_id);
END$$

CREATE PROCEDURE p_loan_close(
    IN p_player_id INT,
    IN p_sim_now   DATETIME(6))
BEGIN
    UPDATE loan_version
       SET tx_to = p_sim_now
     WHERE player_id = p_player_id
       AND tx_to    = '9999-12-31 23:59:59.999999';
END$$

CREATE PROCEDURE p_loan_close_at(
    IN p_version_id BIGINT,
    IN p_sim_now    DATETIME(6))
BEGIN
    UPDATE loan_version
       SET tx_to = p_sim_now
     WHERE version_id = p_version_id
       AND tx_to      = '9999-12-31 23:59:59.999999';
END$$

-- -- head_coach_version -----------------------------------------------------
CREATE PROCEDURE p_hc_insert(
    IN p_club_id    INT,
    IN p_coach_id   INT,
    IN p_valid_from DATE,
    IN p_valid_to   DATE,
    IN p_sim_now    DATETIME(6),
    IN p_tx_id      BIGINT)
BEGIN
    INSERT INTO head_coach_version
        (club_id, coach_id, valid_from, valid_to, tx_from, tx_id)
    VALUES
        (p_club_id, p_coach_id, p_valid_from, p_valid_to, p_sim_now, p_tx_id);
END$$

CREATE PROCEDURE p_hc_close(
    IN p_club_id INT,
    IN p_sim_now DATETIME(6))
BEGIN
    UPDATE head_coach_version
       SET tx_to = p_sim_now
     WHERE club_id = p_club_id
       AND tx_to  = '9999-12-31 23:59:59.999999';
END$$

CREATE PROCEDURE p_hc_close_at(
    IN p_version_id BIGINT,
    IN p_sim_now    DATETIME(6))
BEGIN
    UPDATE head_coach_version
       SET tx_to = p_sim_now
     WHERE version_id = p_version_id
       AND tx_to      = '9999-12-31 23:59:59.999999';
END$$

-- ============================================================================
-- SECTION 3 · TAMPER-RESISTANCE VERIFICATION
-- ----------------------------------------------------------------------------
-- Two procedures wrap forbidden operations in DECLARE EXIT HANDLERs and
-- report whether the triggers rejected them. Expected: both say PASS.
-- ============================================================================

CREATE PROCEDURE p_demo_tamper_update()
BEGIN
    DECLARE EXIT HANDLER FOR SQLSTATE '45000'
    BEGIN
        SELECT 'PASS — trigger rejected direct UPDATE of a business column' AS tamper_test_update;
    END;

    UPDATE contract_version
       SET salary_eur = 1
     WHERE player_id = 1
       AND tx_to    = '9999-12-31 23:59:59.999999'
     LIMIT 1;

    SELECT 'FAIL — trigger did NOT reject UPDATE' AS tamper_test_update;
END$$

CREATE PROCEDURE p_demo_tamper_delete()
BEGIN
    DECLARE EXIT HANDLER FOR SQLSTATE '45000'
    BEGIN
        SELECT 'PASS — trigger rejected DELETE' AS tamper_test_delete;
    END;

    DELETE FROM contract_version
     WHERE player_id = 1
     LIMIT 1;

    SELECT 'FAIL — trigger did NOT reject DELETE' AS tamper_test_delete;
END$$

DELIMITER ;

-- ============================================================================
-- SECTION 4 · RUN THE VERIFICATION
-- ============================================================================

SELECT '--- A1 verification: tamper resistance ---' AS section;
CALL p_demo_tamper_update();
CALL p_demo_tamper_delete();

-- ============================================================================
-- SECTION 5 · POSITIVE DEMO (ROLLED BACK)
-- ----------------------------------------------------------------------------
-- Shows the stored-procedure write workflow for a hypothetical E2 extension
-- on Pennington (player 1). Everything is rolled back at the end so no data
-- persists — 05_tests.sql's expected counts remain accurate on re-run.
-- ============================================================================

SELECT '--- A1 demo: procedure-based write workflow (rolled back) ---' AS section;

SELECT 'BEFORE: Pennington currently-believed contract rows' AS note;
SELECT version_id, salary_eur, valid_from, valid_to
  FROM contract_version
 WHERE player_id = 1
   AND tx_to    = '9999-12-31 23:59:59.999999'
 ORDER BY valid_from;

START TRANSACTION;

SET @demo_now := '2026-10-26 10:00:00.000000';
SET @demo_tx  := NULL;

CALL p_tx_begin('a1-demo', 'A1 demo: hypothetical Pennington extension', @demo_now, @demo_tx);
CALL p_contract_close(1, @demo_now);
CALL p_contract_insert(1, 1, 12000000, '2028-07-01', '2030-06-30', @demo_now, @demo_tx);

SELECT 'DURING: Pennington currently-believed rows (inside transaction)' AS note;
SELECT version_id, salary_eur, valid_from, valid_to
  FROM contract_version
 WHERE player_id = 1
   AND tx_to    = '9999-12-31 23:59:59.999999'
 ORDER BY valid_from;

ROLLBACK;

SELECT 'AFTER ROLLBACK: Pennington currently-believed rows (should match BEFORE)' AS note;
SELECT version_id, salary_eur, valid_from, valid_to
  FROM contract_version
 WHERE player_id = 1
   AND tx_to    = '9999-12-31 23:59:59.999999'
 ORDER BY valid_from;

SELECT '--- A1 install complete ---' AS summary;