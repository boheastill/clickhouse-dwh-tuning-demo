# Runbook — events DWH (demo)

## Reload from empty
`./run_demo.sh` — idempotent; drops and rebuilds both tables.

## Symptom: a dashboard query got slow
1. `SET send_logs_level='trace'` then run the query, or read `system.query_log`
   (`read_rows`, `read_bytes`, `query_duration_ms`) for the offending query.
2. If `read_rows ≈ total table rows`, the primary key isn't being used — the
   query filters on a column that isn't a prefix of `ORDER BY`. Fix the schema,
   not the query.
3. If it's a repeated aggregation, add a projection (see `sql/03_tune.sql`).

## Rollback a projection
`ALTER TABLE events_tuned DROP PROJECTION p_daily;` — non-blocking; the table
keeps serving from the base data.

## SLI / SLO (what I'd wire to Prometheus/Grafana)
- SLI: p95 `query_duration_ms` per dashboard, and `read_bytes` per query.
- SLO: p95 < 200 ms for the top-10 dashboards; alert on `read_bytes` regressions
  (a schema/query change that starts full-scanning shows up as bytes, before users complain).
