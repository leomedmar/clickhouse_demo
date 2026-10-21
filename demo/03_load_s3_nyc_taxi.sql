-- ============================================================
-- DEMO 2b — Load real data from S3 (NYC Taxi, ~3 million trips)
-- Requires Internet access from the container.
-- ============================================================
USE demo;

-- 1. Peek at the remote file WITHOUT loading anything
SELECT pickup_datetime, pickup_ntaname, dropoff_ntaname, total_amount
FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi/trips_0.gz',
        'TabSeparatedWithNames')
LIMIT 5;

-- 2. Automatically inferred schema: everything Nullable, Int64, String...
--    It works, but wastes space and CPU → in production we define the types.
DESCRIBE s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi/trips_0.gz',
            'TabSeparatedWithNames');

-- 3. Table with well-chosen types
CREATE TABLE trips (
    trip_id          UInt32,
    pickup_datetime  DateTime,
    dropoff_datetime DateTime,
    pickup_longitude Nullable(Float64),
    pickup_latitude  Nullable(Float64),
    passenger_count  UInt8,
    trip_distance    Float32,
    fare_amount      Float32,
    tip_amount       Float32,
    total_amount     Float32,
    payment_type     Enum8('CSH' = 1, 'CRE' = 2, 'NOC' = 3, 'DIS' = 4, 'UNK' = 5),
    pickup_ntaname   LowCardinality(String),
    dropoff_ntaname  LowCardinality(String)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(pickup_datetime)
ORDER BY (pickup_datetime, pickup_ntaname);

-- 4. Load 3 files (trips_0, trips_1, trips_2) in a single INSERT
INSERT INTO trips
SELECT
    trip_id, pickup_datetime, dropoff_datetime,
    pickup_longitude, pickup_latitude, passenger_count,
    trip_distance, fare_amount, tip_amount, total_amount,
    payment_type, pickup_ntaname, dropoff_ntaname
FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi/trips_{0..2}.gz',
        'TabSeparatedWithNames');

-- 4b. PLAN B (no network): same files, downloaded beforehand with 00_prepare_offline.sh
--     Use THIS INSERT instead of step 4:
-- INSERT INTO trips
-- SELECT
--     trip_id, pickup_datetime, dropoff_datetime,
--     pickup_longitude, pickup_latitude, passenger_count,
--     trip_distance, fare_amount, tip_amount, total_amount,
--     payment_type, pickup_ntaname, dropoff_ntaname
-- FROM file('nyc/trips_{0..2}.gz', 'TabSeparatedWithNames');

-- 5. Check
SELECT formatReadableQuantity(count()) AS trip_count FROM trips;

SELECT
    formatReadableSize(sum(data_uncompressed_bytes)) AS original,
    formatReadableSize(sum(data_compressed_bytes))   AS on_disk,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 1) AS ratio
FROM system.columns
WHERE database = 'demo' AND table = 'trips';

-- 6. Business questions
-- Neighborhoods with the most pickups
SELECT pickup_ntaname, count() AS trip_count, round(avg(total_amount), 2) AS avg_total
FROM trips
GROUP BY pickup_ntaname
ORDER BY trip_count DESC
LIMIT 10;

-- Trips and average tip per hour of the day
SELECT
    toHour(pickup_datetime)         AS hour,
    count()                         AS trip_count,
    round(avg(tip_amount), 2)       AS avg_tip,
    bar(count(), 0, 250000, 40)     AS chart
FROM trips
GROUP BY hour
ORDER BY hour;

-- Most profitable routes
SELECT
    pickup_ntaname,
    dropoff_ntaname,
    count()                     AS trip_count,
    round(sum(total_amount))    AS revenue
FROM trips
WHERE pickup_ntaname != '' AND dropoff_ntaname != ''
GROUP BY pickup_ntaname, dropoff_ntaname
ORDER BY revenue DESC
LIMIT 10;
