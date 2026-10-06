#!/bin/bash
set -e

# Enable extensions after database is ready
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Vector similarity search
    CREATE EXTENSION IF NOT EXISTS vector;

    -- PostGIS core, raster, topology and SFCGAL support
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS postgis_raster;
    CREATE EXTENSION IF NOT EXISTS postgis_topology;
    CREATE EXTENSION IF NOT EXISTS postgis_sfcgal;

    -- TimescaleDB for time-series data
    CREATE EXTENSION IF NOT EXISTS timescaledb;

    -- Apache AGE graph database
    CREATE EXTENSION IF NOT EXISTS age;

    -- Load AGE in every session and expose its catalog without manual LOAD/SET
    ALTER SYSTEM SET session_preload_libraries = 'age';
    ALTER DATABASE "$POSTGRES_DB" SET search_path = ag_catalog, "\$user", public;
EOSQL

# Opt-in resource tuning (shared_buffers, work_mem, maintenance_work_mem, workers, ...).
#   TIMESCALEDB_TUNE=true   run timescaledb-tune once, on first start
#   TS_TUNE_MEMORY=4GB      memory to tune for (default: container memory limit, else host memory)
#   TS_TUNE_NUM_CPUS=4      CPUs to tune for (default: container CPU limit, else host CPUs)
if [ "${TIMESCALEDB_TUNE:-false}" = "true" ]; then
    memory="${TS_TUNE_MEMORY:-}"
    cpus="${TS_TUNE_NUM_CPUS:-}"

    # Inside a container the tool would otherwise see the host's memory and CPUs.
    if [ -z "$memory" ] && [ -r /sys/fs/cgroup/memory.max ]; then
        limit="$(cat /sys/fs/cgroup/memory.max)"
        if [ "$limit" != "max" ]; then
            memory="$((limit / 1024 / 1024))MB"
        fi
    fi
    if [ -z "$cpus" ] && [ -r /sys/fs/cgroup/cpu.max ]; then
        read -r quota period < /sys/fs/cgroup/cpu.max
        if [ "$quota" != "max" ]; then
            cpus="$(( (quota + period - 1) / period ))"
        fi
    fi

    args=(--quiet --yes --conf-path="$PGDATA/postgresql.conf")
    [ -n "$memory" ] && args+=(--memory="$memory")
    [ -n "$cpus" ] && args+=(--cpus="$cpus")

    echo "init.sh: running timescaledb-tune ${args[*]}"
    timescaledb-tune "${args[@]}"
fi
