#!/usr/bin/env bash
# ============================================================
# DEMO 2a — Load local files (CSV) — 3 ways
# Run from the host: bash 02_load_files.sh
# ============================================================
set -euo pipefail
CH="docker exec -i clickhouse-1 clickhouse-client"

# Sample file
cat > /tmp/customers.csv <<'CSV'
id,name,country,signup_date
1,Ana Silva,PT,2025-03-10
2,Bruno Costa,PT,2025-04-22
3,Carmen Ruiz,ES,2025-05-01
4,Didier Martin,FR,2025-06-15
5,Eva Schmidt,DE,2025-07-30
CSV

$CH --query "
DROP TABLE IF EXISTS demo.customers SYNC"
$CH --query "
CREATE TABLE demo.customers (
    id           UInt32,
    name         String,
    country      LowCardinality(String),
    signup_date  Date
) ENGINE = MergeTree ORDER BY id"

# Way 1 — clickhouse-client reads from stdin (the most common in scripts/ETL)
$CH --query "INSERT INTO demo.customers FORMAT CSVWithNames" < /tmp/customers.csv

# Way 2 — HTTP (port 8123, or CH_HTTP_PORT from .env): any language/tool that can send a POST
#   The password of the "default" user is in docker_study's .env (CH_PASSWORD)
source "$(dirname "$0")/../.env"
CH_HTTP="http://localhost:${CH_HTTP_PORT:-8123}"
curl -s -u "default:$CH_PASSWORD" --data-binary @/tmp/customers.csv \
  "$CH_HTTP/?query=INSERT%20INTO%20demo.customers%20FORMAT%20CSVWithNames"

# Way 3 — read the file directly with the file() table function
#         (the file must be in the server's /var/lib/clickhouse/user_files/)
docker cp /tmp/customers.csv clickhouse-1:/var/lib/clickhouse/user_files/customers.csv
$CH --query "SELECT * FROM file('customers.csv', CSVWithNames)"         # query without loading
$CH --query "DESCRIBE file('customers.csv', CSVWithNames)"              # inferred schema
$CH --query "INSERT INTO demo.customers SELECT * FROM file('customers.csv', CSVWithNames)"

# Result: 15 rows (5 x 3 loads)
$CH --query "SELECT count() FROM demo.customers"

# Bonus — exporting works the same way: pick the FORMAT
curl -s -u "default:$CH_PASSWORD" \
  "$CH_HTTP/?query=SELECT%20*%20FROM%20demo.customers%20LIMIT%203%20FORMAT%20JSONEachRow"
$CH --query "SELECT * FROM demo.customers LIMIT 3 FORMAT Pretty"
