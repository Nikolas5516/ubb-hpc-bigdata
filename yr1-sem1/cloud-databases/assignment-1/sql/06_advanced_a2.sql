-- ============================================================================
-- 06_advanced_a2.sql
-- Advanced A2 bonus: MariaDB native bitemporal syntax.
--
-- RUNS AGAINST MARIADB, NOT MYSQL. Bring the service up first:
--   docker compose --profile a2 up -d mariadb --wait
--   docker compose exec mariadb sh -c "mariadb -uroot -proot football < /sql/06_advanced_a2.sql"
--
-- Does NOT depend on the MySQL pipeline. The MariaDB container has its own
-- empty `football` database and no shared data with the MySQL side.
--
-- Demonstrates three native-temporal constructs on a single table that stands
-- in for head_coach_version:
--   Demo 1  WITHOUT OVERLAPS      — engine enforces I1 natively (vs. our
--                                    manual close-before-insert discipline
--                                    + v_integrity_violations check in MySQL)
--   Demo 2  FOR PORTION OF        — surgical VT correction in one statement
--                                    (vs. our two-row close+insert pattern)
--   Demo 3  FOR SYSTEM_TIME AS OF — the three-answer query becomes trivial:
--                                    one declarative line, no query_params
--                                    parameter table, no bitemporal predicate
--                                    arithmetic in the view
--
-- Effect on the decision guide (report §11): query ergonomics moves from
-- medium to strong.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS football;
USE football;

DROP TABLE IF EXISTS head_coach_bitemporal;

CREATE TABLE head_coach_bitemporal (
    version_id  BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    club_id     INT          NOT NULL,
    coach_name  VARCHAR(100) NOT NULL,
    valid_from  DATE         NOT NULL,
    valid_to    DATE         NOT NULL,
    PERIOD FOR validity (valid_from, valid_to),
    row_start   TIMESTAMP(6) GENERATED ALWAYS AS ROW START,
    row_end     TIMESTAMP(6) GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (row_start, row_end),
    UNIQUE KEY uk_club_vt (club_id, validity WITHOUT OVERLAPS)
) WITH SYSTEM VERSIONING;

-- ============================================================================
-- DEMO 1 · WITHOUT OVERLAPS replaces manual I1 enforcement
-- ----------------------------------------------------------------------------
-- In MySQL (01_schema.sql + 03_timeline.sql) we enforce I1 by discipline:
--   * every event closes tx_to before inserting the new row
--   * v_integrity_violations (Q0) provides on-demand verification
-- MariaDB's `UNIQUE (club_id, validity WITHOUT OVERLAPS)` makes the engine
-- reject an overlapping insert outright — no discipline required.
-- The check is system-time-aware: it only compares currently-visible rows,
-- so historical rows don't trigger false positives.
-- ============================================================================

SELECT '--- Demo 1: WITHOUT OVERLAPS enforcement ---' AS section;

-- Two half-open adjacent periods for club 1 — accepted
INSERT INTO head_coach_bitemporal (club_id, coach_name, valid_from, valid_to)
VALUES (1, 'CoachA', '2023-07-01', '2025-06-30');

INSERT INTO head_coach_bitemporal (club_id, coach_name, valid_from, valid_to)
VALUES (1, 'CoachB', '2025-06-30', '2027-06-30');

SELECT 'Accepted: two half-open adjacent periods for club 1' AS note;
SELECT coach_name, valid_from, valid_to
  FROM head_coach_bitemporal WHERE club_id = 1 ORDER BY valid_from;

-- Attempt an overlapping insert — rejected by WITHOUT OVERLAPS
DELIMITER $$
CREATE OR REPLACE PROCEDURE p_demo1_overlap_reject()
BEGIN
    DECLARE EXIT HANDLER FOR SQLSTATE '23000'
    BEGIN
        SELECT 'PASS — WITHOUT OVERLAPS rejected the overlapping insert' AS result;
    END;
    INSERT INTO head_coach_bitemporal (club_id, coach_name, valid_from, valid_to)
    VALUES (1, 'CoachX', '2024-01-01', '2026-01-01');
    SELECT 'FAIL — WITHOUT OVERLAPS did NOT reject' AS result;
END$$
DELIMITER ;

CALL p_demo1_overlap_reject();
DROP PROCEDURE p_demo1_overlap_reject;

-- ============================================================================
-- DEMO 2 · FOR PORTION OF replaces manual close-and-insert
-- ----------------------------------------------------------------------------
-- In MySQL (03_timeline.sql) a mid-period change takes three statements per
-- event: close the old row, insert the amended row, insert the new period.
-- MariaDB's `UPDATE ... FOR PORTION OF validity FROM X TO Y` does all three
-- in a single declarative statement — the engine splits the row at the
-- boundary and writes the old half to the system-versioning history.
-- ============================================================================

SELECT '--- Demo 2: FOR PORTION OF ---' AS section;

INSERT INTO head_coach_bitemporal (club_id, coach_name, valid_from, valid_to)
VALUES (2, 'Reyes', '2022-06-15', '9999-12-31');

SELECT 'Before: one open-ended row for club 2' AS note;
SELECT coach_name, valid_from, valid_to
  FROM head_coach_bitemporal WHERE club_id = 2 ORDER BY valid_from;

-- Hamill takes over at club 2 from 2026-07-01 onward
UPDATE head_coach_bitemporal
   FOR PORTION OF validity FROM '2026-07-01' TO '9999-12-31'
   SET coach_name = 'Hamill'
 WHERE club_id = 2;

SELECT 'After FOR PORTION OF: engine split the row into two' AS note;
SELECT coach_name, valid_from, valid_to
  FROM head_coach_bitemporal WHERE club_id = 2 ORDER BY valid_from;

-- ============================================================================
-- DEMO 3 · FOR SYSTEM_TIME AS OF reproduces the three-answer test
-- ----------------------------------------------------------------------------
-- The MySQL Q6 view uses:
--   WHERE hc.tx_from    <= q.known_at AND q.known_at <  hc.tx_to
--     AND hc.valid_from <= q.valid_at AND q.valid_at <  hc.valid_to
-- With MariaDB's FOR SYSTEM_TIME AS OF the TT predicate is one line.
--
-- Setup replays Chelsea's coach timeline (events 16 + 17 in the main story),
-- using system_versioning_insert_history = 1 to backdate the row_start /
-- row_end values so the three AS-OF probes return reproducible answers on
-- any run date.
--
-- Five historical rows cover the three TT eras:
--   TT era 1  (2024-06-01 → 2026-02-15): Whittaker open-ended
--   TT era 2  (2026-02-15 → 2026-02-20): event 16 late-enters Delaney at
--                                        2026-02-01 (amended Whittaker +
--                                        new Delaney)
--   TT era 3  (2026-02-20 → max        ): event 17 corrects to 2026-02-05
-- ============================================================================

SELECT '--- Demo 3: three-answer test with FOR SYSTEM_TIME AS OF ---' AS section;

-- Note: when system_versioning_insert_history=1, MariaDB's AUTO_INCREMENT
-- does not advance for history inserts, so every row would receive version_id=0.
-- Because the internal primary key is effectively (version_id, row_end),
-- two rows sharing the same row_end would then collide on (0, row_end).
-- Explicit version_id values avoid the collision.

SET @@system_versioning_insert_history = 1;

-- TT era 1 (closed historical row): Whittaker open-ended, as initially believed
INSERT INTO head_coach_bitemporal
    (version_id, club_id, coach_name, valid_from, valid_to, row_start, row_end)
VALUES
    (101, 5, 'Whittaker', '2024-06-01', '9999-12-31',
     '2024-06-01 09:00:00.000000', '2026-02-15 11:00:00.000000');

-- TT era 2 (closed historical rows): event 16 late entry
INSERT INTO head_coach_bitemporal
    (version_id, club_id, coach_name, valid_from, valid_to, row_start, row_end)
VALUES
    (102, 5, 'Whittaker', '2024-06-01', '2026-02-01',
     '2026-02-15 11:00:00.000000', '2026-02-20 11:00:00.000000'),
    (103, 5, 'Delaney',   '2026-02-01', '9999-12-31',
     '2026-02-15 11:00:00.000000', '2026-02-20 11:00:00.000000');

-- TT era 3 (currently-visible rows: row_end = TIMESTAMP(6) max): event 17 correction
INSERT INTO head_coach_bitemporal
    (version_id, club_id, coach_name, valid_from, valid_to, row_start, row_end)
VALUES
    (104, 5, 'Whittaker', '2024-06-01', '2026-02-05',
     '2026-02-20 11:00:00.000000', '2038-01-19 03:14:07.999999'),
    (105, 5, 'Delaney',   '2026-02-05', '9999-12-31',
     '2026-02-20 11:00:00.000000', '2038-01-19 03:14:07.999999');

SET @@system_versioning_insert_history = 0;

-- Three AS-OF probes with the same valid_at (2026-02-03), different known_at
SELECT 'Answer 1 (known_at=2026-02-10): expect Whittaker' AS probe;
SELECT coach_name FROM head_coach_bitemporal
 FOR SYSTEM_TIME AS OF '2026-02-10 00:00:00.000000'
 WHERE club_id = 5
   AND valid_from <= '2026-02-03' AND '2026-02-03' < valid_to;

SELECT 'Answer 2 (known_at=2026-02-17): expect Delaney' AS probe;
SELECT coach_name FROM head_coach_bitemporal
 FOR SYSTEM_TIME AS OF '2026-02-17 00:00:00.000000'
 WHERE club_id = 5
   AND valid_from <= '2026-02-03' AND '2026-02-03' < valid_to;

SELECT 'Answer 3 (known_at=2026-10-01): expect Whittaker' AS probe;
SELECT coach_name FROM head_coach_bitemporal
 FOR SYSTEM_TIME AS OF '2026-10-01 00:00:00.000000'
 WHERE club_id = 5
   AND valid_from <= '2026-02-03' AND '2026-02-03' < valid_to;

-- Verification: show the full TT history for club 5 (all 5 rows across all eras)
SELECT 'TT history for club 5 (all five rows across all three TT eras):' AS note;
SELECT coach_name, valid_from, valid_to, row_start, row_end
  FROM head_coach_bitemporal FOR SYSTEM_TIME ALL
 WHERE club_id = 5
 ORDER BY row_start, valid_from;

SELECT '--- A2 install complete ---' AS summary;