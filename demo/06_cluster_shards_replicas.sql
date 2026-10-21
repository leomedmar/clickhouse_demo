-- ============================================================
-- DEMO 5 — Cluster: 2 shards × 2 replicas (cluster_study)
--
--   shard 1: clickhouse-1 (replica_1) + clickhouse-2 (replica_2)
--   shard 2: clickhouse-3 (replica_1) + clickhouse-4 (replica_2)
--   keeper-1/2/3: coordination (who has which data, DDL ON CLUSTER)
--
-- Run in: docker exec -it clickhouse-1 clickhouse-client
-- ============================================================

-- 1. The cluster as ClickHouse sees it
SELECT cluster, shard_num, replica_num, host_name
FROM system.clusters
WHERE cluster = 'cluster_study';

-- Each node knows who it is through its macros (config/macros/macros-N.xml)
SELECT hostName() AS node, getMacro('shard') AS shard, getMacro('replica') AS replica
FROM clusterAllReplicas('cluster_study', system.one)
ORDER BY node;

-- 2. DDL on every node at once: ON CLUSTER
CREATE DATABASE IF NOT EXISTS demo_rep ON CLUSTER cluster_study;

-- 2a. Replicated LOCAL table — stores the data (exists on all 4 nodes)
--     {shard} and {replica} are replaced by each node's macros:
--     the 2 replicas of the same shard share the Keeper path → they are copies of each other
CREATE TABLE demo_rep.events_local ON CLUSTER cluster_study (
    ts       DateTime,
    user_id  UInt32,
    event    LowCardinality(String),
    value    Float64
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/demo_rep/events_local', '{replica}')
PARTITION BY toYYYYMM(ts)
ORDER BY (event, ts);

-- 2b. DISTRIBUTED table — stores no data, it is a "router":
--     on INSERT it spreads rows across the shards; on SELECT it asks all of them and merges
CREATE TABLE demo_rep.events ON CLUSTER cluster_study
AS demo_rep.events_local
ENGINE = Distributed(cluster_study, demo_rep, events_local, cityHash64(user_id));
--                                                          ^ sharding key:
--                                 the same user_id always goes to the same shard

-- 3. Insert 1 million rows through the Distributed table
INSERT INTO demo_rep.events
SELECT
    now() - toIntervalSecond(rand() % 86400)                AS ts,
    rand() % 10000                                          AS user_id,
    ['login','purchase','logout','search'][rand() % 4 + 1]  AS event,
    round(randUniform(1, 500), 2)                           AS value
FROM numbers(1000000)
SETTINGS distributed_foreground_insert = 1;   -- demo only: wait until it reaches the shards

-- 4. One query, the whole cluster
SELECT event, count() AS event_count, round(sum(value)) AS total
FROM demo_rep.events
GROUP BY event
ORDER BY event;

-- 5. Replication is asynchronous: the INSERT returns as soon as ONE replica of each shard
--    has the data; the other replica fetches the new parts in the background.
-- 5a. Watch it happen right after the INSERT: parts still queued on some replicas
SELECT
    hostName()        AS node,
    queue_size,                              -- replication tasks still pending
    inserts_in_queue,                        -- of which: parts to fetch from the other replica
    absolute_delay                           -- seconds behind the most up-to-date replica
FROM clusterAllReplicas('cluster_study', system.replicas)
WHERE database = 'demo_rep' AND table = 'events_local'
ORDER BY node;

-- 5b. Give it a moment (demo only — in production nothing to do: replicas catch up by themselves)
SELECT sleep(3) FORMAT Null;

-- 5c. Where is the data? Each shard has ~half; the 2 replicas of a shard hold the same
SELECT
    hostName()           AS node,
    getMacro('shard')    AS shard,
    getMacro('replica')  AS replica,
    count()              AS row_count
FROM clusterAllReplicas('cluster_study', demo_rep.events_local)
GROUP BY node, shard, replica
ORDER BY node;

-- 6. A user always lives in a single shard (because of the sharding key)
SELECT getMacro('shard') AS shard, count() AS events_of_user_42
FROM clusterAllReplicas('cluster_study', demo_rep.events_local)
WHERE user_id = 42
GROUP BY shard;

-- 7. Replication health on every node
SELECT hostName() AS node, table, is_readonly, queue_size, active_replicas, total_replicas
FROM clusterAllReplicas('cluster_study', system.replicas)
WHERE database = 'demo_rep'
ORDER BY node;

-- 8. What if a container dies? → see 07_simulate_failures.sh
