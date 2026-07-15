-- 50M synthetic rows over 180 days. No real data, no credentials — mock-first.
INSERT INTO events_naive
SELECT
  number AS event_id,
  toDateTime('2025-01-01 00:00:00') + toIntervalSecond(rand(9) % 15552000) AS ts,
  (rand(1) % 3000000)::UInt32 AS user_id,
  ['US','GB','DE','FR','IN','BR','JP','CA','AU','MX','ES','IT','NL','SE','PL','TR','SG','KR','ZA','AE'][(rand(2) % 20) + 1] AS country,
  ['ios','android','web','desktop','tablet'][(rand(3) % 5) + 1] AS device,
  ['view','click','add_to_cart','purchase','signup','login','search','share'][(rand(4) % 8) + 1] AS event_type,
  round(rand(5) % 50000 / 100.0, 2) AS revenue,
  (rand(6) % 600000)::UInt32 AS session_ms
FROM numbers(50000000)
SETTINGS max_insert_threads = 4;

-- Same rows, tuned layout.
INSERT INTO events_tuned SELECT * FROM events_naive SETTINGS max_insert_threads = 4;
