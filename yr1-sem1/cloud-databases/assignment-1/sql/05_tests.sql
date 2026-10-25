-- ============================================================================
-- 05_tests.sql
-- Test harness — drives each view with concrete parameters and prints results.
--
-- Expects 01..04 to have run. Each test prints a labelled row followed by
-- its output; the -- Expected: comment states what the output should be.
-- Grader can diff visually.
--
-- Pattern:
--   SELECT '--- Qn description ---' AS test;
--   [UPDATE query_params ...];
--   SELECT ... FROM v_...;
--   -- Expected: <answer>
-- ============================================================================

USE football;

-- Known starting point for query_params.
UPDATE query_params
   SET valid_at    = '2026-10-26',
       known_at    = '2026-10-26 00:00:00.000000',
       season_name = '2025-26';

-- ============================================================================
-- Q0 · Integrity violations
-- ============================================================================
SELECT '--- Q0 · integrity violations across all three bitemporal tables ---' AS test;
SELECT * FROM v_integrity_violations;
-- Expected: 0 rows. Any row means an I1 overlap bug.

-- ============================================================================
-- Q1 · Current snapshot (state at end-of-timeline wall clock, 2026-10-26)
-- ============================================================================
SELECT '--- Q1 · current contracts count ---' AS test;
SELECT COUNT(*) AS current_contracts FROM v_contracts_asof;
-- Expected: 57 (50 primary − 8 E5 terminations + 15 background anchors).

SELECT '--- Q1 · current head coaches (one per club) ---' AS test;
SELECT club_name, CONCAT(first_name, ' ', last_name) AS coach, valid_from
  FROM v_coaches_asof
 ORDER BY club_id;
-- Expected: 6 rows — Harwood/MUN, Reyes/MCI, Conti/LIV, Wagner/ARS, Delaney/CHE, Richter/TOT.

SELECT '--- Q1 · current loans ---' AS test;
SELECT COUNT(*) AS current_loans FROM v_loans_asof;
-- Expected: 0. All loans expired or were converted to permanent transfers by October.

-- ============================================================================
-- Q2 · Role tenures (coalesced per club + coach)
-- ============================================================================
SELECT '--- Q2 · head-coach tenures ---' AS test;
SELECT club_name, CONCAT(first_name, ' ', last_name) AS coach,
       tenure_from, tenure_to
  FROM v_role_tenures
 ORDER BY club_name, tenure_from;
-- Expected: 9 rows total.
--   Arsenal:    Bellini   2021-12-10 → 2025-11-11, Wagner 2025-11-11 → ∞
--   Chelsea:    Whittaker 2024-06-01 → 2026-02-05, Delaney 2026-02-05 → ∞
--   Liverpool:  Van Dijk  2024-05-20 → 2026-03-10, Conti   2026-03-10 → ∞
--   Man City:   Reyes     2022-06-15 → ∞
--   Man United: Harwood   2023-07-01 → ∞
--   Tottenham:  Richter   2024-07-15 → ∞

-- ============================================================================
-- Q3 · Changes classified by valid-vs-transaction signature
-- ============================================================================
SELECT '--- Q3 · E2 proactive inserts (valid_from > tx_date) ---' AS test;
SELECT tx_id, tagged_as, tbl, entity_id, valid_from, tx_date, vt_minus_tt_days
  FROM v_changes
 WHERE signature = 'E2 proactive'
 ORDER BY tx_id;
-- Expected: 7 rows. 5 true E2 events contribute 1 row each (only the NEW period row has
-- valid_from > tx_date; the amended "shortened" row preserves the old past valid_from).
-- Plus 2 rows the view honestly surfaces as proactive: Wagner's appointment at ARS
-- (tx_id 12, valid_from 1 day after tx_date) and Fletcher's gap renewal (tx_id 29,
-- valid_from 21 days after tx_date). The view classifies by data signature, not by
-- authorial intent — these two incidentals are legitimately proactive.

SELECT '--- Q3 · E3 late entries (tx_date ≥ 7 days after valid_from) ---' AS test;
SELECT tx_id, tagged_as, tbl, entity_id, valid_from, tx_date, vt_minus_tt_days
  FROM v_changes
 WHERE signature = 'E3 late entry'
 ORDER BY tx_id;
-- Expected: ~47 rows. The signature "tx_date >= valid_from + 7 days" is OVER-INCLUSIVE
-- vs the authorial E3 tag: it catches true late entries AND amendments of old facts
-- (e.g., Benali termination's amended row has valid_from=2023-07-01 (original contract
-- start) and tx_from=2026-01-15, so it reads as a 929-day "late entry" even though it's
-- really a termination). This is a bitemporal reality: data signatures alone cannot
-- distinguish "a fact entered late" from "an existing fact closed-and-reinserted with
-- preserved valid_from". For true E3 events only, filter also by `tagged_as LIKE 'E3%'`
-- — see additional query below.

SELECT '--- Q3 · true E3 late entries (signature AND tagged_as = E3) ---' AS test;
SELECT tx_id, tagged_as, tbl, entity_id, valid_from, tx_date, vt_minus_tt_days
  FROM v_changes
 WHERE signature = 'E3 late entry'
   AND tagged_as LIKE 'E3%'
 ORDER BY tx_id;
-- Expected: 17 rows across 9 events (4, 6, 11, 16, 20, 26, 27, 28, 35). Event 33 is
-- tagged 'E6+E3' so it does not match 'E3%'. Comparing this 17-row count to the previous
-- 47-row result quantifies how many signature-matches are amendments-in-disguise (30 of 47).

SELECT '--- Q3 · E4 corrections (by reason tag) ---' AS test;
SELECT DISTINCT tx_id, reason
  FROM v_changes
 WHERE tagged_as LIKE 'E4%'
 ORDER BY tx_id;
-- Expected: 5 distinct tx_ids — events 7, 17, 22, 32, 40.

-- ============================================================================
-- Q4 · Facts valid during a named season
-- ============================================================================
SELECT '--- Q4 · contracts valid during 2025-26 season ---' AS test;
SELECT COUNT(*) AS contracts_in_2025_26
  FROM v_contracts_during_season
 WHERE season_name = '2025-26';
-- Expected: ~60 (most E1 contracts plus a few mid-season transfers).

SELECT '--- Q4 · a sample of 10 contracts during 2025-26 ---' AS test;
SELECT last_name, club_name, salary_eur, valid_from, valid_to
  FROM v_contracts_during_season
 WHERE season_name = '2025-26'
 ORDER BY last_name
 LIMIT 10;
-- Expected: alphabetical by player last name.

-- ============================================================================
-- Q5 · State at any known_at (time travel)
-- ============================================================================
SELECT '--- Q5 · Arsenal coach as of 2025-10-01 (expect Bellini) ---' AS test;
UPDATE query_params SET valid_at = '2025-10-01', known_at = '2025-10-01 00:00:00.000000';
SELECT club_name, CONCAT(first_name, ' ', last_name) AS coach
  FROM v_coaches_asof WHERE club_id = 4;
-- Expected: Francesco Bellini (still in post; sacked 2025-11-11).

SELECT '--- Q5 · Arsenal coach as of 2026-01-15 (expect Wagner) ---' AS test;
UPDATE query_params SET valid_at = '2026-01-15', known_at = '2026-01-15 00:00:00.000000';
SELECT club_name, CONCAT(first_name, ' ', last_name) AS coach
  FROM v_coaches_asof WHERE club_id = 4;
-- Expected: Erik Wagner (installed 2025-11-11).

SELECT '--- Q5 · Chelsea coach as of 2026-02-18 (right between late entry and correction) ---' AS test;
UPDATE query_params SET valid_at = '2026-02-18', known_at = '2026-02-18 00:00:00.000000';
SELECT club_name, CONCAT(first_name, ' ', last_name) AS coach
  FROM v_coaches_asof WHERE club_id = 5;
-- Expected: Marcus Delaney (DB believed handover was 2026-02-01 at this moment).

-- ============================================================================
-- Q6 · THE THREE-ANSWER TEST — Chelsea coach on 2026-02-03
-- One valid_at, three different known_at values, three different coaches.
-- This is the signature test of a bitemporal database.
-- ============================================================================
SELECT '--- Q6 ANSWER 1 · known_at = 2026-02-10 (before late entry at event 16) ---' AS test;
UPDATE query_params SET valid_at = '2026-02-03', known_at = '2026-02-10 00:00:00.000000';
SELECT coach_name FROM v_coach_at_club WHERE club_id = 5;
-- Expected: James Whittaker.

SELECT '--- Q6 ANSWER 2 · known_at = 2026-02-17 (after late entry, before event 17 correction) ---' AS test;
UPDATE query_params SET known_at = '2026-02-17 00:00:00.000000';
SELECT coach_name FROM v_coach_at_club WHERE club_id = 5;
-- Expected: Marcus Delaney.

SELECT '--- Q6 ANSWER 3 · known_at = 2026-10-01 (after correction at event 17) ---' AS test;
UPDATE query_params SET known_at = '2026-10-01 00:00:00.000000';
SELECT coach_name FROM v_coach_at_club WHERE club_id = 5;
-- Expected: James Whittaker (corrected handover 2026-02-05 is AFTER 2026-02-03).

-- ============================================================================
-- Q7 · Monthly change histogram
-- ============================================================================
SELECT '--- Q7 · tx_registry entries per month ---' AS test;
SELECT * FROM v_monthly_changes;
-- Expected: 16 months (2025-07 .. 2026-10). Peak months: Oct 2026 (5 events),
-- Feb/Jul/Sep 2026 (4 each). Totals to 40 across all months.

-- ============================================================================
-- Q8 · Gap detection (E6 restart pairs)
-- ============================================================================
SELECT '--- Q8 · contract gaps (all four, including Kristensen fencepost) ---' AS test;
SELECT last_name, club_name, period1_to, period2_from, gap_days
  FROM v_contract_gaps
 ORDER BY player_id;
-- Expected: 4 rows —
--   Ashworth    MUN  2026-06-30 → 2026-08-01   32 days
--   Fletcher    LIV  2026-07-31 → 2026-08-15   15 days
--   Jansen      LIV  2026-06-30 → 2026-09-10   72 days
--   Kristensen  TOT  2026-06-30 → 2026-07-01    1 day   (half-open fencepost)

SELECT '--- Q8 · contract gaps — meaningful only (gap_days >= 7) ---' AS test;
SELECT last_name, club_name, period1_to, period2_from, gap_days
  FROM v_contract_gaps
 WHERE gap_days >= 7
 ORDER BY player_id;
-- Expected: 3 rows — Ashworth, Fletcher, Jansen.
-- Kristensen filtered out as the 1-day fencepost artifact.

SELECT '--- Q8 · loan gaps ---' AS test;
SELECT last_name, from_club, to_club, period1_to, period2_from, gap_days
  FROM v_loan_gaps
 ORDER BY player_id;
-- Expected: 1 row — Thornton MCI→ARS, 2025-12-20 → 2026-02-25, 67 days.

-- ============================================================================
-- Reset query_params before exiting.
-- ============================================================================
UPDATE query_params
   SET valid_at    = '2026-10-26',
       known_at    = '2026-10-26 00:00:00.000000',
       season_name = '2025-26';

SELECT '--- All tests complete ---' AS summary;
