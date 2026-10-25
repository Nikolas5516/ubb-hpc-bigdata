-- ============================================================================
-- 04_views.sql
-- Views Q0..Q8 and the query_params parameter table
--
-- Expects 01_schema.sql + 02_data.sql + 03_timeline.sql to have run.
-- Re-runnable: DROPs first.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Clean slate
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS v_integrity_violations;
DROP VIEW IF EXISTS v_contracts_asof;
DROP VIEW IF EXISTS v_coaches_asof;
DROP VIEW IF EXISTS v_loans_asof;
DROP VIEW IF EXISTS v_role_tenures;
DROP VIEW IF EXISTS v_changes;
DROP VIEW IF EXISTS v_contracts_during_season;
DROP VIEW IF EXISTS v_coach_at_club;
DROP VIEW IF EXISTS v_monthly_changes;
DROP VIEW IF EXISTS v_contract_gaps;
DROP VIEW IF EXISTS v_loan_gaps;
DROP TABLE IF EXISTS query_params;

-- ============================================================================
-- query_params · parameter row for parameterised views
-- ----------------------------------------------------------------------------
-- Single row (param_id = 1 always). Default values give a reproducible
-- "end-of-timeline snapshot": state as of 2026-10-26, as known on 2026-10-26.
-- 05_tests.sql UPDATEs these before each parameterised test.
-- ============================================================================
CREATE TABLE query_params (
    param_id    INT          NOT NULL,
    valid_at    DATE         NOT NULL DEFAULT '2026-10-26',
    known_at    DATETIME(6)  NOT NULL DEFAULT '2026-10-26 00:00:00.000000',
    season_name VARCHAR(10)  NOT NULL DEFAULT '2025-26',
    PRIMARY KEY (param_id),
    CHECK (param_id = 1)
) ENGINE=InnoDB;

INSERT INTO query_params (param_id) VALUES (1);

-- ============================================================================
-- Q0 · v_integrity_violations
-- ----------------------------------------------------------------------------
-- Checks I1 (no VT overlap among currently-believed rows) across all three
-- bitemporal tables. Returns 0 rows when invariants hold.
-- Self-join trick: a.version_id < b.version_id avoids returning each pair twice.
-- ============================================================================
CREATE VIEW v_integrity_violations AS
SELECT 'contract_version' AS source_table,
       a.player_id AS business_key,
       a.version_id AS v1, b.version_id AS v2,
       a.valid_from AS a_from, a.valid_to AS a_to,
       b.valid_from AS b_from, b.valid_to AS b_to
  FROM contract_version a
  JOIN contract_version b
    ON a.player_id  = b.player_id
   AND a.version_id < b.version_id
   AND a.tx_to      = '9999-12-31 23:59:59.999999'
   AND b.tx_to      = '9999-12-31 23:59:59.999999'
   AND a.valid_from < b.valid_to
   AND b.valid_from < a.valid_to
 UNION ALL
SELECT 'head_coach_version',
       a.club_id,
       a.version_id, b.version_id,
       a.valid_from, a.valid_to,
       b.valid_from, b.valid_to
  FROM head_coach_version a
  JOIN head_coach_version b
    ON a.club_id    = b.club_id
   AND a.version_id < b.version_id
   AND a.tx_to      = '9999-12-31 23:59:59.999999'
   AND b.tx_to      = '9999-12-31 23:59:59.999999'
   AND a.valid_from < b.valid_to
   AND b.valid_from < a.valid_to
 UNION ALL
SELECT 'loan_version',
       a.player_id,
       a.version_id, b.version_id,
       a.valid_from, a.valid_to,
       b.valid_from, b.valid_to
  FROM loan_version a
  JOIN loan_version b
    ON a.player_id  = b.player_id
   AND a.version_id < b.version_id
   AND a.tx_to      = '9999-12-31 23:59:59.999999'
   AND b.tx_to      = '9999-12-31 23:59:59.999999'
   AND a.valid_from < b.valid_to
   AND b.valid_from < a.valid_to;

-- ============================================================================
-- Q1 / Q5 · v_contracts_asof, v_coaches_asof, v_loans_asof
-- ----------------------------------------------------------------------------
-- Parameterised "state at valid_at, as known on known_at".
-- Q1 = call with query_params set to today's date.
-- Q5 = call with query_params set to any past/future (valid_at, known_at) pair.
-- The two bitemporal predicates:
--   valid at V:    valid_from <= V AND V < valid_to
--   known at T:    tx_from   <= T AND T < tx_to
-- Both half-open.
-- ============================================================================
CREATE VIEW v_contracts_asof AS
SELECT q.valid_at, q.known_at,
       cv.player_id, p.first_name, p.last_name,
       cv.club_id,   cl.name AS club_name,
       cv.salary_eur,
       cv.valid_from, cv.valid_to
  FROM contract_version cv
  CROSS JOIN query_params q
  JOIN player p ON p.player_id = cv.player_id
  JOIN club   cl ON cl.club_id = cv.club_id
 WHERE cv.tx_from    <= q.known_at AND q.known_at <  cv.tx_to
   AND cv.valid_from <= q.valid_at AND q.valid_at <  cv.valid_to;

CREATE VIEW v_coaches_asof AS
SELECT q.valid_at, q.known_at,
       hc.club_id, cl.name AS club_name,
       hc.coach_id, c.first_name, c.last_name,
       hc.valid_from, hc.valid_to
  FROM head_coach_version hc
  CROSS JOIN query_params q
  JOIN coach c  ON c.coach_id = hc.coach_id
  JOIN club  cl ON cl.club_id = hc.club_id
 WHERE hc.tx_from    <= q.known_at AND q.known_at <  hc.tx_to
   AND hc.valid_from <= q.valid_at AND q.valid_at <  hc.valid_to;

CREATE VIEW v_loans_asof AS
SELECT q.valid_at, q.known_at,
       lv.player_id,     p.last_name,
       lv.from_club_id,  cf.name AS from_club,
       lv.to_club_id,    ct.name AS to_club,
       lv.valid_from, lv.valid_to
  FROM loan_version lv
  CROSS JOIN query_params q
  JOIN player p  ON p.player_id = lv.player_id
  JOIN club   cf ON cf.club_id = lv.from_club_id
  JOIN club   ct ON ct.club_id = lv.to_club_id
 WHERE lv.tx_from    <= q.known_at AND q.known_at <  lv.tx_to
   AND lv.valid_from <= q.valid_at AND q.valid_at <  lv.valid_to;

-- ============================================================================
-- Q2 · v_role_tenures
-- ----------------------------------------------------------------------------
-- Coalesces currently-believed head_coach_version rows into (club, coach)
-- tenures. Each coach's time at a club spans from the earliest valid_from
-- to the latest valid_to among their TT-current rows.
--
-- SIMPLIFICATION: assumes each coach has at most one contiguous tenure per
-- club (no coach is sacked then re-hired). True for this dataset.
-- The general case would need a window-function or recursive gap-filling query.
-- ============================================================================
CREATE VIEW v_role_tenures AS
SELECT hc.club_id, cl.name AS club_name,
       hc.coach_id, c.first_name, c.last_name,
       MIN(hc.valid_from) AS tenure_from,
       MAX(hc.valid_to)   AS tenure_to
  FROM head_coach_version hc
  JOIN coach c  ON c.coach_id = hc.coach_id
  JOIN club  cl ON cl.club_id = hc.club_id
 WHERE hc.tx_to = '9999-12-31 23:59:59.999999'
 GROUP BY hc.club_id, cl.name, hc.coach_id, c.first_name, c.last_name;

-- ============================================================================
-- Q3 · v_changes
-- ----------------------------------------------------------------------------
-- Lists every version-row INSERT (excluding the E1 load) with:
--   * the tx_registry entry it belongs to (tx_id, reason)
--   * the first token of reason (tagged_as) to surface E2/E3/E4/.../E9 tags
--   * a data-signature classifier derived from valid_from vs tx_from:
--       E2 proactive        — valid_from is in the future vs tx_date
--       E3 late entry       — tx_date is >= 7 days after valid_from
--       contemporaneous     — same day (new fact entered on the day it starts)
-- ============================================================================
CREATE VIEW v_changes AS
SELECT t.tx_id, t.tx_time, t.reason,
       SUBSTRING_INDEX(t.reason, ' ', 1) AS tagged_as,
       'contract' AS tbl,
       v.player_id AS entity_id,
       v.valid_from,
       DATE(v.tx_from) AS tx_date,
       DATEDIFF(v.valid_from, DATE(v.tx_from)) AS vt_minus_tt_days,
       CASE
         WHEN v.valid_from > DATE(v.tx_from)              THEN 'E2 proactive'
         WHEN DATEDIFF(DATE(v.tx_from), v.valid_from) >= 7 THEN 'E3 late entry'
         ELSE 'contemporaneous'
       END AS signature
  FROM contract_version v
  JOIN tx_registry t ON t.tx_id = v.tx_id
 WHERE t.tx_id > 1
 UNION ALL
SELECT t.tx_id, t.tx_time, t.reason,
       SUBSTRING_INDEX(t.reason, ' ', 1),
       'head_coach',
       v.club_id,
       v.valid_from, DATE(v.tx_from),
       DATEDIFF(v.valid_from, DATE(v.tx_from)),
       CASE
         WHEN v.valid_from > DATE(v.tx_from)              THEN 'E2 proactive'
         WHEN DATEDIFF(DATE(v.tx_from), v.valid_from) >= 7 THEN 'E3 late entry'
         ELSE 'contemporaneous'
       END
  FROM head_coach_version v
  JOIN tx_registry t ON t.tx_id = v.tx_id
 WHERE t.tx_id > 1
 UNION ALL
SELECT t.tx_id, t.tx_time, t.reason,
       SUBSTRING_INDEX(t.reason, ' ', 1),
       'loan',
       v.player_id,
       v.valid_from, DATE(v.tx_from),
       DATEDIFF(v.valid_from, DATE(v.tx_from)),
       CASE
         WHEN v.valid_from > DATE(v.tx_from)              THEN 'E2 proactive'
         WHEN DATEDIFF(DATE(v.tx_from), v.valid_from) >= 7 THEN 'E3 late entry'
         ELSE 'contemporaneous'
       END
  FROM loan_version v
  JOIN tx_registry t ON t.tx_id = v.tx_id
 WHERE t.tx_id > 1;

-- ============================================================================
-- Q4 · v_contracts_during_season
-- ----------------------------------------------------------------------------
-- Currently-believed contracts whose valid period overlaps a named season
-- (from the reference `season` table). Overlap test is the standard
-- half-open rectangle overlap: a_from < b_to AND b_from < a_to.
--
-- Filter in 05_tests: WHERE season_name = '2025-26' or '2024-25'.
-- ============================================================================
CREATE VIEW v_contracts_during_season AS
SELECT s.name AS season_name,
       s.start_date AS season_start, s.end_date AS season_end,
       cv.player_id, p.last_name,
       cv.club_id,   cl.name AS club_name,
       cv.salary_eur,
       cv.valid_from, cv.valid_to
  FROM season s
  JOIN contract_version cv
    ON cv.valid_from < s.end_date
   AND s.start_date  < cv.valid_to
  JOIN player p ON p.player_id = cv.player_id
  JOIN club   cl ON cl.club_id = cv.club_id
 WHERE cv.tx_to = '9999-12-31 23:59:59.999999';

-- ============================================================================
-- Q6 · v_coach_at_club
-- ----------------------------------------------------------------------------
-- THE three-answer view. Parameterised by query_params.{valid_at, known_at}.
-- Filter with WHERE club_id = <N> after SELECT.
--
-- Reproduces the Chelsea story: with valid_at = '2026-02-03' and three
-- different known_at values (2026-02-10, 2026-02-17, 2026-10-01), returns
-- three different coaches for Chelsea (club_id = 5):
--   Whittaker (before late entry), Delaney (after late entry, before
--   correction), Whittaker (after correction).
-- ============================================================================
CREATE VIEW v_coach_at_club AS
SELECT q.valid_at, q.known_at,
       hc.club_id, cl.name AS club_name,
       hc.coach_id,
       CONCAT(c.first_name, ' ', c.last_name) AS coach_name,
       hc.valid_from, hc.valid_to,
       hc.tx_from,    hc.tx_to
  FROM head_coach_version hc
  CROSS JOIN query_params q
  JOIN coach c  ON c.coach_id = hc.coach_id
  JOIN club  cl ON cl.club_id = hc.club_id
 WHERE hc.tx_from    <= q.known_at AND q.known_at <  hc.tx_to
   AND hc.valid_from <= q.valid_at AND q.valid_at <  hc.valid_to;

-- ============================================================================
-- Q7 · v_monthly_changes
-- ----------------------------------------------------------------------------
-- Transaction-time histogram: how many `tx_registry` entries landed per month.
-- Useful for the report's "when did changes come in" chart.
-- ============================================================================
CREATE VIEW v_monthly_changes AS
SELECT DATE_FORMAT(tx_time, '%Y-%m') AS tx_month,
       COUNT(*) AS tx_count
  FROM tx_registry
 GROUP BY tx_month
 ORDER BY tx_month;

-- ============================================================================
-- Q8 · v_contract_gaps, v_loan_gaps
-- ----------------------------------------------------------------------------
-- Detects E6 restart patterns: two currently-believed rows for the same
-- business key with a strict gap between them in valid time.
-- Business keys (per schema design decision):
--   contracts: (player_id, club_id)
--   loans:     (player_id, from_club_id, to_club_id)
-- Two loans by the same player to DIFFERENT clubs are not a restart.
-- Expected hits in this dataset:
--   v_contract_gaps: Fletcher (21, 3), Ashworth (2, 1), Jansen (23, 3)
--   v_loan_gaps:     Thornton (16, 2, 4)
-- ============================================================================
CREATE VIEW v_contract_gaps AS
SELECT a.player_id, p.last_name,
       a.club_id,   cl.name AS club_name,
       a.valid_from AS period1_from, a.valid_to AS period1_to,
       b.valid_from AS period2_from, b.valid_to AS period2_to,
       DATEDIFF(b.valid_from, a.valid_to) AS gap_days
  FROM contract_version a
  JOIN contract_version b
    ON a.player_id = b.player_id
   AND a.club_id   = b.club_id
   AND a.valid_to  < b.valid_from
  JOIN player p ON p.player_id = a.player_id
  JOIN club   cl ON cl.club_id = a.club_id
 WHERE a.tx_to = '9999-12-31 23:59:59.999999'
   AND b.tx_to = '9999-12-31 23:59:59.999999';

CREATE VIEW v_loan_gaps AS
SELECT a.player_id, p.last_name,
       a.from_club_id, cf.name AS from_club,
       a.to_club_id,   ct.name AS to_club,
       a.valid_from AS period1_from, a.valid_to AS period1_to,
       b.valid_from AS period2_from, b.valid_to AS period2_to,
       DATEDIFF(b.valid_from, a.valid_to) AS gap_days
  FROM loan_version a
  JOIN loan_version b
    ON a.player_id    = b.player_id
   AND a.from_club_id = b.from_club_id
   AND a.to_club_id   = b.to_club_id
   AND a.valid_to     < b.valid_from
  JOIN player p  ON p.player_id = a.player_id
  JOIN club   cf ON cf.club_id = a.from_club_id
  JOIN club   ct ON ct.club_id = a.to_club_id
 WHERE a.tx_to = '9999-12-31 23:59:59.999999'
   AND b.tx_to = '9999-12-31 23:59:59.999999';

-- Restore defaults.
UPDATE query_params
   SET valid_at = '2026-10-26',
       known_at = '2026-10-26 00:00:00.000000',
       season_name = '2025-26';
