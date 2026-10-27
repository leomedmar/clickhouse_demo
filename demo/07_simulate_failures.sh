#!/usr/bin/env bash
# ============================================================
# DEMO 6 — "What if a container dies?"
# Requires: demo 5 (06_cluster_shards_replicas.sql) already run.
# Usage: bash 07_simulate_failures.sh     (pauses between scenarios when run in a terminal)
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.."             # docker-compose.yml folder

# Hard limit per query: GNU timeout (Linux, Git Bash), gtimeout (macOS + coreutils) or none (plain macOS)
if command -v timeout >/dev/null 2>&1; then limit=(timeout 30)
elif command -v gtimeout >/dev/null 2>&1; then limit=(gtimeout 30)
else limit=(); fi

q() {  # q <node> <sql>   — query on a node; errors summarized in one line
  local out
  out=$(${limit[@]+"${limit[@]}"} docker exec "$1" clickhouse-client --receive_timeout=15 -q "$2" </dev/null 2>&1)
  if [ $? -ne 0 ] || grep -q "Exception" <<<"$out"; then
    echo "      ❌ ERROR $(grep -oE 'Code: [0-9]+' <<<"$out" | head -1) $(grep -oE '\([A-Z_]{5,}\)' <<<"$out" | tail -1)"
    [ -z "$out" ] && echo "      ❌ no response (timeout)"
  else
    grep -v '^[[:space:]]*$' <<<"$out" | sed -e 's/^/      /'
  fi
}
title() { echo; echo "=================================================="; echo "  $*"; echo "=================================================="; }
pause() { if [ -t 0 ]; then read -rp "  [${1:-Press Enter to continue}] " _; fi; }
nodes() { docker ps -a --format '   {{.Names}}  {{.Status}}' --filter name=clickhouse- --filter name=keeper- | sort; }
count_q='SELECT count() FROM demo_rep.events'
insert_q='INSERT INTO demo_rep.events SELECT now(), number, '"'"'purchase'"'"', 1 FROM numbers(100000) SETTINGS distributed_foreground_insert = 1'

title "0. Initial state: 4 nodes + 3 keepers"
docker ps --format '   {{.Names}}  {{.Status}}' --filter name=clickhouse --filter name=keeper | sort
echo "   Rows (via Distributed, from clickhouse-1):"; q clickhouse-1 "$count_q"
pause

title "1. ONE replica dies (clickhouse-2) → nothing is lost"
docker stop clickhouse-2 >/dev/null
nodes
echo "   SELECT still works (shard 1 answers through clickhouse-1):"; q clickhouse-1 "$count_q"
echo "   INSERT still works:"; q clickhouse-1 "$insert_q"; q clickhouse-1 "$count_q"
pause

title "2. The replica comes back → it catches up on its own"
docker start clickhouse-2 >/dev/null; sleep 10
q clickhouse-2 "SYSTEM SYNC REPLICA demo_rep.events_local"
echo "   Local rows on each node (clickhouse-1 and clickhouse-2 must match):"
q clickhouse-1 "SELECT hostName(), getMacro('shard'), count() FROM clusterAllReplicas('cluster_study', demo_rep.events_local) GROUP BY 1,2 ORDER BY 1 FORMAT PrettyCompactMonoBlock"
pause

title "3. One replica of EACH shard dies (clickhouse-2 and clickhouse-4)"
docker stop clickhouse-2 clickhouse-4 >/dev/null
nodes
echo "   Cluster still complete — each shard still has 1 live copy:"; q clickhouse-1 "$count_q"
pause "Press Enter to bring clickhouse-2 and clickhouse-4 back"
docker start clickhouse-2 clickhouse-4 >/dev/null; sleep 10
echo "   Back:"; nodes
pause

title "4. A WHOLE SHARD dies (clickhouse-3 and clickhouse-4)"
docker stop clickhouse-3 clickhouse-4 >/dev/null
nodes
# Fail fast on the dead hosts: with the default retries a query to a stopped container can take
# 15–45 s on Docker Desktop (connections hang until timeout instead of being refused).
fast_fail='connections_with_failover_max_tries = 1, connect_timeout_with_failover_ms = 500'
echo "   By default the query FAILS (better an error than a wrong number):"; q clickhouse-1 "$count_q SETTINGS $fast_fail"
echo "   With skip_unavailable_shards = 1 it answers, but with only half the data:"
q clickhouse-1 "$count_q SETTINGS skip_unavailable_shards = 1, $fast_fail"
pause "Press Enter to bring shard 2 (clickhouse-3 and clickhouse-4) back"
docker start clickhouse-3 clickhouse-4 >/dev/null; sleep 10
echo "   Shard back:"; q clickhouse-1 "$count_q"
pause

title "5. ONE keeper dies (keeper-1) → 2/3 majority holds, everything works"
docker stop keeper-1 >/dev/null; sleep 5
nodes
q clickhouse-1 "$insert_q"; q clickhouse-1 "$count_q"
pause

title "6. TWO keepers die → no majority: reads work, writes don't"
docker stop keeper-2 >/dev/null; sleep 5
nodes
echo "   SELECT works:"; q clickhouse-1 "$count_q"
echo "   After the Keeper session timeout (~30 s) the replicas switch to read-only (the alarm to watch):"
sleep 30
q clickhouse-1 "SELECT hostName() AS node, is_readonly FROM clusterAllReplicas('cluster_study', system.replicas) WHERE database='demo_rep' ORDER BY node FORMAT PrettyCompactMonoBlock"
echo "   INSERT fails (the replicas cannot coordinate):"
# insert_keeper_max_retries = 0 → fails right away; by default the INSERT keeps retrying and
# may end up written when Keeper comes back (client timeout ≠ lost INSERT!)
q clickhouse-1 "INSERT INTO demo_rep.events_local SETTINGS insert_keeper_max_retries = 0 VALUES (now(), 1, 'purchase', 1)"
pause "Press Enter to bring keeper-1 and keeper-2 back"
docker start keeper-1 keeper-2 >/dev/null
echo "   Keepers back — waiting for the replicas to reconnect..."
for i in $(seq 1 30); do
  ro=$(docker exec clickhouse-1 clickhouse-client -q "SELECT sum(is_readonly) FROM clusterAllReplicas('cluster_study', system.replicas) WHERE database='demo_rep'" </dev/null 2>/dev/null)
  [ "$ro" = "0" ] && break; sleep 3
done
q clickhouse-1 "$insert_q"; q clickhouse-1 "$count_q"

title "Done — everything back to normal"
docker ps --format '   {{.Names}}  {{.Status}}' --filter name=clickhouse --filter name=keeper | sort
