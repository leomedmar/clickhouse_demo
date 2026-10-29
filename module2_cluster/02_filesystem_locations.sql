-- ============================================================
-- MODULE 2 / 2 — Where are the tables on the filesystem?
-- Paths are INSIDE the container (/var/lib/clickhouse = clickhouse-N/data on the host)
-- ============================================================

-- 1. Metadata (DDL) and data folder of each table on THIS node
--    Atomic database: data lives in store/<first 3 chars of uuid>/<uuid>/
SELECT database, name, uuid, metadata_path, data_paths
FROM system.tables
WHERE database = 'lab'
ORDER BY name;

-- 2. Same, on every node of the cluster (Distributed tables have no data folder of their own)
SELECT hostName() AS node, name, arrayJoin(data_paths) AS data_path
FROM clusterAllReplicas('cluster_study', system.tables)
WHERE database = 'lab' AND name LIKE '%_local'
ORDER BY name, node;

-- 3. One folder per part (immutable), with disk and size
SELECT partition, name AS part, rows, formatReadableSize(bytes_on_disk) AS size, disk_name, path
FROM system.parts
WHERE database = 'lab' AND table = 'events_user_local' AND active
ORDER BY partition, name;

-- 4. The files inside a part: data.bin (data) + data.cmrk4 (marks) in a small "Compact" part;
--    large "Wide" parts have one <column>.bin + <column>.cmrk2 per column. Both have primary.cidx (sparse index)
--    From the host:  docker exec clickhouse-1 ls -la <path from this query>
SELECT hostName() AS node, name, path
FROM system.parts
WHERE database = 'lab' AND table = 'events_user_local' AND active
LIMIT 1;

-- 5. Where does each replicated table live in Keeper? (see 03_keeper_commands.sh)
SELECT hostName() AS node, table, zookeeper_path, replica_path
FROM clusterAllReplicas('cluster_study', system.replicas)
WHERE database = 'lab' AND table = 'events_user_local'
ORDER BY node;
