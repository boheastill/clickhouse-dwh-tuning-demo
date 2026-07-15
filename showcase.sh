#!/usr/bin/env bash
# Fuller walkthrough for a live demo. Assumes ./run_demo.sh loaded the data.
set -euo pipefail
N=ch-dwh-demo
F="country='DE' AND ts>='2025-03-01' AND ts<'2025-04-01'"
hdr(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$1"; }
ch(){ docker exec "$N" clickhouse-client "$@"; }

hdr "1. Same query on both schemas -> SAME answer (the tuned one isn't cheating)"
for s in naive tuned; do
  echo "-- events_$s"
  ch --query "SELECT event_type, count() AS events, round(sum(revenue)) AS revenue
              FROM events_$s WHERE $F GROUP BY event_type ORDER BY event_type
              SETTINGS log_comment='live_$s' FORMAT PrettyCompact"
done

hdr "2. ...but look what each had to SCAN to get there"
ch --query "SYSTEM FLUSH LOGS"
ch --query "SELECT log_comment AS schema, query_duration_ms AS ms,
                   formatReadableQuantity(read_rows) AS rows_read,
                   formatReadableSize(read_bytes) AS scanned
            FROM system.query_log
            WHERE type='QueryFinish' AND log_comment IN ('live_naive','live_tuned')
            ORDER BY log_comment DESC LIMIT 1 BY log_comment FORMAT PrettyCompact"

hdr "3. WHY: tuned index + partitions drop most granules BEFORE reading"
echo "tuned:"
ch --query "EXPLAIN indexes=1 SELECT count() FROM events_tuned WHERE $F" | grep -iE "Granules|Partition|PrimaryKey"
echo "naive (for contrast — nothing to skip):"
ch --query "EXPLAIN indexes=1 SELECT count() FROM events_naive WHERE $F" | grep -iE "Granules" | head -1

hdr "4. At rest: LowCardinality makes the tuned table smaller too"
ch --query "SELECT table, formatReadableSize(sum(bytes_on_disk)) AS on_disk
            FROM system.parts WHERE table LIKE 'events_%' AND active
            GROUP BY table ORDER BY table FORMAT PrettyCompact"
