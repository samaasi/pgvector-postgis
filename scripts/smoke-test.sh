#!/usr/bin/env bash
# Smoke test for a built image: starts it, waits for the healthcheck, then exercises
# every extension plus the hardened defaults.
#   scripts/smoke-test.sh <image> [extra docker run args...]
set -euo pipefail

image="${1:?usage: smoke-test.sh <image> [extra docker run args...]}"
shift || true
name="smoke-$$"

cleanup() {
  if [ "${SMOKE_KEEP:-}" != "true" ]; then
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

psql_q() { MSYS_NO_PATHCONV=1 docker exec "$name" psql -U postgres -v ON_ERROR_STOP=1 -tA "$@"; }

docker run -d --name "$name" -e POSTGRES_PASSWORD=smoke "$@" "$image" >/dev/null

status=starting
for _ in $(seq 1 90); do
  status="$(docker inspect -f '{{.State.Health.Status}}' "$name")"
  [ "$status" = healthy ] && break
  [ "$(docker inspect -f '{{.State.Running}}' "$name")" = false ] && break
  sleep 2
done
if [ "$status" != healthy ]; then
  echo "FAIL: container not healthy (status=$status)"; docker logs --tail 40 "$name"; exit 1
fi

fail=0
check() { # check <description> <expected> <sql>
  local got
  got="$(psql_q -c "$3" 2>&1 | grep -v '^NOTICE' | tr -d '\r' | tail -n 1)" || true
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected '$2', got '$got')"; fail=1; fi
}

check "extensions installed" "age,plpgsql,postgis,postgis_raster,postgis_sfcgal,postgis_topology,timescaledb,vector" \
  "SELECT string_agg(extname, ',' ORDER BY extname) FROM pg_extension"
check "pgvector distance"   "1" "SELECT '[1,2]'::vector <-> '[1,3]'::vector"
check "postgis point"       "POINT(1 2)" "SELECT ST_AsText(ST_MakePoint(1,2))"
check "timescaledb hypertable" "m" \
  "CREATE TABLE public.m(t timestamptz NOT NULL); SELECT table_name FROM create_hypertable('public.m','t')"
check "age graph + cypher"  "\"b\"" \
  "SELECT create_graph('smoke'); SELECT * FROM cypher('smoke', \$\$ CREATE (:P)-[:K]->(b:P {n:'b'}) RETURN b.n \$\$) AS (n agtype)"
check "age search_path preset" "ag_catalog, \"\$user\", public" "SHOW search_path"
check "jit off"             "off" "SHOW jit"
check "telemetry off"       "off" "SHOW timescaledb.telemetry_level"
check "wal_compression lz4" "lz4" "SHOW wal_compression"
check "random_page_cost"    "1.1" "SHOW random_page_cost"
check "password encryption" "scram-sha-256" "SHOW password_encryption"

[ "$fail" = 0 ] && echo "All smoke tests passed for $image" || { echo "Smoke tests FAILED for $image"; exit 1; }
