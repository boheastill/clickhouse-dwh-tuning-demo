# Verify it yourself (10 minutes)

You don't have to trust the README's numbers — reproduce them, and see *why*
each one moves. Only prerequisite: Docker.

## 1. Run the whole thing

```bash
git clone https://github.com/boheastill/clickhouse-dwh-tuning-demo
cd clickhouse-dwh-tuning-demo
./run_demo.sh
```

It starts ClickHouse, loads 50M synthetic rows into both schemas, adds the
projection, runs the benchmark, and prints a results table. ~1–2 minutes on a
laptop. Nothing touches a real database or a credential.

## 2. Read the win with your own eyes

Open a client against the running container:

```bash
docker exec -it ch-dwh-demo clickhouse-client
```

Run the same filtered query on both tables, and ask ClickHouse how much it read:

```sql
-- naïve: ordered by event_id, so this filter can't skip anything
SELECT event_type, count(), sum(revenue)
FROM events_naive
WHERE country = 'DE' AND ts >= '2025-03-01' AND ts < '2025-04-01'
GROUP BY event_type
SETTINGS log_comment = 'demo_naive';

-- tuned: ORDER BY (country, event_type, ts) + monthly partitions
SELECT event_type, count(), sum(revenue)
FROM events_tuned
WHERE country = 'DE' AND ts >= '2025-03-01' AND ts < '2025-04-01'
GROUP BY event_type
SETTINGS log_comment = 'demo_tuned';

SYSTEM FLUSH LOGS;

SELECT log_comment,
       query_duration_ms AS ms,
       formatReadableQuantity(read_rows)  AS rows_read,
       formatReadableSize(read_bytes)     AS scanned
FROM system.query_log
WHERE type = 'QueryFinish' AND log_comment IN ('demo_naive', 'demo_tuned')
ORDER BY event_time DESC
LIMIT 1 BY log_comment;
```

You'll see the naïve query scans the whole table (~50M rows / ~1.9 GiB) and the
tuned one reads a sliver (~0.5M rows / ~8 MiB). `read_bytes` is the number that
matters — it's deterministic and it's what costs you money and latency at scale.

## 3. Prove the primary key is the reason

Ask ClickHouse to show the index at work:

```sql
EXPLAIN indexes = 1
SELECT count() FROM events_tuned
WHERE country = 'DE' AND ts >= '2025-03-01' AND ts < '2025-04-01';
```

Look for the `PrimaryKey` and `Partition` steps and their **Granules: N/M** — the
tuned table drops most granules before reading a byte. Run the same `EXPLAIN` on
`events_naive` and you'll see it can't drop any: it reads all of them.

## 4. See the projection serve Q3

```sql
SELECT country, event_type, toDate(ts) AS d, count(), sum(revenue)
FROM events_tuned
GROUP BY country, event_type, d
SETTINGS log_comment = 'demo_rollup';

SYSTEM FLUSH LOGS;
SELECT read_rows, formatReadableSize(read_bytes)
FROM system.query_log
WHERE log_comment = 'demo_rollup' AND type = 'QueryFinish'
ORDER BY event_time DESC LIMIT 1;
```

It reads ~200K pre-aggregated rows instead of 50M — the projection did the work
at insert time. `system.projection_parts` shows it costs ~1 MiB on disk.

## 5. Tear down

```bash
docker rm -f ch-dwh-demo
```

That's the whole method: **change the schema to match the query, then let
`read_bytes` prove it.** The same loop is in `RUNBOOK.md` for triaging a slow
dashboard in production.
