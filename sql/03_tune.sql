-- Pre-aggregate the hot daily rollup as a projection. Reads the aggregate,
-- not the 50M raw rows. Costs ~1.4 MiB of storage; kept in sync automatically.
ALTER TABLE events_tuned ADD PROJECTION p_daily (
  SELECT country, event_type, toDate(ts) AS d, count(), sum(revenue)
  GROUP BY country, event_type, d
);
ALTER TABLE events_tuned MATERIALIZE PROJECTION p_daily SETTINGS mutations_sync = 1;
