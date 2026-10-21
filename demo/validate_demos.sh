#!/usr/bin/env bash
# Runs every demo end to end (rehearsal before the presentation).
# Usage: bash validate_demos.sh              (demos 1–5, ~15 s)
#        bash validate_demos.sh --failures   (includes demo 6, failures, +2 min)
set -euo pipefail
cd "$(dirname "$0")"
CH="docker exec -i clickhouse-1 clickhouse-client --multiquery"

echo ">> Cleanup"
# Right after the cluster starts, ON CLUSTER DDL can fail until Keeper and the DDL queue are ready
for i in 1 2 3 4 5 6; do
  $CH < 99_cleanup.sql && break
  [ "$i" = 6 ] && { echo "Cluster not ready — check './cluster.sh ps'"; exit 1; }
  echo "   (cluster not ready yet, retrying in 5 s)"; sleep 5
done
echo ">> Demo 1 — first steps";         $CH < 01_first_steps.sql           > /dev/null
echo ">> Demo 2a — CSV files";          bash 02_load_files.sh              > /dev/null
# If the plan B files exist (00_prepare_offline.sh), use file() instead of s3()
if docker exec clickhouse-1 test -s /var/lib/clickhouse/user_files/nyc/trips_2.gz; then
  echo ">> Demo 2b — NYC Taxi (OFFLINE mode, file())"
  sed "s#s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi/#file('nyc/#g" \
    03_load_s3_nyc_taxi.sql | $CH > /dev/null
else
  echo ">> Demo 2b — NYC Taxi (S3, needs network)"
  $CH < 03_load_s3_nyc_taxi.sql > /dev/null
fi
echo ">> Demo 3 — MergeTree";           $CH < 04_mergetree_internals.sql   > /dev/null
echo ">> Demo 4 — ALTER/DELETE";        $CH < 05_alter_and_delete.sql      > /dev/null
echo ">> Demo 5 — cluster 2 shards × 2 replicas"; $CH < 06_cluster_shards_replicas.sql > /dev/null
sleep 2
docker exec clickhouse-1 clickhouse-client </dev/null -q "
  SELECT hostName(), getMacro('shard'), count()
  FROM clusterAllReplicas('cluster_study', demo_rep.events_local)
  GROUP BY 1, 2 ORDER BY 1" | sed 's/^/   /'
echo "   (expected: ~500k per node; replicas of the same shard identical)"
if [ "${1:-}" = "--failures" ]; then
  echo ">> Demo 6 — simulate failures (~2 min)"; bash 07_simulate_failures.sh </dev/null
fi
echo ">> Cleanup";                      $CH < 99_cleanup.sql
echo "OK — all demos ran without errors."
