-- ============================================================================
-- 02_data.sql
-- Event E1 — Initial load (go-live snapshot)
--
-- Domain: English Premier League, 2025-26 season.
-- Clubs and stadiums are real; players and coaches are generated.
--
-- Expects an empty database after 01_schema.sql ran.
-- Everything inserted here shares ONE tx_id (rule 7: "one change, one timestamp").
--
-- Simulated clock pattern (assignment Part B): instead of CURRENT_TIMESTAMP(6),
-- every write takes its tx_from from @sim_now so transaction time looks like
-- it was written in the past. 03_timeline.sql advances @sim_now step by step.
--
-- Volume: 65 player anchors, 75 current relationship facts at go-live.
-- 50 is the assignment minimum; the extra 15 players (IDs 51–65) hold stable
-- contracts through the timeline window to keep the "current facts ≥ 60 today"
-- requirement comfortably met once the timeline closes out many E1 contracts.
-- ============================================================================

-- Simulated wall clock for E1.
SET @sim_now = '2025-07-01 09:00:00.000000';   -- go-live instant, UTC

-- ----------------------------------------------------------------------------
-- Open the E1 transaction in the registry.
-- Every version row inserted below will reference this tx_id.
-- ----------------------------------------------------------------------------
INSERT INTO tx_registry (tx_time, author, reason) VALUES
  (@sim_now, 'system', 'E1 initial load — EPL 2025-26 go-live snapshot');
SET @e1_tx_id = LAST_INSERT_ID();

-- ============================================================================
-- SECTION 1 · REFERENCE DATA
-- ============================================================================

-- Two seasons: covers > 12 months of valid time (Part B requirement).
INSERT INTO season (name, start_date, end_date) VALUES
  ('2024-25', '2024-08-16', '2025-05-25'),
  ('2025-26', '2025-08-15', '2026-05-24');

-- ============================================================================
-- SECTION 2 · ANCHORS
-- IDs are auto-assigned 1..N in insertion order (assumed below for FKs).
-- ============================================================================

-- Stadiums (6) — stadium_id 1..6
INSERT INTO stadium (name, city, capacity) VALUES
  ('Old Trafford',               'Manchester', 74310),   -- 1
  ('Etihad Stadium',             'Manchester', 53400),   -- 2
  ('Anfield',                    'Liverpool',  61276),   -- 3
  ('Emirates Stadium',           'London',     60704),   -- 4
  ('Stamford Bridge',            'London',     40173),   -- 5
  ('Tottenham Hotspur Stadium',  'London',     62850);   -- 6

-- Clubs (6) — club_id 1..6
INSERT INTO club (name, city, founded_year, home_stadium_id) VALUES
  ('Manchester United', 'Manchester', 1878, 1),   -- 1  MUN
  ('Manchester City',   'Manchester', 1880, 2),   -- 2  MCI
  ('Liverpool',         'Liverpool',  1892, 3),   -- 3  LIV
  ('Arsenal',           'London',     1886, 4),   -- 4  ARS
  ('Chelsea',           'London',     1905, 5),   -- 5  CHE
  ('Tottenham Hotspur', 'London',     1882, 6);   -- 6  TOT

-- Coaches (7) — coach_id 1..7
-- Coaches 1..6 are the current head coaches at go-live, one per club.
-- Coach 7 (Delaney) is unaffiliated at E1; he becomes the subject of the
-- three-answer E7 story in 03_timeline.sql (taking over Chelsea).
INSERT INTO coach (first_name, last_name, birth_date, nationality) VALUES
  ('Oliver',    'Harwood',   '1968-04-15', 'English'),   -- 1  → MUN
  ('Martin',    'Reyes',     '1972-11-02', 'Spanish'),   -- 2  → MCI
  ('Hendrik',   'Van Dijk',  '1970-07-21', 'Dutch'),     -- 3  → LIV
  ('Francesco', 'Bellini',   '1975-03-08', 'Italian'),   -- 4  → ARS
  ('James',     'Whittaker', '1971-09-14', 'English'),   -- 5  → CHE
  ('Thomas',    'Richter',   '1969-12-05', 'German'),    -- 6  → TOT
  ('Marcus',    'Delaney',   '1976-02-28', 'English');   -- 7  → unaffiliated

-- Players (65) — player_id 1..65
-- Players 1..50 are the primary roster (referenced by the timeline);
-- players 51..65 are stable background anchors with 2028+ contracts to
-- keep the current-facts count above 60 after timeline terminations.
INSERT INTO player (first_name, last_name, birth_date, nationality) VALUES
  -- Manchester United (players 1..9)
  ('Marcus',    'Pennington', '1998-03-12', 'English'),
  ('Daniel',    'Ashworth',   '1996-07-24', 'English'),
  ('Finn',      'O''Brien',   '2001-11-08', 'Irish'),
  ('Rafael',    'Costa',      '1999-05-16', 'Brazilian'),
  ('Jamal',     'Oduya',      '2000-02-03', 'Nigerian'),
  ('Victor',    'Lindqvist',  '2002-09-27', 'Swedish'),
  ('Henrik',    'Vollmer',    '1995-01-19', 'German'),
  ('Omar',      'Benali',     '1997-04-11', 'Moroccan'),
  ('Toby',      'Reeves',     '2004-08-30', 'English'),
  -- Manchester City (players 10..18)
  ('Diego',     'Almeida',    '1994-10-05', 'Portuguese'),
  ('Lucas',     'Mendoza',    '1996-06-14', 'Argentine'),
  ('Noah',      'Winterberg', '1997-12-02', 'German'),
  ('Kofi',      'Mensah',     '2000-03-18', 'Ghanaian'),
  ('Edouard',   'Lacroix',    '1998-08-07', 'French'),
  ('Takeshi',   'Nakamura',   '1999-11-23', 'Japanese'),
  ('Caleb',     'Thornton',   '2003-05-04', 'English'),
  ('Mateo',     'Rossi',      '1995-02-28', 'Italian'),
  ('Pedro',     'Villanueva', '1996-07-09', 'Spanish'),
  -- Liverpool (players 19..26)
  ('Scott',     'Blackwood',  '1997-09-15', 'Scottish'),
  ('Isaac',     'Mwangi',     '1999-04-22', 'Kenyan'),
  ('Ryan',      'Fletcher',   '1995-06-10', 'English'),
  ('Thiago',    'Oliveira',   '2001-01-17', 'Brazilian'),
  ('Robin',     'Jansen',     '1996-11-28', 'Dutch'),
  ('Marco',     'Dubois',     '2000-08-13', 'Belgian'),
  ('Sean',      'Doherty',    '2002-02-20', 'Irish'),
  ('Owen',      'Bradley',    '1998-10-30', 'English'),
  -- Arsenal (players 27..34)
  ('Antoine',   'Girard',     '1998-05-07', 'French'),
  ('Felipe',    'Souza',      '1996-12-19', 'Brazilian'),
  ('George',    'Hartley',    '1999-07-26', 'English'),
  ('Yuki',      'Sasaki',     '2001-03-14', 'Japanese'),
  ('Mahmoud',   'Al-Rashid',  '1997-09-01', 'Egyptian'),
  ('Logan',     'Pierce',     '2004-02-11', 'English'),
  ('Nikos',     'Papadakis',  '1995-11-04', 'Greek'),
  ('Lukas',     'Weber',      '2000-06-25', 'Austrian'),
  -- Chelsea (players 35..42)
  ('Alfie',     'Marsden',    '1996-04-18', 'English'),
  ('Carlos',    'Beltran',    '1997-08-29', 'Mexican'),
  ('Dylan',     'Winters',    '1999-12-06', 'Welsh'),
  ('Enzo',      'Ferraro',    '1995-10-12', 'Italian'),
  ('Hugo',      'Berger',     '1998-01-25', 'German'),
  ('Ismael',    'Diallo',     '2001-05-30', 'Senegalese'),
  ('Youssef',   'Haddad',     '1996-03-02', 'Moroccan'),
  ('Nathan',    'Brooks',     '2002-07-19', 'English'),
  -- Tottenham Hotspur (players 43..50)
  ('Max',       'Davenport',  '1997-02-14', 'English'),
  ('Pablo',     'Hernandez',  '1996-09-21', 'Spanish'),
  ('Sebastien', 'Moreau',     '1999-11-11', 'French'),
  ('Johan',     'Kristensen', '1995-05-08', 'Danish'),
  ('Isaac',     'Gyasi',      '1998-12-30', 'Ghanaian'),
  ('Oscar',     'Lindgren',   '2000-04-16', 'Swedish'),
  ('Harry',     'Whitfield',  '2003-10-23', 'English'),
  ('Vincent',   'Bauer',      '1996-06-05', 'German'),
  -- Background anchors (players 51..65) — stable through timeline
  -- Manchester United (51..52)
  ('Harry',     'Walsh',      '1998-06-18', 'English'),
  ('Igor',      'Volkov',     '2001-09-04', 'Russian'),
  -- Manchester City (53..55)
  ('Benjamin',  'Clark',      '1996-11-27', 'English'),
  ('Luís',      'Mendes',     '2000-05-13', 'Portuguese'),
  ('Mohamed',   'Keita',      '1999-02-09', 'Guinean'),
  -- Liverpool (56..57)
  ('Peter',     'Nielsen',    '1997-10-21', 'Danish'),
  ('Chen',      'Wei',        '2001-04-16', 'Chinese'),
  -- Arsenal (58..60)
  ('Mikel',     'Larsson',    '1998-08-02', 'Swedish'),
  ('Khaled',    'Mansour',    '1996-01-30', 'Moroccan'),
  ('Jack',      'Thompson',   '2003-03-17', 'English'),
  -- Chelsea (61..63)
  ('Theo',      'Rousseau',   '1999-07-25', 'French'),
  ('Rasmus',    'Olsen',      '1997-12-11', 'Norwegian'),
  ('Serge',     'Kouassi',    '2000-10-06', 'Ivorian'),
  -- Tottenham Hotspur (64..65)
  ('Luca',      'Russo',      '1998-04-28', 'Italian'),
  ('Daniel',    'Brennan',    '2002-08-14', 'Irish');

-- ============================================================================
-- SECTION 3 · BITEMPORAL VERSION ROWS (E1 beliefs)
-- All rows share @e1_tx_id and tx_from = @sim_now.
-- tx_to defaults to the sentinel (current belief).
-- valid_from = contract/role start date (in the past);
-- valid_to   = contract end date (future) OR sentinel for open-ended roles.
-- ============================================================================

-- --- contract_version (65 rows: one current contract per player) ------------
-- Players 1..50: as before, but 10 unreferenced-expiring contracts shifted
--   to 2028-06-30 so they stay current at wall-clock today
--   (originally expired 2026-06-30 or 2026-07-31 with no renewal in timeline).
--   Shifted: 4 (Costa), 7 (Vollmer), 13 (Mensah), 15 (Nakamura), 17 (Rossi),
--            28 (Souza), 33 (Papadakis), 36 (Beltran), 41 (Haddad),
--            43 (Davenport).
-- Players 51..65: new background anchors, contracts to 2028–2029.
INSERT INTO contract_version
  (player_id, club_id, salary_eur, valid_from, valid_to, tx_from, tx_id)
VALUES
  -- Manchester United
  ( 1, 1,  8000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),
  ( 2, 1,  6000000, '2022-07-01', '2026-06-30', @sim_now, @e1_tx_id),   -- expires naturally; re-signs via event 30
  ( 3, 1,  4000000, '2024-01-15', '2027-01-14', @sim_now, @e1_tx_id),
  ( 4, 1,  5000000, '2023-08-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-07-31
  ( 5, 1,  4500000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),
  ( 6, 1,  3000000, '2024-02-01', '2027-01-31', @sim_now, @e1_tx_id),
  ( 7, 1,  7000000, '2022-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  ( 8, 1,  4000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- terminated via event 14
  ( 9, 1,  1500000, '2024-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- transferred via event 10
  -- Manchester City
  (10, 2, 12000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),
  (11, 2, 15000000, '2022-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- transferred via event 4
  (12, 2, 10000000, '2024-01-01', '2028-06-30', @sim_now, @e1_tx_id),   -- released via event 37
  (13, 2,  7000000, '2023-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  (14, 2,  9000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- released via event 39
  (15, 2,  6000000, '2023-01-15', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  (16, 2,  3000000, '2024-08-01', '2027-07-31', @sim_now, @e1_tx_id),
  (17, 2,  8000000, '2022-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  (18, 2, 11000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- released via event 36
  -- Liverpool
  (19, 3,  8000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- released via event 31
  (20, 3,  7000000, '2024-01-01', '2027-12-31', @sim_now, @e1_tx_id),
  (21, 3,  9000000, '2022-08-01', '2026-07-31', @sim_now, @e1_tx_id),   -- expires naturally; re-signs via event 29
  (22, 3,  7000000, '2024-07-01', '2029-06-30', @sim_now, @e1_tx_id),
  (23, 3,  6000000, '2023-07-01', '2026-06-30', @sim_now, @e1_tx_id),   -- expires naturally; re-signs via event 33
  (24, 3,  5000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- released via event 34
  (25, 3,  3000000, '2024-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- transferred via event 28
  (26, 3,  7000000, '2023-07-01', '2026-06-30', @sim_now, @e1_tx_id),   -- transferred via event 11 before expiry
  -- Arsenal
  (27, 4,  9000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),
  (28, 4,  8000000, '2022-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  (29, 4,  6000000, '2023-01-15', '2026-12-31', @sim_now, @e1_tx_id),
  (30, 4,  4000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),
  (31, 4,  7000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),
  (32, 4,  2000000, '2024-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- transferred via event 3
  (33, 4,  6000000, '2022-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  (34, 4,  5000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- terminated via event 21
  -- Chelsea
  (35, 5,  8000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),
  (36, 5,  7000000, '2022-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  (37, 5,  6000000, '2024-01-01', '2027-12-31', @sim_now, @e1_tx_id),
  (38, 5,  9000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),
  (39, 5,  7000000, '2023-07-01', '2026-06-30', @sim_now, @e1_tx_id),   -- transferred via event 25 before expiry
  (40, 5,  5000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),
  (41, 5,  7000000, '2022-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  (42, 5,  3000000, '2024-07-01', '2027-06-30', @sim_now, @e1_tx_id),
  -- Tottenham Hotspur
  (43, 6,  7000000, '2022-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- shifted from 2026-06-30
  (44, 6,  8000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- terminated via event 23
  (45, 6,  6000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),
  (46, 6,  7000000, '2022-07-01', '2026-06-30', @sim_now, @e1_tx_id),   -- expires naturally; re-signs via event 26
  (47, 6,  5000000, '2023-01-15', '2026-12-31', @sim_now, @e1_tx_id),
  (48, 6,  4000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),
  (49, 6,  2000000, '2024-07-01', '2027-06-30', @sim_now, @e1_tx_id),
  (50, 6,  6000000, '2023-07-01', '2027-06-30', @sim_now, @e1_tx_id),   -- transferred via event 27
  -- Background anchors (players 51..65), all current at wall-clock today
  (51, 1,  5000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- Walsh    (MUN)
  (52, 1,  3500000, '2024-01-15', '2027-06-30', @sim_now, @e1_tx_id),   -- Volkov   (MUN)
  (53, 2,  8000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- Clark    (MCI)
  (54, 2,  7000000, '2024-01-01', '2028-12-31', @sim_now, @e1_tx_id),   -- Mendes   (MCI)
  (55, 2,  6000000, '2025-01-01', '2029-06-30', @sim_now, @e1_tx_id),   -- Keita    (MCI)
  (56, 3,  6500000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- Nielsen  (LIV)
  (57, 3,  4000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- Wei      (LIV)
  (58, 4,  7000000, '2024-01-01', '2028-06-30', @sim_now, @e1_tx_id),   -- Larsson  (ARS)
  (59, 4,  5000000, '2024-07-01', '2029-06-30', @sim_now, @e1_tx_id),   -- Mansour  (ARS)
  (60, 4,  2500000, '2025-01-01', '2028-06-30', @sim_now, @e1_tx_id),   -- Thompson (ARS)
  (61, 5,  8000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id),   -- Rousseau (CHE)
  (62, 5,  6000000, '2024-01-15', '2028-01-14', @sim_now, @e1_tx_id),   -- Olsen    (CHE)
  (63, 5,  5000000, '2024-07-01', '2029-06-30', @sim_now, @e1_tx_id),   -- Kouassi  (CHE)
  (64, 6,  7000000, '2024-01-01', '2028-06-30', @sim_now, @e1_tx_id),   -- Russo    (TOT)
  (65, 6,  4000000, '2024-07-01', '2028-06-30', @sim_now, @e1_tx_id);   -- Brennan  (TOT)

-- --- head_coach_version (6 rows: one current head coach per club) -----------
-- valid_to defaults to sentinel (role ongoing).
INSERT INTO head_coach_version
  (club_id, coach_id, valid_from, tx_from, tx_id)
VALUES
  (1, 1, '2023-07-01', @sim_now, @e1_tx_id),   -- Harwood   → Manchester United
  (2, 2, '2022-06-15', @sim_now, @e1_tx_id),   -- Reyes     → Manchester City
  (3, 3, '2024-05-20', @sim_now, @e1_tx_id),   -- Van Dijk  → Liverpool
  (4, 4, '2021-12-10', @sim_now, @e1_tx_id),   -- Bellini   → Arsenal
  (5, 5, '2024-06-01', @sim_now, @e1_tx_id),   -- Whittaker → Chelsea
  (6, 6, '2024-07-15', @sim_now, @e1_tx_id);   -- Richter   → Tottenham Hotspur

-- --- loan_version (4 rows: loans already in progress at go-live) ------------
-- Parent contract in contract_version is NOT closed; the two facts coexist.
-- Each loan is a one-season spell within 2025 → 2026.
INSERT INTO loan_version
  (player_id, from_club_id, to_club_id, valid_from, valid_to, tx_from, tx_id)
VALUES
  ( 9, 1, 6, '2025-01-15', '2026-01-14', @sim_now, @e1_tx_id),  -- Reeves    MUN → TOT
  (16, 2, 4, '2025-02-01', '2026-01-31', @sim_now, @e1_tx_id),  -- Thornton  MCI → ARS
  (32, 4, 5, '2024-08-15', '2025-08-14', @sim_now, @e1_tx_id),  -- Pierce    ARS → CHE
  (49, 6, 3, '2025-01-10', '2026-01-09', @sim_now, @e1_tx_id);  -- Whitfield TOT → LIV

-- ============================================================================
-- SECTION 4 · VERIFICATION (optional)
-- Expected counts after E1:
--   player           = 65     club       = 6
--   coach            =  7     stadium    = 6
--   season           =  2     tx_registry= 1
--   contract_version = 65     head_coach_version = 6     loan_version = 4
--   current relationship facts at @sim_now (contracts + loans + head coach) = 75
-- ============================================================================

SELECT 'player'              AS table_name, COUNT(*) AS row_count FROM player
UNION ALL SELECT 'club',               COUNT(*) FROM club
UNION ALL SELECT 'coach',              COUNT(*) FROM coach
UNION ALL SELECT 'stadium',            COUNT(*) FROM stadium
UNION ALL SELECT 'season',             COUNT(*) FROM season
UNION ALL SELECT 'tx_registry',        COUNT(*) FROM tx_registry
UNION ALL SELECT 'contract_version',   COUNT(*) FROM contract_version
UNION ALL SELECT 'head_coach_version', COUNT(*) FROM head_coach_version
UNION ALL SELECT 'loan_version',       COUNT(*) FROM loan_version;

-- Sanity: current relationship facts at the simulated clock.
-- Should be 75 (65 contracts + 6 head-coach assignments + 4 loans) immediately after E1.
SELECT 'current_relationship_facts_at_sim_now' AS metric, (
    (SELECT COUNT(*) FROM contract_version
       WHERE tx_to = '9999-12-31 23:59:59.999999'
         AND valid_from <= DATE(@sim_now) AND DATE(@sim_now) < valid_to)
  + (SELECT COUNT(*) FROM head_coach_version
       WHERE tx_to = '9999-12-31 23:59:59.999999'
         AND valid_from <= DATE(@sim_now) AND DATE(@sim_now) < valid_to)
  + (SELECT COUNT(*) FROM loan_version
       WHERE tx_to = '9999-12-31 23:59:59.999999'
         AND valid_from <= DATE(@sim_now) AND DATE(@sim_now) < valid_to)
) AS value;
