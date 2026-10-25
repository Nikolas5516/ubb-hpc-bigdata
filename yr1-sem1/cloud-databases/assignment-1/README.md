# Assignment 1 — Bitemporal Football League Database

A MySQL 8.4 bitemporal database modelling the English Premier League 2025–26 season. Design write-up is in `report.md` / `report.pdf`; the full event-by-event narrative is in `story-log.md`.

## Prerequisites

- Docker Desktop with Docker Compose v2
- Port 3306 free (or edit `docker-compose.yml`)

## File layout

```
assignment-1/
├── docker-compose.yml       MySQL 8.4 service, UTC, strict mode
├── README.md                this file
├── report.md / report.pdf   Part D report
├── story-log.md             40-event timeline narrative
├── er_diagram.pdf           schema diagram
└── sql/
    ├── 01_schema.sql        tables, constraints, indexes
    ├── 02_data.sql          E1: initial load (one tx_id, 75 version rows)
    ├── 03_timeline.sql      E2–E9: 39 events across 16 months
    ├── 04_views.sql         Q0–Q8 as views + query_params table
    └── 05_tests.sql         test harness with -- Expected: comments
```

## Run the full pipeline

```powershell
docker compose up -d --wait
docker compose exec mysql sh -c "mysql -uroot -proot football < /sql/01_schema.sql"
docker compose exec mysql sh -c "mysql -uroot -proot football < /sql/02_data.sql"
docker compose exec mysql sh -c "mysql -uroot -proot football < /sql/03_timeline.sql"
docker compose exec mysql sh -c "mysql -uroot -proot football < /sql/04_views.sql"
docker compose exec mysql sh -c "mysql -uroot -proot football < /sql/05_tests.sql"
```

Takes ~15 seconds on a laptop. The `[Warning] Using a password on the command line interface can be insecure` message is harmless in this dev setup.

## Expected output highlights

From `05_tests.sql`:

| Check | Expected |
|-------|----------|
| Q0 integrity violations | **0 rows** |
| Q1 current contracts / coaches / loans | **57 / 6 / 0** (= 63 current facts) |
| Q2 head-coach tenures | **9** (3 clubs with handovers × 2 + 3 stable × 1) |
| Q6 three-answer test on Chelsea at `valid_at = '2026-02-03'` | Whittaker / Delaney / Whittaker |
| Q7 monthly tx_registry entries | **40** across 16 months |
| Q8 contract gaps | **4** (Ashworth, Fletcher, Jansen, Kristensen 1-day fencepost) |
| Q8 loan gaps | **1** (Thornton MCI→ARS, 67 days) |

## Reproduce the three-answer test only

After the full pipeline has run:

```powershell
docker compose exec mysql mysql -uroot -proot football -e "
  UPDATE query_params SET valid_at='2026-02-03', known_at='2026-02-10 00:00:00.000000';
  SELECT 'Answer 1 (before late entry)' AS probe, coach_name FROM v_coach_at_club WHERE club_id=5;
  UPDATE query_params SET known_at='2026-02-17 00:00:00.000000';
  SELECT 'Answer 2 (after late entry, before correction)' AS probe, coach_name FROM v_coach_at_club WHERE club_id=5;
  UPDATE query_params SET known_at='2026-10-01 00:00:00.000000';
  SELECT 'Answer 3 (after correction)' AS probe, coach_name FROM v_coach_at_club WHERE club_id=5;
"
```

## Reset to an empty database

```powershell
docker compose down -v
```

Removes the container, network, and named volume. The next `docker compose up` starts from a blank slate.

## Install the A1 advanced features (bonus)

After the main pipeline, run:

```powershell
docker compose exec mysql sh -c "mysql -uroot -proot football < /sql/06_advanced_a1.sql"
```

Installs 6 triggers (BEFORE UPDATE / BEFORE DELETE on each bitemporal table) and 10 stored procedures that encapsulate the common bitemporal write patterns. The file ends with a verification pass — two PASS lines prove the triggers reject direct business-column UPDATEs and all DELETEs — plus a transactional procedure demo that is rolled back so no data persists. See `report.md` §12 for the design.

## Install the A2 advanced features (bonus)

A2 runs against a separate MariaDB 11.4 service with its own data volume, scoped behind the `a2` compose profile. Bring it up with:

```powershell
docker compose --profile a2 up -d mariadb --wait
docker compose exec mariadb sh -c "mariadb -uroot -proot football < /sql/06_advanced_a2.sql"
```

Expected tail of output:

```
Answer 1 (known_at=2026-02-10): expect Whittaker  → Whittaker
Answer 2 (known_at=2026-02-17): expect Delaney    → Delaney
Answer 3 (known_at=2026-10-01): expect Whittaker  → Whittaker
--- A2 install complete ---
```

Three demos: `WITHOUT OVERLAPS` (engine-enforced I1), `FOR PORTION OF` (one-statement surgical correction), and `FOR SYSTEM_TIME AS OF` (the three-answer test in declarative form). See `report.md` §13.

Reset the MariaDB side only with:

```powershell
docker compose --profile a2 down -v
```

## Reproduce the §8 EXPLAIN benchmark

The composite index `ix_contract_asof (player_id, tx_to, valid_from)` is also the FK support index for `player_id`, so `DROP INDEX` fails with error 1553. Swap in a plain FK index first:

```sql
-- With the composite (default state) — run after the full pipeline:
EXPLAIN FORMAT=TREE SELECT * FROM contract_version
 WHERE player_id = 1
   AND tx_from <= '2026-07-01 00:00:00.000000' AND '2026-07-01 00:00:00.000000' < tx_to
   AND valid_from <= '2026-06-01' AND '2026-06-01' < valid_to;

-- Swap to FK-only index:
ALTER TABLE contract_version ADD INDEX ix_fk_player (player_id);
ALTER TABLE contract_version DROP INDEX ix_contract_asof;
-- Re-run the EXPLAIN above here.

-- Restore the composite:
ALTER TABLE contract_version ADD INDEX ix_contract_asof (player_id, tx_to, valid_from);
ALTER TABLE contract_version DROP INDEX ix_fk_player;
```

## Troubleshooting

- **`port is already allocated`** on `docker compose up` — change the host-side port in `docker-compose.yml` from `"3306:3306"` to e.g. `"3307:3306"`.
- **Pipeline runs but tests show different numbers** — check that `02_data.sql` and `03_timeline.sql` both ran without errors. The counts in `05_tests.sql` assume the full timeline is loaded.
- **Changes don't take effect after editing SQL** — `docker compose down -v` to drop the volume, then `up -d --wait` and re-run the pipeline. SQL files are mounted read-only at `/sql/`, so edits on the host take effect on the next run without rebuilding the image.