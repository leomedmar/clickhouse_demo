# Module 2 — Cluster first

Same lab, different order: instead of starting on one node and moving to the cluster later,
every object is created **on the cluster from the first statement** (`ON CLUSTER cluster_study`,
`Replicated*MergeTree`, `Distributed`). Run after `./cluster.sh up -d`. Independent of `demo/`.

| File | What it shows |
|---|---|
| `01_cluster_first.sql` | Database + replicated local tables + two Distributed tables: sharding key `cityHash64(user_id)` (same user → same shard) vs `rand()` (even spread, no locality); rows per shard; locality check |
| `02_filesystem_locations.sql` | Where tables, parts and files live on disk (`system.tables.data_paths`, `metadata_path`, `system.parts.path`) and in Keeper (`system.replicas.zookeeper_path`) |
| `03_keeper_commands.sh` | Keeper from the command line: 4-letter words (`ruok`, `srvr`, `mntr`), `clickhouse-keeper-client` (`ls`, `get`, `get_stat`), and `system.zookeeper` |
| `99_cleanup.sql` | `DROP DATABASE lab ON CLUSTER … SYNC` |

```bash
docker exec -i clickhouse-1 clickhouse-client --multiquery < module2_cluster/01_cluster_first.sql
docker exec -i clickhouse-1 clickhouse-client --multiquery < module2_cluster/02_filesystem_locations.sql
bash module2_cluster/03_keeper_commands.sh
docker exec -i clickhouse-1 clickhouse-client --multiquery < module2_cluster/99_cleanup.sql
```
