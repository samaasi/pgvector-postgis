#!/bin/bash
set -e

# Enable extensions after database is ready
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS age;

    -- Load AGE in every session and expose its catalog without manual LOAD/SET
    ALTER SYSTEM SET session_preload_libraries = 'age';
    ALTER DATABASE "$POSTGRES_DB" SET search_path = ag_catalog, "\$user", public;
EOSQL
