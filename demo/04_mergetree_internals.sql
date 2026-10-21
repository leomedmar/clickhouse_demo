-- ============================================================
-- DEMO 3 — MergeTree internals: parts, partitions and the sparse index
-- Uses the demo.trips table (Demo 2b)
-- ============================================================
USE demo;

-- 1. Each INSERT creates one or more "parts" (immutable folders on disk)
SELECT partition, name, rows, formatReadableSize(bytes_on_disk) AS size, level
FROM system.parts
WHERE database = 'demo' AND table = 'trips' AND active
ORDER BY partition, name;

-- 2. Small INSERTs = many small parts (anti-pattern!)
INSERT INTO trips (trip_id, pickup_datetime, pickup_ntaname) VALUES (1, '2015-07-01 10:00:00', 'Test');
INSERT INTO trips (trip_id, pickup_datetime, pickup_ntaname) VALUES (2, '2015-07-01 11:00:00', 'Test');
INSERT INTO trips (trip_id, pickup_datetime, pickup_ntaname) VALUES (3, '2015-07-01 12:00:00', 'Test');

SELECT partition, count() AS parts, sum(rows) AS total_rows
FROM system.parts
WHERE database = 'demo' AND table = 'trips' AND active
GROUP BY partition ORDER BY partition;

-- 3. ClickHouse MERGEs parts in the background. We can force it (dev only!)
OPTIMIZE TABLE trips FINAL;

SELECT partition, count() AS parts, sum(rows) AS total_rows
FROM system.parts
WHERE database = 'demo' AND table = 'trips' AND active
GROUP BY partition ORDER BY partition;

-- 4. Sparse index: 1 entry per 8192 rows (granule)
SELECT
    sum(rows)                         AS total_rows,
    sum(marks)                        AS granules,
    formatReadableSize(sum(primary_key_bytes_in_memory)) AS index_in_memory
FROM system.parts
WHERE database = 'demo' AND table = 'trips' AND active;

-- 5. Filter on the sorting key → reads few granules
EXPLAIN indexes = 1
SELECT count(), avg(total_amount)
FROM trips
WHERE pickup_datetime BETWEEN '2015-08-15 00:00:00' AND '2015-08-15 23:59:59';

SELECT count(), round(avg(total_amount), 2)
FROM trips
WHERE pickup_datetime BETWEEN '2015-08-15 00:00:00' AND '2015-08-15 23:59:59';
-- → look at "Processed X rows" in the client: ~1/90 of the table

-- 6. Filter outside the key → full scan (every row)
SELECT count(), round(avg(total_amount), 2)
FROM trips
WHERE dropoff_ntaname = 'Airport';
-- → "Processed 3.00 million rows"

-- 7. Partitions: cheap management operations (metadata, no data rewrite)
SELECT DISTINCT partition FROM system.parts WHERE database='demo' AND table='trips' AND active;
ALTER TABLE trips DROP PARTITION 201507;   -- deletes July 2015 instantly
SELECT toYYYYMM(pickup_datetime) AS month, count() FROM trips GROUP BY month ORDER BY month;
