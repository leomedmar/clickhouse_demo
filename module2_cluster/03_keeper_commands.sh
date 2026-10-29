#!/usr/bin/env bash
# ============================================================
# MODULE 2 / 3 — Talking to ClickHouse Keeper
# Run from the host: bash 03_keeper_commands.sh   (after 01_cluster_first.sql)
# Everything runs from the clickhouse-1 container, which already has the tools.
# ============================================================
set -uo pipefail
export MSYS_NO_PATHCONV=1
KC="docker exec clickhouse-1 clickhouse-keeper-client -h keeper-1 -p 9181 -q"
CH="docker exec -i clickhouse-1 clickhouse-client"
T=/clickhouse/tables/1/lab/events_user_local    # shard 1 (the {shard} macro of clickhouse-1 is '1')

# 4-letter-word commands over raw TCP (no nc needed): ruok, srvr, mntr, stat, conf
fourlw() { docker exec clickhouse-1 bash -c "exec 3<>/dev/tcp/$1/9181; echo $2 >&3; timeout 2 cat <&3"; }

echo "== 1. Are the 3 keepers alive? (answer: imok)"
for k in keeper-1 keeper-2 keeper-3; do printf "%s: " "$k"; fourlw "$k" ruok; echo; done

echo; echo "== 2. Who is the leader? (Mode: leader | follower)"
for k in keeper-1 keeper-2 keeper-3; do printf "%s: " "$k"; fourlw "$k" srvr | grep -E '^Mode'; done

echo; echo "== 3. Metrics of one keeper"
fourlw keeper-1 mntr | grep -E 'zk_(server_state|znode_count|watch_count|ephemerals_count|synced_followers)'

echo; echo "== 4. Navigate the tree with clickhouse-keeper-client"
$KC "ls '/'"
$KC "ls '/clickhouse'"
$KC "ls '/clickhouse/tables'"
$KC "ls '$T'"
$KC "ls '$T/replicas'"

echo; echo "== 5. Read znodes: get / get_stat"
$KC "get '$T/metadata'"
$KC "get_stat '$T'"
$KC "get '$T/replicas/replica_1/is_active'"

echo; echo "== 6. Replication log and distributed DDL queue"
$KC "ls '$T/log'"
$KC "ls '/clickhouse/task_queue/ddl'"

echo; echo "== 7. The same tree through SQL: system.zookeeper (a path filter is mandatory)"
$CH --query "SELECT name, numChildren, ctime FROM system.zookeeper WHERE path = '/clickhouse/tables' FORMAT PrettyCompactMonoBlock"
$CH --query "SELECT name, value FROM system.zookeeper WHERE path = '$T' AND name IN ('metadata','columns') FORMAT Vertical"
