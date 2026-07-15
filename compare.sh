#!/usr/bin/env bash
# Run the SAME filtered query on both schemas and show what each actually scanned.
# Assumes ./run_demo.sh already loaded the data (container ch-dwh-demo is up).
set -euo pipefail
N=ch-dwh-demo
F="country='DE' AND ts>='2025-03-01' AND ts<'2025-04-01'"
for s in naive tuned; do
  docker exec "$N" clickhouse-client --query \
    "SELECT event_type, count(), sum(revenue) FROM events_$s WHERE $F GROUP BY event_type SETTINGS log_comment='live_$s'" --format Null
done
docker exec "$N" clickhouse-client --query "SYSTEM FLUSH LOGS"
echo "Same query, same data, two schemas — what each scanned:"
docker exec "$N" clickhouse-client --query "
SELECT log_comment AS schema,
       query_duration_ms AS ms,
       formatReadableQuantity(read_rows) AS rows_read,
       formatReadableSize(read_bytes)    AS scanned
FROM system.query_log
WHERE type='QueryFinish' AND log_comment IN ('live_naive','live_tuned')
ORDER BY log_comment DESC
LIMIT 1 BY log_comment
FORMAT PrettyCompact"
