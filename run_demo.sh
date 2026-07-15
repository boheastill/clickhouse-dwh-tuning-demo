#!/usr/bin/env bash
# One command, from empty: start ClickHouse, build both schemas, load 50M rows,
# tune, and print the before/after benchmark. Mock-first — no real data/creds.
set -euo pipefail
CH="clickhouse/clickhouse-server:24.3"
NAME="ch-dwh-demo"

echo "==> starting ClickHouse ($CH)"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --ulimit nofile=262144:262144 "$CH" >/dev/null
until docker exec "$NAME" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; do sleep 2; done

q() { docker exec -i "$NAME" clickhouse-client -n; }
echo "==> schema";  q < sql/01_schema.sql
echo "==> loading 50M rows"; q < sql/02_load.sql
echo "==> tuning (projection)"; q < sql/03_tune.sql

# --- benchmark: run each query warm on both tables, read real metrics from query_log
bench() { # tag  sql
  docker exec "$NAME" clickhouse-client --query "$2 -- $1" --format Null >/dev/null 2>&1
  docker exec "$NAME" clickhouse-client --query "$2 -- $1" --format Null >/dev/null 2>&1
}
F="ts>='2025-03-01' AND ts<'2025-04-01' AND country='DE'"
bench q1_naive "SELECT event_type,count(),sum(revenue) FROM events_naive WHERE $F GROUP BY event_type"
bench q1_tuned "SELECT event_type,count(),sum(revenue) FROM events_tuned WHERE $F GROUP BY event_type"
W="ts>='2025-02-01' AND ts<'2025-05-01'"
bench q2_naive "SELECT country,sum(revenue) r FROM events_naive WHERE $W GROUP BY country ORDER BY r DESC LIMIT 10"
bench q2_tuned "SELECT country,sum(revenue) r FROM events_tuned WHERE $W GROUP BY country ORDER BY r DESC LIMIT 10"
R="SELECT country,event_type,toDate(ts) d,count(),sum(revenue) FROM %T GROUP BY country,event_type,d"
bench q3_naive "${R/\%T/events_naive}"
bench q3_tuned "${R/\%T/events_tuned}"

sleep 2
docker exec "$NAME" clickhouse-client --query "SYSTEM FLUSH LOGS"
echo; echo "==> RESULTS (real numbers from system.query_log)"
docker exec "$NAME" clickhouse-client --query "
SELECT extract(query, 'q[0-9]_[a-z]+') AS q,
       query_duration_ms AS ms,
       formatReadableQuantity(read_rows) AS rows_read,
       formatReadableSize(read_bytes) AS scanned
FROM system.query_log
WHERE type = 'QueryFinish'
  AND match(query, '-- q[0-9]_(naive|tuned)\\s*\$')
ORDER BY q, event_time DESC
LIMIT 1 BY q
FORMAT PrettyCompact"
echo; echo "table sizes at rest:"
docker exec "$NAME" clickhouse-client --query "
SELECT table, formatReadableSize(sum(bytes_on_disk)) on_disk FROM system.parts
WHERE table LIKE 'events_%' AND active GROUP BY table ORDER BY table FORMAT PrettyCompact"
echo; echo "done. teardown: docker rm -f $NAME"
