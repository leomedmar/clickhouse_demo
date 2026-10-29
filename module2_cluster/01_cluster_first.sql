-- ============================================================
-- MODULE 2 / 1 — Cluster first: everything is created ON CLUSTER from the start
-- Run in: docker exec -it clickhouse-1 clickhouse-client
--
-- Rule of thumb: on a cluster, DDL always carries ON CLUSTER cluster_study,
-- and data tables are Replicated*MergeTree (+ a Distributed table on top).
-- ============================================================

-- 1. Database on all 4 nodes
CREATE DATABASE IF NOT EXISTS lab ON CLUSTER cluster_study;

-- 2. LOCAL tables (store the data; one copy per replica, one slice per shard)
--    {shard} / {replica} come from each node's macros.
CREATE TABLE lab.events_user_local ON CLUSTER cluster_study (
    ts       DateTime,
    user_id  UInt32,
    event    LowCardinality(String),
    value    Float64
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/lab/events_user_local', '{replica}')
PARTITION BY toYYYYMM(ts)
ORDER BY (event, ts);

CREATE TABLE lab.events_rand_local ON CLUSTER cluster_study
AS lab.events_user_local
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/lab/events_rand_local', '{replica}')
PARTITION BY toYYYYMM(ts)
ORDER BY (event, ts);

-- 3. DISTRIBUTED tables (store nothing: they route INSERTs and fan out SELECTs)
--    3a. cityHash64(user_id) → deterministic: the same user always lands on the same shard
--        (good for per-user queries/joins; can be uneven if the key is skewed)
CREATE TABLE lab.events_by_user ON CLUSTER cluster_study
AS lab.events_user_local
ENGINE = Distributed(cluster_study, lab, events_user_local, cityHash64(user_id));

--    3b. rand() → random: even spread, but no locality
--        (a user's rows end up on every shard)
CREATE TABLE lab.events_by_rand ON CLUSTER cluster_study
AS lab.events_rand_local
ENGINE = Distributed(cluster_study, lab, events_rand_local, rand());

-- 4. Same 1 M rows into each Distributed table
INSERT INTO lab.events_by_user
SELECT now() - toIntervalSecond(rand() % 86400), number % 10000,
       ['login','purchase','logout','search'][rand() % 4 + 1], round(randUniform(1, 500), 2)
FROM numbers(1000000)
SETTINGS distributed_foreground_insert = 1;   -- demo only: wait until it reaches the shards

INSERT INTO lab.events_by_rand
SELECT now() - toIntervalSecond(rand() % 86400), number % 10000,
       ['login','purchase','logout','search'][rand() % 4 + 1], round(randUniform(1, 500), 2)
FROM numbers(1000000)
SETTINGS distributed_foreground_insert = 1;

-- 5. Rows per shard (the 2 replicas of a shard hold the same copy, so we look at replica_1 only)
SELECT * FROM (
SELECT 'cityHash64(user_id)' AS sharding_key, getMacro('shard') AS shard, count() AS row_count
FROM clusterAllReplicas('cluster_study', lab.events_user_local)
WHERE getMacro('replica') = 'replica_1' GROUP BY shard
UNION ALL
SELECT 'rand()', getMacro('shard') AS shard, count()
FROM clusterAllReplicas('cluster_study', lab.events_rand_local)
WHERE getMacro('replica') = 'replica_1' GROUP BY shard
)
ORDER BY sharding_key, shard;

-- 6. Locality: in how many shards does user 42 live?
--    cityHash64 → 1 shard; rand() → both
SELECT 'cityHash64(user_id)' AS sharding_key, uniqExact(getMacro('shard')) AS shards_with_user_42
FROM clusterAllReplicas('cluster_study', lab.events_user_local) WHERE user_id = 42
UNION ALL
SELECT 'rand()', uniqExact(getMacro('shard'))
FROM clusterAllReplicas('cluster_study', lab.events_rand_local) WHERE user_id = 42;

-- 7. One query, the whole cluster
SELECT event, count() AS event_count, round(sum(value)) AS total
FROM lab.events_by_user GROUP BY event ORDER BY event;
