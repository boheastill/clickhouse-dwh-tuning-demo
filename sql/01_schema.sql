-- Two schemas for the SAME data.
-- events_naive: the common first-timer mistake — ORDER BY a high-cardinality id
--   that no query filters on, plain String columns, no partitioning.
-- events_tuned: ORDER BY matches the real query predicates, monthly partitions,
--   LowCardinality for low-cardinality strings.

DROP TABLE IF EXISTS events_naive;
CREATE TABLE events_naive (
  event_id   UInt64,
  ts         DateTime,
  user_id    UInt32,
  country    String,
  device     String,
  event_type String,
  revenue    Float64,
  session_ms UInt32
) ENGINE = MergeTree
ORDER BY event_id;                       -- <-- useless for analytics filters

DROP TABLE IF EXISTS events_tuned;
CREATE TABLE events_tuned (
  event_id   UInt64,
  ts         DateTime,
  user_id    UInt32,
  country    LowCardinality(String),     -- ~20 distinct  -> dictionary-encoded
  device     LowCardinality(String),     -- ~5 distinct
  event_type LowCardinality(String),     -- ~8 distinct
  revenue    Float64,
  session_ms UInt32
) ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)                -- prune by month
ORDER BY (country, event_type, ts);      -- primary key matches how analysts slice
