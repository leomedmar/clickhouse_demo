#!/usr/bin/env bash
# Plan B for Demo 2b: downloads the NYC Taxi files into clickhouse-1's user_files
# (run BEFORE the presentation, with network). Then load with file('nyc/trips_{0..2}.gz', ...).
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash: keep /var/lib/... as a container path (no C:/Program Files/Git/...)
BASE=https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi
docker exec clickhouse-1 mkdir -p /var/lib/clickhouse/user_files/nyc
for i in 0 1 2; do
  echo ">> trips_$i.gz"
  docker exec clickhouse-1 wget -q -c -O /var/lib/clickhouse/user_files/nyc/trips_$i.gz "$BASE/trips_$i.gz"
done
docker exec clickhouse-1 ls -lh /var/lib/clickhouse/user_files/nyc/
docker exec clickhouse-1 clickhouse-client -q \
  "SELECT formatReadableQuantity(count()) AS total_rows FROM file('nyc/trips_{0..2}.gz', 'TabSeparatedWithNames')" </dev/null
