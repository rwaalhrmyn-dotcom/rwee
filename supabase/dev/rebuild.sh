#!/usr/bin/env bash
# Rebuild the local development database from the repository's migrations.
# Usage: supabase/dev/rebuild.sh [dbname]   (runs psql as the postgres OS user)
set -euo pipefail
DB="${1:-rwaa_dev}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PSQL=(su postgres -c)
run() { su postgres -c "psql -v ON_ERROR_STOP=1 -q -X -d $DB -f '$1'" >/dev/null || { echo "FAILED: $1"; exit 1; }; }
su postgres -c "psql -q -X -d postgres -c 'drop database if exists $DB with (force)' -c 'create database $DB'" >/dev/null
run "$HERE/00_supabase_shim.sql"
for f in $(ls "$ROOT/migrations"/*.sql | sort); do run "$f"; done
for f in $(ls "$HERE/seed"/*.sql 2>/dev/null | sort); do run "$f"; done
echo "rebuilt $DB OK"
