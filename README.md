# ClickHouse Lab — 2 shards × 2 replicas on Docker

A local ClickHouse cluster for learning and live demos, with tested demo scripts that go
from a first table to a fault-tolerant 2 × 2 cluster.

- **ClickHouse 25.8 LTS** — 4 server nodes: 2 shards × 2 replicas
- **ClickHouse Keeper** — 3 nodes (Raft quorum) for replication and `ON CLUSTER` DDL
- Everything runs on one laptop with `docker compose`

---

## 1. Requirements

| | |
|---|---|
| Docker | Docker Engine 24+ or Docker Desktop, with **Compose v2** (`docker compose`, not `docker-compose`) |
| OS | **Linux**, **macOS** (Intel or Apple Silicon) or **Windows** (WSL2 or Git Bash) — `./cluster.sh` picks the right compose files |
| Shell | `bash` (macOS's built-in bash 3.2 is fine) |
| Resources | ~4 GB free RAM, ~2 GB disk |
| Network | Internet to pull images (`clickhouse/clickhouse-server:25.8`, `clickhouse/clickhouse-keeper:25.8`) and for the NYC Taxi demo (public S3 bucket) |
| Free ports (localhost) | 8123–8126 (HTTP) and 9000–9003 (native protocol) |
| Optional | `curl` (HTTP demo) |

### One command per OS: `./cluster.sh`

`./cluster.sh` runs `docker compose` with the right files for the machine, so the same commands
work everywhere (`./cluster.sh up -d`, `ps`, `stop`, `down`, `logs -f clickhouse-1` …):

| OS | Detected as | Compose files | ClickHouse data |
|---|---|---|---|
| Linux, or WSL2 with the project in the WSL filesystem (`~/…`) | `linux` | `docker-compose.yml` | bind mounts `./<node>/data` |
| macOS (Docker Desktop, Intel/Apple Silicon) | `mac` | + `docker-compose.mac.yml` | named Docker volumes |
| Windows Git Bash, or WSL2 with the project under `/mnt/c/…` | `windows` | + `docker-compose.windows.yml` | named Docker volumes |

Why named volumes on Docker Desktop: NTFS bind mounts break ClickHouse's atomic part renames
(`filesystem error: in rename: Permission denied`), and macOS bind mounts (VirtioFS) are slow for
ClickHouse's many small files. Force a mode with `CLUSTER_OS=linux|mac|windows ./cluster.sh …`.

> **Windows tip:** the fastest option is the WSL2 filesystem (e.g. `~/docker_study`, with Docker
> Desktop → Settings → Resources → WSL integration enabled for your distro) — it behaves exactly like Linux.

Validated on 2026-10-21: **Linux** (Ubuntu on WSL2, project on ext4, fresh install) and **Windows**
(Git Bash, Docker Desktop 29.8, project under `C:\`) — `validate_demos.sh --failures` passes on both.
**macOS** not run on a Mac yet: the compose override and the bash 3.2 compatibility of the scripts
were checked, but do a rehearsal on the Mac before presenting from it.

---

## 2. Copy the project to another machine

Copy **only the configuration and scripts** — never the `*/data` and `*/logs` folders.
They hold the runtime state of this specific cluster (including Keeper metadata) and are
owned by the container user (uid 101), so copying them usually fails and would break a
fresh cluster anyway.

From the parent folder of the project:

```bash
tar czf docker_study.tgz \
  --exclude='docker_study/*/data' \
  --exclude='docker_study/*/logs' \
  --exclude='docker_study/.env' \
  --exclude='docker_study/config/client/config.xml' \
  docker_study
```

The archive is ~30 KB (no data, no secrets). On the target machine:

```bash
tar xzf docker_study.tgz
cd docker_study
```

(`.gitignore` already excludes the same files if you prefer to use git.)

---

## 3. Install and start

```bash
cd docker_study

./setup.sh                 # 1. one-time: folders + random password (.env) + client config
./cluster.sh up -d         # 2. start 3 keepers + 4 ClickHouse servers (right files for your OS)
./cluster.sh ps            # 3. all 7 containers should be "Up"
```

What `setup.sh` does (safe to re-run):
1. Creates `keeper-N/{data,logs}` and `clickhouse-N/{data,logs}`.
2. Creates `.env` with a random password for the ClickHouse `default` user (keeps an existing one).
3. Generates `config/client/config.xml` with the same password, so `clickhouse-client`
   **inside** the containers connects without asking for it.

Wait ~15–20 seconds after `up -d`, then check the cluster:

```bash
docker exec -it clickhouse-1 clickhouse-client
```

```sql
SELECT cluster, shard_num, replica_num, host_name, errors_count
FROM system.clusters
WHERE cluster = 'cluster_study';
```

Expected: 4 rows (shards 1 and 2, replicas 1 and 2), `errors_count = 0`.

Full end-to-end check (creates demo tables, verifies, cleans up):

```bash
bash demo/validate_demos.sh            # demos 1–5, ~15–60 s (depends on network)
bash demo/validate_demos.sh --failures   # + node-failure scenarios, ~2 min more
```

It must end with `OK — all demos ran without errors.`

---

## 4. Architecture

```
                          SELECT / INSERT
                                 │
                 ┌────── Distributed table ─────┐
                 │  "router": stores no data,   │
                 │  exists on every node        │
                 └──────────────────────────────┘
                │                                  │
                ▼                                  ▼
┌────────── SHARD 1 ───────────┐   ┌────────── SHARD 2 ───────────┐
│ clickhouse-1 ⇄ clickhouse-2  │   │ clickhouse-3 ⇄ clickhouse-4  │
│   replica_1     replica_2    │   │   replica_1     replica_2    │
│      (~half the data)        │   │      (~other half)           │
└──────────────────────────────┘   └──────────────────────────────┘
        ReplicatedMergeTree tables — hold the data

   keeper-1    keeper-2    keeper-3   (coordination, majority 2/3)
```

| Container | Role | HTTP port | Native port |
|---|---|---|---|
| `keeper-1`, `keeper-2`, `keeper-3` | ClickHouse Keeper (Raft) — replication log, distributed DDL | — | — (9181 internal) |
| `clickhouse-1` | shard 1, replica_1 | 127.0.0.1:8123 | 127.0.0.1:9000 |
| `clickhouse-2` | shard 1, replica_2 | 127.0.0.1:8124 | 127.0.0.1:9001 |
| `clickhouse-3` | shard 2, replica_1 | 127.0.0.1:8125 | 127.0.0.1:9002 |
| `clickhouse-4` | shard 2, replica_2 | 127.0.0.1:8126 | 127.0.0.1:9003 |

- Cluster name: **`cluster_study`**.
- Ports are published on **127.0.0.1 only** (not reachable from the office network).
- Fault tolerance: each shard survives the loss of 1 replica; Keeper survives the loss of 1 node.

---

## 5. Project layout

```
docker_study/
├── README.md                      ← this file
├── docker-compose.yml             ← 3 keepers + 4 servers, volumes, ports
├── docker-compose.mac.yml         ← override for macOS (named data volumes)
├── docker-compose.windows.yml     ← override for Windows hosts (named data volumes)
├── cluster.sh                     ← runs docker compose with the right files for the OS
├── setup.sh                       ← one-time setup (folders, password, client config)
├── .env.example                   ← template for .env (setup.sh creates the real one)
├── .env                           ← CH_PASSWORD (generated, secret, not copied)
├── .gitignore
│
├── config/
│   ├── keeper/keeper-config.xml   ← Keeper: Raft cluster of 3 (server id from KEEPER_ID env)
│   ├── server/cluster.xml         ← Keeper endpoints + cluster_study topology (2×2)
│   ├── macros/macros-{1..4}.xml   ← per-node {cluster}, {shard}, {replica} macros
│   └── client/config.xml          ← clickhouse-client credentials (generated by setup.sh)
│
├── keeper-{1..3}/{data,logs}/     ← runtime state (created by setup.sh, not copied)
├── clickhouse-{1..4}/{data,logs}/ ← runtime state (created by setup.sh, not copied)
│
├── backup_config_1s2r/            ← previous topology (1 shard × 2 replicas), reference only
│
└── demo/
    ├── 00_prepare_offline.sh          ← optional: pre-download NYC Taxi files (no-network plan B)
    ├── 01_first_steps.sql             ← Demo 1: database, MergeTree table, 10M rows, compression
    ├── 02_load_files.sh               ← Demo 2a: load CSV via clickhouse-client, HTTP (curl), file()
    ├── 03_load_s3_nyc_taxi.sql        ← Demo 2b: s3() table function, schema inference, 3M real rows
    ├── 04_mergetree_internals.sql     ← Demo 3: parts, merges, sparse index (EXPLAIN), partitions
    ├── 05_alter_and_delete.sql        ← Demo 4: ALTER, lightweight DELETE, UPDATE mutation, ReplacingMergeTree
    ├── 06_cluster_shards_replicas.sql ← Demo 5: ON CLUSTER, ReplicatedMergeTree, Distributed
    ├── 07_simulate_failures.sh        ← Demo 6: stop/start nodes and keepers live, show behaviour
    ├── 99_cleanup.sql                 ← drop all demo databases (all nodes)
    └── validate_demos.sh              ← run everything end-to-end (rehearsal)
```

### How the configuration fits together

| File | What it does |
|---|---|
| `docker-compose.yml` | Two YAML anchors (`x-keeper-defaults`, `x-server-defaults`) share image, network and ulimits. Every server mounts the same `cluster.xml`, its own `macros-N.xml` and the client config. `CLICKHOUSE_PASSWORD` comes from `.env`. |
| `config/keeper/keeper-config.xml` | Same file for the 3 keepers; each one gets its id from the `KEEPER_ID` environment variable. |
| `config/server/cluster.xml` | `<zookeeper>` → the 3 keepers. `<remote_servers>` → `cluster_study` with 2 shards × 2 replicas; inter-node user/password are read with `from_env="CLICKHOUSE_PASSWORD"`. |
| `config/macros/macros-N.xml` | Makes `{shard}`/`{replica}` in DDL resolve per node, so one `CREATE TABLE … ON CLUSTER` works everywhere. |
| `config/client/config.xml` | Lets `docker exec … clickhouse-client` authenticate automatically. **Generated** — re-run `./setup.sh` after changing `.env`. |

### Why the `default` user has a password

Recent ClickHouse Docker images restrict a password-less `default` user to connections
from inside its own container. A sharded cluster needs nodes to query each other
(Distributed tables, `clusterAllReplicas()`), so the lab sets a password through `.env`.
This is a **local lab setup** — in production create dedicated users with RBAC.

---

## 6. Connecting

| Client | Command |
|---|---|
| CLI (any node) | `docker exec -it clickhouse-1 clickhouse-client` (or `clickhouse-2/3/4`) |
| HTTP | `source .env && curl -u "default:$CH_PASSWORD" 'http://localhost:8123/?query=SELECT+version()'` |
| DBeaver / DataGrip | ClickHouse driver, host `localhost`, port `8123`, user `default`, password from `.env` |
| Python | `clickhouse-connect`: `get_client(host='localhost', port=8123, username='default', password=...)` |

---

## 7. Demos

Ten scripts in `demo/` take you from a single table to a fault-tolerant cluster (≈ 30 min live):

| Demo | Script | What it shows |
|---|---|---|
| 1 | `01_first_steps.sql` | Database, MergeTree table, 10M rows in seconds, compression per column |
| 2a | `02_load_files.sh` | Load a CSV three ways: `clickhouse-client`, HTTP (`curl`), `file()` |
| 2b | `03_load_s3_nyc_taxi.sql` | `s3()` table function, schema inference, 3M real NYC Taxi trips |
| 3 | `04_mergetree_internals.sql` | Parts, merges, sparse index (`EXPLAIN indexes = 1`), partitions |
| 4 | `05_alter_and_delete.sql` | ALTER, lightweight DELETE, UPDATE mutations, ReplacingMergeTree |
| 5 | `06_cluster_shards_replicas.sql` | `ON CLUSTER`, ReplicatedMergeTree, Distributed, asynchronous replication |
| 6 | `07_simulate_failures.sh` | Stop replicas, a whole shard and Keeper nodes — and see what still works |

### Running the demos

Demos depend on each other — run them **in order** (`01` → `07`). SQL demos can be run
whole, or pasted query-by-query into an interactive client (recommended live: the
interactive client prints `Processed N rows … (X rows/s.)`).

```bash
# whole file
docker exec -i clickhouse-1 clickhouse-client --multiquery < demo/01_first_steps.sql
# shell demos
bash demo/02_load_files.sh
bash demo/07_simulate_failures.sh        # pauses between scenarios (press Enter)
# reset
docker exec -i clickhouse-1 clickhouse-client --multiquery < demo/99_cleanup.sql
```

`07_simulate_failures.sh` really stops and starts containers (`docker stop/start`) and restores
everything at the end. If you interrupt it with Ctrl+C, run `./cluster.sh up -d` to bring
any stopped node back.

---

## 8. Day-to-day operations

```bash
./cluster.sh up -d                  # start
./cluster.sh stop                   # stop (keeps containers and data)
./cluster.sh down                   # remove containers (data is kept)
./cluster.sh logs -f clickhouse-1   # follow logs (also in clickhouse-1/logs/)
./cluster.sh ps
```

**Full reset** (delete all data and start from an empty cluster).

macOS / Windows (named volumes):

```bash
./cluster.sh down -v        # -v also removes the named data volumes
./cluster.sh up -d
```

Linux (bind mounts — files are owned by the container user, so delete them through a container):

```bash
./cluster.sh down
docker run --rm -v "$PWD":/x alpine sh -c 'rm -rf /x/keeper-*/data/* /x/keeper-*/logs/* /x/clickhouse-*/data/* /x/clickhouse-*/logs/*'
./cluster.sh up -d
```

> Always reset **keepers and servers together** — wiping only one side leaves
> replication metadata out of sync.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `required variable CH_PASSWORD is missing` on `docker compose up` | No `.env` | `./setup.sh` |
| `Authentication failed` from `docker exec … clickhouse-client` | `config/client/config.xml` out of sync with `.env` | `./setup.sh && ./cluster.sh up -d` |
| `Authentication failed` / HTTP 401 from `curl` | Missing credentials | `source .env; curl -u "default:$CH_PASSWORD" …` |
| `Bind for 127.0.0.1:8123 failed: port is already allocated` | Another ClickHouse/service running | Stop it, or publish clickhouse-1 on other ports (see the comment at the top of `docker-compose.mac.yml` / `docker-compose.windows.yml`) and set `CH_HTTP_PORT` in `.env` |
| `filesystem error: in rename: Permission denied` on the first INSERT | Data folders bind-mounted from an NTFS path (`C:\…`) | Start through `./cluster.sh` (uses named volumes on Windows), or move the project into the WSL2 filesystem |
| Failure demo: queries to a stopped shard take 15–45 s | Docker Desktop lets connections to stopped containers hang until timeout | `07_simulate_failures.sh` already uses `connections_with_failover_max_tries = 1, connect_timeout_with_failover_ms = 500`; add them when testing by hand |
| `errors_count > 0` in `system.clusters` or `is_readonly = 1` in `system.replicas` | A node or a Keeper majority is down | `./cluster.sh ps`; `./cluster.sh up -d`; wait ~30 s |
| `Table … already exists` when running a demo | Demo already ran | Run `99_cleanup.sql` (see above) |
| NYC Taxi load (demo 2b) is slow or fails | Network / S3 access | Run `00_prepare_offline.sh` beforehand; use block 4b (`file()`) in `03_load_s3_nyc_taxi.sql`. `validate_demos.sh` switches to it automatically when the files exist |

---

## 10. Related material

- ClickHouse documentation: <https://clickhouse.com/docs>
- ClickHouse Academy: <https://learn.clickhouse.com/>
