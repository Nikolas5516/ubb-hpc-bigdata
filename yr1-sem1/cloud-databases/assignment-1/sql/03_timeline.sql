-- ============================================================================
-- 03_timeline.sql
-- Events E2..E9 — Timeline replay (events 2 through 40)
--
-- Expects 01_schema.sql and 02_data.sql to have run already.
-- The 40-event story from story-log.md, translated event-by-event.
-- Each event is one `tx_registry` entry, one BEGIN/COMMIT transaction,
-- one @sim_now value shared by every statement in it (so all rows written
-- in one event share the same tx_from — the "one change, one timestamp" rule).
--
-- Pattern per event:
--   SET @sim_now = '...';
--   START TRANSACTION;
--     INSERT INTO tx_registry (...) VALUES (@sim_now, author, 'EN label');
--     SET @tx = LAST_INSERT_ID();
--     [UPDATE ... SET tx_to = @sim_now WHERE ... AND tx_to = @ts_sentinel;]  -- close TT first
--     [INSERT INTO ... VALUES (..., @sim_now, @tx);]                         -- then new rows
--   COMMIT;
--
-- TT-close before any INSERT means no intermediate state ever violates I1
-- (no two currently-believed rows ever share a business key with overlapping
-- valid periods, because the old rows are already closed in TT by the time
-- the new ones go in).
-- ============================================================================

-- Sentinel for "still believed" / "still valid". Used in every UPDATE's WHERE.
SET @ts_sentinel = '9999-12-31 23:59:59.999999';

-- ============================================================================
-- SECTION 1 · SUMMER 2025 — opening transfer window + early season
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Event 2 · [E2] Pennington contract extension (Manchester United)
-- ----------------------------------------------------------------------------
-- Proactive: salary €8M -> €10M effective 2026-07-01, contract to 2028-06-30.
-- valid_from (2026-07-01) > tx_from (2025-07-05) — 361 days ahead.
-- Writes: close current MUN contract TT, insert amended (€8M, valid_to=2026-07-01),
--         insert new period (€10M, valid [2026-07-01, 2028-06-30)).
-- Rows: 2 new in contract_version.
SET @sim_now = '2025-07-05 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E2 Pennington extension at MUN (eff 2026-07-01)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version
   SET tx_to = @sim_now
 WHERE player_id = 1 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (1, 1,  8000000, '2023-07-01', '2026-07-01', @sim_now, @tx),
  (1, 1, 10000000, '2026-07-01', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 3 · [E9] Pierce permanent transfer Arsenal -> Chelsea
-- ----------------------------------------------------------------------------
-- Chelsea converts Pierce's loan into a permanent move, effective 2025-08-05.
-- Writes:
--   contract: close ARS TT, insert amended ARS [2024-07-01, 2025-08-05) @ €2M,
--             insert new CHE [2025-08-05, 2028-06-30) @ €3M
--   loan:     close ARS->CHE TT, insert amended loan [2024-08-15, 2025-08-05)
-- Rows: 3 new (2 in contract_version, 1 in loan_version). E9: 2 tables, 1 tx_id.
SET @sim_now = '2025-08-05 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_registrar', 'E9 Pierce permanent ARS->CHE (converts loan)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 32 AND tx_to = @ts_sentinel;
UPDATE loan_version     SET tx_to = @sim_now WHERE player_id = 32 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (32, 4, 2000000, '2024-07-01', '2025-08-05', @sim_now, @tx),
  (32, 5, 3000000, '2025-08-05', '2028-06-30', @sim_now, @tx);

INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (32, 4, 5, '2024-08-15', '2025-08-05', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 4 · [E3] Mendoza transfer Manchester City -> Chelsea (19 days late)
-- ----------------------------------------------------------------------------
-- Transfer registered 2025-08-20, actual date 2025-08-01. 19-day late entry.
-- Rows: 2 new in contract_version.
SET @sim_now = '2025-08-20 14:30:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_registrar', 'E3 Mendoza MCI->CHE (19d late, actual 2025-08-01)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 11 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (11, 2, 15000000, '2022-07-01', '2025-08-01', @sim_now, @tx),
  (11, 5, 14000000, '2025-08-01', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 5 · [E2] Girard salary rise (Arsenal)
-- ----------------------------------------------------------------------------
-- Proactive: €9M -> €11M effective 2026-01-01, 122 days ahead.
-- NOTE: salary value corrected to €10.5M in event 22.
-- Rows: 2 new in contract_version.
SET @sim_now = '2025-09-01 09:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E2 Girard salary rise at ARS (eff 2026-01-01)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 27 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (27, 4,  9000000, '2023-07-01', '2026-01-01', @sim_now, @tx),
  (27, 4, 11000000, '2026-01-01', '2027-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 6 · [E3] Ashworth loan Manchester United -> Tottenham (16 days late)
-- ----------------------------------------------------------------------------
-- Loan actual start 2025-08-25, registered 2025-09-10 (16d late).
-- No existing loan for Ashworth to close — pure INSERT.
-- Parent MUN contract NOT closed (loans don't close parent contracts).
-- Rows: 1 new in loan_version.
SET @sim_now = '2025-09-10 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 Ashworth loan MUN->TOT (16d late, actual 2025-08-25)');
SET @tx = LAST_INSERT_ID();

INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (2, 1, 6, '2025-08-25', '2026-05-31', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 7 · [E4] Correction: Mendoza transfer actual date 2025-07-30 (not 2025-08-01)
-- ----------------------------------------------------------------------------
-- Correcting event 4. Both Mendoza rows share the 2025-08-01 boundary, so both
-- are affected: amended MCI gets new valid_to=2025-07-30, new CHE gets new
-- valid_from=2025-07-30.
-- Rows: 2 new in contract_version.
SET @sim_now = '2025-09-25 15:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'audit', 'E4 correction: Mendoza actual date 2025-07-30');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 11 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (11, 2, 15000000, '2022-07-01', '2025-07-30', @sim_now, @tx),
  (11, 5, 14000000, '2025-07-30', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 8 · Al-Rashid "loan" ARS -> LIV (ERRONEOUS — setup for E8)
-- ----------------------------------------------------------------------------
-- Clerk mistakenly enters a loan that never happened. Will be retracted in event 9.
-- Rows: 1 new in loan_version (erroneous, retracted next event).
SET @sim_now = '2025-09-30 09:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'erroneous entry: Al-Rashid loan ARS->LIV (never happened)');
SET @tx = LAST_INSERT_ID();

INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (31, 4, 3, '2025-09-15', '2026-01-15', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 9 · [E8] Retract Al-Rashid "loan"
-- ----------------------------------------------------------------------------
-- Verification shows the loan never happened. Close event 8's row TT only.
-- No new row — this is the defining signature of E8.
-- Rows: 0 new (TT-close only).
SET @sim_now = '2025-10-05 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'audit', 'E8 retract Al-Rashid loan (data entry error, event 8)');
SET @tx = LAST_INSERT_ID();

UPDATE loan_version SET tx_to = @sim_now WHERE player_id = 31 AND tx_to = @ts_sentinel;

COMMIT;

-- ============================================================================
-- SECTION 2 · AUTUMN 2025
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Event 10 · [E5 + E9] Reeves permanent transfer Manchester United -> Tottenham
-- ----------------------------------------------------------------------------
-- TOT buys Reeves outright, converting his loan into a permanent move.
-- Writes:
--   contract: close MUN TT, insert amended MUN [2024-07-01, 2025-10-20),
--             insert new TOT [2025-10-20, 2027-06-30) @ €2.5M
--   loan:     close MUN->TOT loan TT, insert amended loan [2025-01-15, 2025-10-20)
-- Rows: 3 new. E5+E9: ends current fact AND touches two tables.
SET @sim_now = '2025-10-20 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_registrar', 'E5+E9 Reeves permanent MUN->TOT (converts loan)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 9 AND tx_to = @ts_sentinel;
UPDATE loan_version     SET tx_to = @sim_now WHERE player_id = 9 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (9, 1, 1500000, '2024-07-01', '2025-10-20', @sim_now, @tx),
  (9, 6, 2500000, '2025-10-20', '2027-06-30', @sim_now, @tx);

INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (9, 1, 6, '2025-01-15', '2025-10-20', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 11 · [E3] Bradley transfer Liverpool -> Tottenham (15 days late)
-- ----------------------------------------------------------------------------
-- Transfer actual 2025-10-10, registered 2025-10-25. Salary €8M.
-- NOTE: salary corrected to €7.5M in event 32.
-- Rows: 2 new in contract_version.
SET @sim_now = '2025-10-25 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_registrar', 'E3 Bradley LIV->TOT (15d late, actual 2025-10-10)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 26 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (26, 3, 7000000, '2023-07-01', '2025-10-10', @sim_now, @tx),
  (26, 6, 8000000, '2025-10-10', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 12 · [E7] Bellini sacked at Arsenal, Erik Wagner appointed
-- ----------------------------------------------------------------------------
-- Insert new coach anchor (Wagner), then swap head coach at ARS.
-- Rows: 2 new in head_coach_version + 1 new coach anchor (coach_id 8).
SET @sim_now = '2025-11-10 12:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E7 Bellini sacked at ARS, Wagner appointed (eff 2025-11-11)');
SET @tx = LAST_INSERT_ID();

INSERT INTO coach (first_name, last_name, birth_date, nationality)
VALUES ('Erik', 'Wagner', '1973-08-22', 'German');
SET @wagner_id = LAST_INSERT_ID();

UPDATE head_coach_version SET tx_to = @sim_now WHERE club_id = 4 AND tx_to = @ts_sentinel;

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (4, 4, '2021-12-10', '2025-11-11', @sim_now, @tx);

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, tx_from, tx_id) VALUES
  (4, @wagner_id, '2025-11-11', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 13 · [E5] Thornton loan recalled early (Manchester City)
-- ----------------------------------------------------------------------------
-- MCI injury crisis — loan ends 2025-12-20 instead of original 2026-01-31.
-- Amended row preserves original valid_from=2025-02-01 from E1; only valid_to changes.
-- Rows: 1 new in loan_version.
SET @sim_now = '2025-12-20 14:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Thornton loan recall (injury crisis at MCI)');
SET @tx = LAST_INSERT_ID();

UPDATE loan_version SET tx_to = @sim_now WHERE player_id = 16 AND tx_to = @ts_sentinel;

INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (16, 2, 4, '2025-02-01', '2025-12-20', @sim_now, @tx);

COMMIT;

-- ============================================================================
-- SECTION 3 · WINTER / SPRING 2026
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Event 14 · [E5] Benali contract terminated (Manchester United)
-- ----------------------------------------------------------------------------
-- Mutual termination 2026-01-15. Original contract ran to 2027-06-30.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-01-15 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Benali contract terminated at MUN (mutual)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 8 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (8, 1, 4000000, '2023-07-01', '2026-01-15', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 15 · [E2] Hartley salary bump (Arsenal)
-- ----------------------------------------------------------------------------
-- Proactive: €6M -> €7M effective 2026-07-01, 150 days ahead.
-- Rows: 2 new in contract_version.
SET @sim_now = '2026-02-01 09:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E2 Hartley salary bump at ARS (eff 2026-07-01)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 29 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (29, 4, 6000000, '2023-01-15', '2026-07-01', @sim_now, @tx),
  (29, 4, 7000000, '2026-07-01', '2026-12-31', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 16 · [E3 + E7] Delaney appointment at Chelsea — late entry
-- ----------------------------------------------------------------------------
-- THREE-ANSWER STORY PART 1. Clerk records on 2026-02-15 that Delaney took over
-- 2026-02-01 (14 days late). This belief will be corrected in event 17.
-- Rows: 2 new in head_coach_version.
SET @sim_now = '2026-02-15 14:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3+E7 Delaney appointment at CHE (14d late, actual 2026-02-01)');
SET @tx = LAST_INSERT_ID();

UPDATE head_coach_version SET tx_to = @sim_now WHERE club_id = 5 AND tx_to = @ts_sentinel;

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (5, 5, '2024-06-01', '2026-02-01', @sim_now, @tx);

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, tx_from, tx_id) VALUES
  (5, 7, '2026-02-01', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 17 · [E4 + E7] Correction: Chelsea handover was 2026-02-05
-- ----------------------------------------------------------------------------
-- THREE-ANSWER STORY PART 2. Corrects event 16: both rows (amended Whittaker +
-- Delaney) share the 2026-02-01 boundary, so both are affected.
-- Rows: 2 new in head_coach_version.
SET @sim_now = '2026-02-20 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'audit', 'E4+E7 correction: CHE handover 2026-02-05 (not 2026-02-01)');
SET @tx = LAST_INSERT_ID();

UPDATE head_coach_version SET tx_to = @sim_now WHERE club_id = 5 AND tx_to = @ts_sentinel;

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (5, 5, '2024-06-01', '2026-02-05', @sim_now, @tx);

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, tx_from, tx_id) VALUES
  (5, 7, '2026-02-05', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 18 · [E6] Thornton second loan Manchester City -> Arsenal
-- ----------------------------------------------------------------------------
-- Second loan spell. First loan ended early 2025-12-20 (event 13); gap of ~2 months.
-- Same (player, from_club, to_club) triple as the first loan -> E6 restart.
-- No current loan to close — pure INSERT.
-- Rows: 1 new in loan_version.
SET @sim_now = '2026-02-25 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_registrar', 'E6 Thornton second loan MCI->ARS (after 2-month gap)');
SET @tx = LAST_INSERT_ID();

INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (16, 2, 4, '2026-02-25', '2026-05-24', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 19 · [E7] Van Dijk resigns at Liverpool, Alessandro Conti appointed
-- ----------------------------------------------------------------------------
-- Insert new coach anchor (Conti), swap head coach at LIV.
-- Rows: 2 new in head_coach_version + 1 new coach anchor (coach_id 9).
SET @sim_now = '2026-03-10 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E7 Van Dijk resigns at LIV, Conti appointed');
SET @tx = LAST_INSERT_ID();

INSERT INTO coach (first_name, last_name, birth_date, nationality)
VALUES ('Alessandro', 'Conti', '1969-04-18', 'Italian');
SET @conti_id = LAST_INSERT_ID();

UPDATE head_coach_version SET tx_to = @sim_now WHERE club_id = 3 AND tx_to = @ts_sentinel;

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (3, 3,        '2024-05-20', '2026-03-10', @sim_now, @tx);

INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, tx_from, tx_id) VALUES
  (3, @conti_id, '2026-03-10', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 20 · [E3] Berger loan Chelsea -> Tottenham (16 days late)
-- ----------------------------------------------------------------------------
-- Loan actual 2026-03-20, registered 2026-04-05. No existing to close.
-- Rows: 1 new in loan_version.
SET @sim_now = '2026-04-05 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 Berger loan CHE->TOT (16d late, actual 2026-03-20)');
SET @tx = LAST_INSERT_ID();

INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (39, 5, 6, '2026-03-20', '2026-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 21 · [E5] Weber contract early termination (Arsenal)
-- ----------------------------------------------------------------------------
-- Mutual termination. Original contract ran to 2027-06-30.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-04-15 14:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Weber contract early termination at ARS');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 34 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (34, 4, 5000000, '2023-07-01', '2026-04-15', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 22 · [E4] Correction: Girard new salary was €10.5M, not €11M
-- ----------------------------------------------------------------------------
-- SURGICAL correction: only the post-2026-01-01 row (Row B) changes.
-- The pre-raise Girard row (Row A, €9M) is still correct, so we leave it alone.
-- WHERE clause narrows the TT-close to just the row with the new salary period.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-04-20 09:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'audit', 'E4 correction: Girard salary 10.5M (not 11M), event 5');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version
   SET tx_to = @sim_now
 WHERE player_id = 27 AND tx_to = @ts_sentinel AND valid_from = '2026-01-01';

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (27, 4, 10500000, '2026-01-01', '2027-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 23 · [E5] Hernandez contract terminated (Tottenham)
-- ----------------------------------------------------------------------------
-- Original contract ran to 2027-06-30.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-05-20 15:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Hernandez contract terminated at TOT');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 44 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (44, 6, 8000000, '2023-07-01', '2026-05-20', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 24 · [E2] Marsden extension (Chelsea)
-- ----------------------------------------------------------------------------
-- Proactive: extended to 2029-06-30, salary €8M -> €9.5M effective 2026-07-01.
-- NOTE: effective date corrected to 2026-07-15 in event 40.
-- Rows: 2 new in contract_version.
SET @sim_now = '2026-05-25 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E2 Marsden extension at CHE (eff 2026-07-01)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 35 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (35, 5, 8000000, '2023-07-01', '2026-07-01', @sim_now, @tx),
  (35, 5, 9500000, '2026-07-01', '2029-06-30', @sim_now, @tx);

COMMIT;

-- ============================================================================
-- SECTION 4 · SUMMER 2026 — end of 2025-26 season, start of 2026-27
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Event 25 · [E9] Berger permanent transfer Chelsea -> Tottenham
-- ----------------------------------------------------------------------------
-- TOT buys Berger outright 15 days before the loan would end naturally.
-- Writes:
--   contract: close CHE TT, amended CHE [2023-07-01, 2026-06-15),
--             new TOT [2026-06-15, 2029-06-30) @ €5M
--   loan:     close CHE->TOT loan TT, amended loan [2026-03-20, 2026-06-15)
-- Rows: 3 new. E9: two tables, one tx_id.
SET @sim_now = '2026-06-15 12:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_registrar', 'E9 Berger permanent CHE->TOT (converts loan)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 39 AND tx_to = @ts_sentinel;
UPDATE loan_version     SET tx_to = @sim_now WHERE player_id = 39 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (39, 5, 7000000, '2023-07-01', '2026-06-15', @sim_now, @tx),
  (39, 6, 5000000, '2026-06-15', '2029-06-30', @sim_now, @tx);

INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id) VALUES
  (39, 5, 6, '2026-03-20', '2026-06-15', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 26 · [E3] Kristensen renewal (Tottenham) — 9 days late
-- ----------------------------------------------------------------------------
-- Original contract expired 2026-06-30. Renewal effective 2026-07-01 at €6.5M,
-- registered 2026-07-10 (9 days late). Original E1 row left alone (its valid_to
-- is already 2026-06-30). Gap-free continuation.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-07-10 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 Kristensen renewal at TOT (9d late, eff 2026-07-01)');
SET @tx = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (46, 6, 6500000, '2026-07-01', '2027-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 27 · [E3] Bauer transfer Tottenham -> Arsenal (14 days late)
-- ----------------------------------------------------------------------------
-- Transfer actual 2026-07-01, registered 2026-07-15.
-- Rows: 2 new in contract_version.
SET @sim_now = '2026-07-15 09:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_registrar', 'E3 Bauer TOT->ARS (14d late, actual 2026-07-01)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 50 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (50, 6, 6000000, '2023-07-01', '2026-07-01', @sim_now, @tx),
  (50, 4, 5500000, '2026-07-01', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 28 · [E3] Doherty transfer Liverpool -> Manchester United (15 days late)
-- ----------------------------------------------------------------------------
-- Transfer actual 2026-07-05, registered 2026-07-20.
-- Rows: 2 new in contract_version.
SET @sim_now = '2026-07-20 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'league_registrar', 'E3 Doherty LIV->MUN (15d late, actual 2026-07-05)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 25 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (25, 3, 3000000, '2024-07-01', '2026-07-05', @sim_now, @tx),
  (25, 1, 4000000, '2026-07-05', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 29 · [E6] Fletcher new contract with gap (Liverpool)
-- ----------------------------------------------------------------------------
-- Original contract expired naturally 2026-07-31. New contract effective
-- 2026-08-15 at €10.5M after a 15-day gap. Same (player, club) pair, two valid
-- periods with a strict gap -> E6. Original row untouched.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-07-25 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E6 Fletcher new contract at LIV (eff 2026-08-15, after gap)');
SET @tx = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (21, 3, 10500000, '2026-08-15', '2029-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 30 · [E6] Ashworth re-signs with Manchester United (after gap)
-- ----------------------------------------------------------------------------
-- Original contract expired 2026-06-30. One-month gap, new 1-year deal from
-- 2026-08-01 at €5.5M. Same (player, club) pair with gap -> E6.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-08-01 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E6 Ashworth re-signs with MUN (eff 2026-08-01, after gap)');
SET @tx = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (2, 1, 5500000, '2026-08-01', '2027-07-31', @sim_now, @tx);

COMMIT;

-- ============================================================================
-- SECTION 5 · AUTUMN 2026 — current state
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Event 31 · [E5] Blackwood released (Liverpool)
-- ----------------------------------------------------------------------------
-- Original contract ran to 2027-06-30.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-08-10 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Blackwood released at LIV (mutual)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 19 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (19, 3, 8000000, '2023-07-01', '2026-08-10', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 32 · [E4] Correction: Bradley transfer salary was €7.5M (not €8M)
-- ----------------------------------------------------------------------------
-- SURGICAL correction: only the new TOT row (club_id=6) changes.
-- The amended LIV row from event 11 is still correct.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-09-01 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'audit', 'E4 correction: Bradley salary 7.5M (not 8M), event 11');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version
   SET tx_to = @sim_now
 WHERE player_id = 26 AND tx_to = @ts_sentinel AND club_id = 6;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (26, 6, 7500000, '2025-10-10', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 33 · [E6 + E3] Jansen gap renewal (Liverpool) — 10 days late
-- ----------------------------------------------------------------------------
-- E1 contract expired 2026-06-30. Renewal effective 2026-09-10 at €7M,
-- registered 2026-09-20 (10d late). ~72-day gap satisfies E6; the late entry
-- satisfies E3. Original E1 row untouched.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-09-20 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E6+E3 Jansen gap renewal at LIV (10d late, eff 2026-09-10)');
SET @tx = LAST_INSERT_ID();

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (23, 3, 7000000, '2026-09-10', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 34 · [E5] Dubois released (Liverpool)
-- ----------------------------------------------------------------------------
-- Original contract ran to 2028-06-30.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-09-25 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Dubois released at LIV');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 24 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (24, 3, 5000000, '2024-07-01', '2026-09-25', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 35 · [E3] Chelsea double salary adjustment (both 15 days late)
-- ----------------------------------------------------------------------------
-- Two salary adjustments for CHE players (Winters, Ferraro) in ONE tx_id,
-- both effective 2026-09-15 (15d late). For each player: close current TT,
-- insert amended period [old_from, 2026-09-15), insert new period at new salary.
-- Rows: 4 new in contract_version (2 per player).
SET @sim_now = '2026-09-30 12:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 CHE salary adjustments (Winters+Ferraro, 15d late, eff 2026-09-15)');
SET @tx = LAST_INSERT_ID();

-- Close current TT for both players
UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 37 AND tx_to = @ts_sentinel;
UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 38 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (37, 5,  6000000, '2024-01-01', '2026-09-15', @sim_now, @tx),   -- Winters amended
  (37, 5,  6500000, '2026-09-15', '2027-12-31', @sim_now, @tx),   -- Winters new period
  (38, 5,  9000000, '2023-07-01', '2026-09-15', @sim_now, @tx),   -- Ferraro amended
  (38, 5, 10000000, '2026-09-15', '2027-06-30', @sim_now, @tx);   -- Ferraro new period

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 36 · [E5] Villanueva released (Manchester City)
-- ----------------------------------------------------------------------------
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-10-02 09:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Villanueva released at MCI');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 18 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (18, 2, 11000000, '2023-07-01', '2026-10-02', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 37 · [E5] Winterberg released (Manchester City)
-- ----------------------------------------------------------------------------
-- Original contract ran to 2028-06-30.
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-10-10 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Winterberg released at MCI');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 12 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (12, 2, 10000000, '2024-01-01', '2026-10-10', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 38 · [E2] Moreau salary bump (Tottenham) — buffer event
-- ----------------------------------------------------------------------------
-- Proactive: €6M -> €7.5M effective 2027-01-01, 78 days ahead.
-- Rows: 2 new in contract_version.
SET @sim_now = '2026-10-15 10:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E2 Moreau salary bump at TOT (eff 2027-01-01)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 45 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (45, 6, 6000000, '2024-07-01', '2027-01-01', @sim_now, @tx),
  (45, 6, 7500000, '2027-01-01', '2028-06-30', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 39 · [E5] Lacroix released (Manchester City) — buffer event
-- ----------------------------------------------------------------------------
-- Rows: 1 new in contract_version.
SET @sim_now = '2026-10-20 11:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'club_admin', 'E5 Lacroix released at MCI');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 14 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (14, 2, 9000000, '2024-07-01', '2026-10-20', @sim_now, @tx);

COMMIT;

-- ----------------------------------------------------------------------------
-- Event 40 · [E4] Correction: Marsden extension effective date was 2026-07-15
-- ----------------------------------------------------------------------------
-- Both rows from event 24 share the 2026-07-01 boundary, so both are affected.
-- amended row's valid_to shifts 2026-07-01 -> 2026-07-15,
-- new period row's valid_from shifts 2026-07-01 -> 2026-07-15.
-- Rows: 2 new in contract_version.
SET @sim_now = '2026-10-25 09:00:00.000000';
START TRANSACTION;

INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'audit', 'E4 correction: Marsden extension eff 2026-07-15 (not 2026-07-01)');
SET @tx = LAST_INSERT_ID();

UPDATE contract_version SET tx_to = @sim_now WHERE player_id = 35 AND tx_to = @ts_sentinel;

INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id) VALUES
  (35, 5, 8000000, '2023-07-01', '2026-07-15', @sim_now, @tx),
  (35, 5, 9500000, '2026-07-15', '2029-06-30', @sim_now, @tx);

COMMIT;
