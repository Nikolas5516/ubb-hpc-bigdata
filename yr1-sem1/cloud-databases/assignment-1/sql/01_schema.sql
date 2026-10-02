-- ============================================================================
-- 01_schema.sql
-- Bitemporal football league database
--
-- Engine: MySQL 8.4 (InnoDB, utf8mb4)
-- Re-runnable on an empty database (DROP IF EXISTS ... first).
--
-- Modeling conventions (see report section "Modeling decisions"):
--   * Half-open periods [from, to)
--   * Sentinels instead of NULL for open ends:
--       valid_to sentinel :  '9999-12-31'                    (DATE)
--       tx_to    sentinel :  '9999-12-31 23:59:59.999999'    (DATETIME(6))
--   * Transaction time in UTC, microsecond precision, DATETIME(6)
--       (TIMESTAMP is unusable here: 2038 cap, cannot hold the sentinel)
--   * Anchor tables carry stable identity; version tables carry periods
--   * Foreign keys point at anchors only, never at version rows
--   * tx_registry stamps every logical change; every version row cites a tx_id
-- ============================================================================

SET NAMES utf8mb4;

-- ----------------------------------------------------------------------------
-- Clean slate. Drop children (version tables) before parents (anchors),
-- and club before stadium (FK club.home_stadium_id -> stadium.stadium_id).
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS contract_version;
DROP TABLE IF EXISTS loan_version;
DROP TABLE IF EXISTS head_coach_version;
DROP TABLE IF EXISTS club;
DROP TABLE IF EXISTS player;
DROP TABLE IF EXISTS coach;
DROP TABLE IF EXISTS stadium;
DROP TABLE IF EXISTS season;
DROP TABLE IF EXISTS tx_registry;

-- ============================================================================
-- SECTION 1 · TRANSACTION REGISTRY (non-temporal audit log)
-- ============================================================================

-- tx_registry -----------------------------------------------------------------
-- One row per logical change. Every write in 03_timeline.sql opens one entry
-- here and stamps its tx_id on every version row it inserts or closes.
-- Non-temporal by nature: it IS the history, so it does not need its own.
CREATE TABLE tx_registry (
    tx_id     BIGINT        NOT NULL AUTO_INCREMENT,
    tx_time   DATETIME(6)   NOT NULL,                       -- UTC
    author    VARCHAR(100)  NOT NULL,
    reason    VARCHAR(255)  NOT NULL,
    PRIMARY KEY (tx_id),
    INDEX ix_tx_time (tx_time)
) ENGINE=InnoDB;

-- ============================================================================
-- SECTION 2 · REFERENCE TABLE (non-temporal)
-- ============================================================================

-- season ----------------------------------------------------------------------
-- Named calendar periods used by Q4 ("valid during a named period").
-- Non-temporal: season boundaries are fixed once published.
CREATE TABLE season (
    season_id   INT           NOT NULL AUTO_INCREMENT,
    name        VARCHAR(10)   NOT NULL,                     -- e.g. '2025-26'
    start_date  DATE          NOT NULL,
    end_date    DATE          NOT NULL,
    PRIMARY KEY (season_id),
    UNIQUE KEY uk_season_name (name),
    CHECK (start_date < end_date)
) ENGINE=InnoDB;

-- ============================================================================
-- SECTION 3 · ANCHOR TABLES (stable identity, non-temporal)
-- Version tables FK to these. IDs are immutable business identities.
-- ============================================================================

-- stadium ---------------------------------------------------------------------
-- Non-temporal in this scope: capacity/city changes are out of scope for the
-- questions we answer. Justified in report ("Modeling decisions").
CREATE TABLE stadium (
    stadium_id  INT           NOT NULL AUTO_INCREMENT,
    name        VARCHAR(100)  NOT NULL,
    city        VARCHAR(100)  NOT NULL,
    capacity    INT           NOT NULL,
    PRIMARY KEY (stadium_id),
    CHECK (capacity > 0)
) ENGINE=InnoDB;

-- club ------------------------------------------------------------------------
-- Anchor. home_stadium_id is a plain (non-temporal) FK to stadium: a club has
-- exactly one current home ground in this model.
CREATE TABLE club (
    club_id           INT           NOT NULL AUTO_INCREMENT,
    name              VARCHAR(100)  NOT NULL,
    city              VARCHAR(100)  NOT NULL,
    founded_year      SMALLINT      NOT NULL,
    home_stadium_id   INT           NOT NULL,
    PRIMARY KEY (club_id),
    UNIQUE KEY uk_club_name (name),
    FOREIGN KEY (home_stadium_id) REFERENCES stadium (stadium_id),
    CHECK (founded_year BETWEEN 1850 AND 2100)
) ENGINE=InnoDB;

-- player ----------------------------------------------------------------------
CREATE TABLE player (
    player_id    INT           NOT NULL AUTO_INCREMENT,
    first_name   VARCHAR(60)   NOT NULL,
    last_name    VARCHAR(60)   NOT NULL,
    birth_date   DATE          NOT NULL,
    nationality  VARCHAR(50)   NOT NULL,
    PRIMARY KEY (player_id),
    INDEX ix_player_name (last_name, first_name)
) ENGINE=InnoDB;

-- coach -----------------------------------------------------------------------
CREATE TABLE coach (
    coach_id     INT           NOT NULL AUTO_INCREMENT,
    first_name   VARCHAR(60)   NOT NULL,
    last_name    VARCHAR(60)   NOT NULL,
    birth_date   DATE          NOT NULL,
    nationality  VARCHAR(50)   NOT NULL,
    PRIMARY KEY (coach_id),
    INDEX ix_coach_name (last_name, first_name)
) ENGINE=InnoDB;

-- ============================================================================
-- SECTION 4 · BITEMPORAL VERSION TABLES
-- Every row is a rectangle on the (valid time × transaction time) plane.
-- Business columns are never updated; only tx_to is updated to close a belief.
-- No physical DELETE.
-- ============================================================================

-- contract_version ------------------------------------------------------------
-- Player <-> Club relationship. Carries salary_eur - the numeric attribute
-- that changes over time (rule: at least one such attribute).
--
-- Largest version table -> hosts the required as-of index.
-- Business key for invariant I1 (no VT overlap among currently-believed rows):
-- player_id  (a player has at most one active contract at any valid instant).
CREATE TABLE contract_version (
    version_id   BIGINT        NOT NULL AUTO_INCREMENT,
    player_id    INT           NOT NULL,
    club_id      INT           NOT NULL,
    salary_eur   DECIMAL(12,2) NOT NULL,
    valid_from   DATE          NOT NULL,
    valid_to     DATE          NOT NULL DEFAULT '9999-12-31',
    tx_from      DATETIME(6)   NOT NULL,
    tx_to        DATETIME(6)   NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id        BIGINT        NOT NULL,
    PRIMARY KEY (version_id),
    FOREIGN KEY (player_id) REFERENCES player      (player_id),
    FOREIGN KEY (club_id)   REFERENCES club        (club_id),
    FOREIGN KEY (tx_id)     REFERENCES tx_registry (tx_id),
    CHECK (valid_from < valid_to),
    CHECK (tx_from    < tx_to),
    CHECK (salary_eur >= 0),
    -- As-of index (Part A requirement). Layout: business key first (equality),
    -- then tx_to (range in the WHERE clause: p.known_at < t.tx_to),
    -- then valid_from (further range narrowing).
    -- Report shows EXPLAIN of Q6 with and without this index.
    INDEX ix_contract_asof (player_id, tx_to, valid_from)
) ENGINE=InnoDB;

-- loan_version ----------------------------------------------------------------
-- Loan spell: player temporarily plays for to_club while their contract stays
-- with from_club. In this model a loan does NOT close the parent contract;
-- both facts coexist (justified in report - mirrors real registration data).
--
-- Business key for I1: player_id (no two overlapping loans for one player).
CREATE TABLE loan_version (
    version_id     BIGINT        NOT NULL AUTO_INCREMENT,
    player_id      INT           NOT NULL,
    from_club_id   INT           NOT NULL,   -- parent club (contract holder)
    to_club_id     INT           NOT NULL,   -- loanee club
    valid_from     DATE          NOT NULL,
    valid_to       DATE          NOT NULL DEFAULT '9999-12-31',
    tx_from        DATETIME(6)   NOT NULL,
    tx_to          DATETIME(6)   NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id          BIGINT        NOT NULL,
    PRIMARY KEY (version_id),
    FOREIGN KEY (player_id)    REFERENCES player      (player_id),
    FOREIGN KEY (from_club_id) REFERENCES club        (club_id),
    FOREIGN KEY (to_club_id)   REFERENCES club        (club_id),
    FOREIGN KEY (tx_id)        REFERENCES tx_registry (tx_id),
    CHECK (valid_from < valid_to),
    CHECK (tx_from    < tx_to),
    CHECK (from_club_id <> to_club_id)
) ENGINE=InnoDB;

-- head_coach_version ----------------------------------------------------------
-- Role assignment: club -> head coach. Enforces I3 (single role holder per
-- club at any valid instant) via the same no-overlap invariant as I1.
--
-- This is the table that reproduces the "one question, three correct answers"
-- pattern.
--
-- Business key: club_id.
CREATE TABLE head_coach_version (
    version_id   BIGINT        NOT NULL AUTO_INCREMENT,
    club_id      INT           NOT NULL,
    coach_id     INT           NOT NULL,
    valid_from   DATE          NOT NULL,
    valid_to     DATE          NOT NULL DEFAULT '9999-12-31',
    tx_from      DATETIME(6)   NOT NULL,
    tx_to        DATETIME(6)   NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id        BIGINT        NOT NULL,
    PRIMARY KEY (version_id),
    FOREIGN KEY (club_id)  REFERENCES club        (club_id),
    FOREIGN KEY (coach_id) REFERENCES coach       (coach_id),
    FOREIGN KEY (tx_id)    REFERENCES tx_registry (tx_id),
    CHECK (valid_from < valid_to),
    CHECK (tx_from    < tx_to)
) ENGINE=InnoDB;
