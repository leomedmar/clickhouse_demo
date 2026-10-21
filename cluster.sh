#!/usr/bin/env bash
# Runs `docker compose` with the right files for this operating system.
#
#   ./cluster.sh up -d          # start the cluster
#   ./cluster.sh ps             # status
#   ./cluster.sh stop           # stop (keeps containers and data)
#   ./cluster.sh down           # remove containers (data is kept)
#   ./cluster.sh down -v        # remove containers AND the named data volumes (macOS/Windows)
#   ./cluster.sh logs -f clickhouse-1
#
# Detection (override with CLUSTER_OS=linux|mac|windows):
#   Linux (incl. WSL2 with the project in the WSL filesystem) → docker-compose.yml (bind mounts)
#   macOS                                                       → + docker-compose.mac.yml
#   Windows (Git Bash) or WSL2 with the project under /mnt/<drive> → + docker-compose.windows.yml
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -eq 0 ]; then
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

os=${CLUSTER_OS:-}
if [ -z "$os" ]; then
  case "$(uname -s)" in
    Darwin)               os=mac ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    Linux)                case "$PWD" in /mnt/[a-z]/*) os=windows ;; *) os=linux ;; esac ;;
    *)                    os=linux ;;
  esac
fi

files=(-f docker-compose.yml)
case "$os" in
  linux)   ;;
  mac)     files+=(-f docker-compose.mac.yml) ;;
  windows) files+=(-f docker-compose.windows.yml) ;;
  *) echo "Unknown CLUSTER_OS='$os' (use linux, mac or windows)" >&2; exit 1 ;;
esac

[ -f .env ] || { echo "No .env found — run ./setup.sh first." >&2; exit 1; }
echo ">> [$os] docker compose ${files[*]} $*" >&2
exec docker compose "${files[@]}" "$@"
