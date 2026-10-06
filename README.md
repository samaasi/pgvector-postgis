# pgvector-postgis

A production-ready PostgreSQL Docker image combining **pgvector**, **PostGIS**, **TimescaleDB**, and **Apache AGE** — providing vector search, geospatial analysis, time-series, and graph (openCypher) capabilities in a single, hardened container.

## Image Tags

| Tag | PostgreSQL |
|---|---|
| `latest`, `pg18`, `<version>-pg18` | 18 |
| `pg17`, `<version>-pg17` | 17 |

> **Upgrading from PostgreSQL 17:** `latest` now points to PostgreSQL 18. A PG17 data directory cannot be opened by PG18 — pin `pg17`, or migrate with `pg_dump`/restore or `pg_upgrade`.

## Extensions

| Extension | Version Source | Purpose |
|---|---|---|
| **pgvector** (`vector`) | Base image | Vector similarity search (cosine, L2, inner product) for AI/ML embeddings |
| **PostGIS** (`postgis`) | PGDG package | Core geospatial data types and spatial functions |
| **PostGIS Raster** (`postgis_raster`) | PGDG package (bundled) | Raster data types and analysis functions |
| **PostGIS Topology** (`postgis_topology`) | PGDG package (bundled) | Topology types for network and boundary modelling |
| **PostGIS SFCGAL** (`postgis_sfcgal`) | PGDG package (bundled) | Advanced 2D/3D spatial operations |
| **TimescaleDB** (`timescaledb`) | Official TimescaleDB repo | Time-series hypertables, continuous aggregates, compression |
| **Apache AGE** (`age`) | PGDG package | Graph database with openCypher queries |

## Quick Start

### Build the image

```bash
docker build -t pgvector-postgis .

# Or build for PostgreSQL 17
docker build --build-arg PG_MAJOR=17 -t pgvector-postgis:pg17 .
```

### Run the container

```bash
# Keep the password out of the environment: put it in a file instead
printf '%s' 'choose-a-long-random-password' > ./db_password.txt && chmod 600 ./db_password.txt

docker run -d \
  --name postgres \
  --shm-size=1g \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/db_password \
  -e POSTGRES_DB=mydb \
  -v "$PWD/db_password.txt:/run/secrets/db_password:ro" \
  -p 127.0.0.1:5432:5432 \
  -v pgdata:/var/lib/postgresql \
  pgvector-postgis
```

All extensions are automatically enabled on the first start via `init.sh`.

> **Why `-p 127.0.0.1:5432:5432`?** `-p 5432:5432` publishes the port on every network interface and bypasses host firewalls such as UFW. Bind to loopback, or put the database on a private Docker network, unless you really need remote access (and then enable [TLS](#tls)).
>
> **Why `--shm-size=1g`?** Docker gives containers only 64 MB of `/dev/shm`. Parallel queries and parallel HNSW index builds use it, and fail with `could not resize shared memory segment` on large datasets.

> **Volume path:** from PostgreSQL 18 the volume is mounted at `/var/lib/postgresql` (data lives in `/var/lib/postgresql/18/docker`). For the `pg17` image, mount `/var/lib/postgresql/data` instead.

### Docker Compose

```yaml
services:
  postgres:
    build: .
    container_name: postgres
    restart: unless-stopped
    shm_size: 1g                      # default 64 MB is too small for parallel queries / HNSW builds
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
      POSTGRES_DB: mydb
      TIMESCALEDB_TUNE: "true"        # optional: size shared_buffers/work_mem/... for the limits below
    secrets:
      - db_password
    ports:
      - "127.0.0.1:5432:5432"         # loopback only; drop this and use a private network if possible
    volumes:
      - pgdata:/var/lib/postgresql
    deploy:
      resources:
        limits:
          memory: 4g
          cpus: "2"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U myuser -d mydb"]
      interval: 10s
      timeout: 5s
      retries: 5

secrets:
  db_password:
    file: ./db_password.txt

volumes:
  pgdata:
```

## Verify Extensions

Connect to the database and check that all extensions are loaded:

```bash
docker exec -it postgres psql -U myuser -d mydb
```

```sql
SELECT extname, extversion FROM pg_extension ORDER BY extname;
```

Expected output:

```
      extname       | extversion
--------------------+------------
 age                | 1.x.x
 plpgsql            | 1.0
 postgis            | 3.6.x
 postgis_raster     | 3.6.x
 postgis_sfcgal     | 3.6.x
 postgis_topology   | 3.6.x
 timescaledb        | 2.x.x
 vector             | 0.8.x
```

## Usage Examples

### pgvector — Vector Similarity Search

```sql
-- Create a table with a vector column (1536 dimensions, e.g. OpenAI embeddings)
CREATE TABLE documents (
  id BIGSERIAL PRIMARY KEY,
  content TEXT,
  embedding VECTOR(1536)
);

-- Create an HNSW index for fast approximate nearest-neighbour search
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);

-- Find the 5 most similar documents
SELECT id, content, embedding <=> '[0.1, 0.2, ...]'::vector AS distance
FROM documents
ORDER BY distance
LIMIT 5;
```

### PostGIS — Geospatial Queries

```sql
-- Create a table with a geography column
CREATE TABLE locations (
  id BIGSERIAL PRIMARY KEY,
  name TEXT,
  coordinates GEOGRAPHY(POINT, 4326)
);

-- Insert a point (longitude, latitude)
INSERT INTO locations (name, coordinates)
VALUES ('London', ST_MakePoint(-0.1276, 51.5074)::geography);

-- Find all locations within 10km of a point
SELECT name, ST_Distance(coordinates, ST_MakePoint(-0.1276, 51.5074)::geography) AS distance_m
FROM locations
WHERE ST_DWithin(coordinates, ST_MakePoint(-0.1276, 51.5074)::geography, 10000);
```

### TimescaleDB — Time-Series Data

```sql
-- Create a regular table
CREATE TABLE metrics (
  time TIMESTAMPTZ NOT NULL,
  device_id TEXT NOT NULL,
  cpu_usage DOUBLE PRECISION,
  memory_usage DOUBLE PRECISION
);

-- Convert it to a hypertable (automatic time-based partitioning)
SELECT create_hypertable('metrics', by_range('time'));

-- Insert data as usual
INSERT INTO metrics (time, device_id, cpu_usage, memory_usage)
VALUES (NOW(), 'server-01', 72.5, 84.1);

-- Query with time-series functions
SELECT time_bucket('5 minutes', time) AS bucket,
       device_id,
       AVG(cpu_usage) AS avg_cpu,
       MAX(memory_usage) AS max_memory
FROM metrics
WHERE time > NOW() - INTERVAL '1 hour'
GROUP BY bucket, device_id
ORDER BY bucket DESC;
```

### Apache AGE — Graph Queries

AGE is preloaded in every session and `ag_catalog` is on the `search_path` of the default database, so no `LOAD 'age'` is needed. Graph names must be at least 3 characters.

```sql
-- Create a graph
SELECT create_graph('social');

-- Create nodes and a relationship with openCypher
SELECT * FROM cypher('social', $$
  CREATE (a:Person {name: 'Alice'})-[:KNOWS]->(b:Person {name: 'Bob'})
  RETURN a, b
$$) AS (a agtype, b agtype);

-- Traverse the graph
SELECT * FROM cypher('social', $$
  MATCH (p:Person)-[:KNOWS]->(friend)
  RETURN p.name, friend.name
$$) AS (person agtype, friend agtype);
```

> In databases other than `POSTGRES_DB`, run `SET search_path = ag_catalog, "$user", public;` (or `ALTER DATABASE ... SET search_path ...`) before using Cypher.

## Project Structure

```
├── .github/workflows/  # CI/CD pipeline (build, push, scan)
├── Dockerfile          # Multi-extension PostgreSQL image (PG_MAJOR build arg, default 18)
├── init.sh             # Extension initialization + optional tuning (runs on first start)
├── scripts/smoke-test.sh # Starts an image and verifies every extension and default
├── trivy.yaml          # Vulnerability scan configuration (CI and local)
├── renovate.json       # Keeps the pgvector base-image version up to date
├── .dockerignore       # Excludes non-essential files from build context
├── .gitignore          # Git ignore rules
├── CONTRIBUTING.md     # Contribution guidelines
├── LICENSE             # MIT License
└── README.md           # This file
```

## Security

### What the image does

- **Pinned, verified packages** — the TimescaleDB signing key is downloaded and its fingerprint is checked against a pinned value; the build fails if it differs (no `curl | bash`)
- **Patched weekly** — CI rebuilds and republishes every tag weekly (and busts the layer cache) so `apt-get upgrade` really picks up new OS security fixes
- **Scan gate before publish** — each image is built, smoke-tested and scanned with Trivy first; a fixable CRITICAL vulnerability fails the build and nothing is pushed. HIGH/CRITICAL results are uploaded to the repository's Security tab
- **Pinned CI** — every GitHub Action is pinned to a commit SHA
- **Minimal attack surface** — build-only tools (`curl`, `gnupg`) are purged, and on PostgreSQL 18 so are the JIT/LLVM packages
- **No telemetry** — `timescaledb.telemetry_level = off`
- **No secrets baked in** — credentials are supplied at runtime (prefer `POSTGRES_PASSWORD_FILE`)
- **Non-root runtime** — the official PostgreSQL image drops to the `postgres` user at runtime
- **Built-in healthcheck** — `pg_isready` over TCP, so the container only reports healthy after initialization finished
- **Passwords hashed with SCRAM-SHA-256**

### What you should do

- **Do not publish 5432 on all interfaces.** Use `-p 127.0.0.1:5432:5432` or a private Docker network. Docker-published ports bypass host firewalls.
- **Use secrets**, not literal passwords in `docker run` / Compose files (`POSTGRES_PASSWORD_FILE`).
- **Run applications with a least-privilege role**, not the superuser:

  ```sql
  CREATE ROLE app LOGIN PASSWORD '...';
  GRANT CONNECT ON DATABASE mydb TO app;
  GRANT USAGE ON SCHEMA public TO app;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app;
  -- Apache AGE: let the role use graphs (ag_catalog is on the search_path)
  GRANT USAGE ON SCHEMA ag_catalog TO app;
  ```
- **Enable TLS** if clients connect over a network you do not fully control (below).

### TLS

SSL is off by default because the image ships no certificates. To enable it, mount a certificate and key that the `postgres` user (uid `999`) can read; the key must be mode `0600` (owned by that user) or `0640` owned by root with group `postgres`:

```bash
docker run -d \
  -v "$PWD/certs/server.crt:/etc/ssl/pg/server.crt:ro" \
  -v "$PWD/certs/server.key:/etc/ssl/pg/server.key:ro" \
  pgvector-postgis \
  postgres -c ssl=on -c ssl_cert_file=/etc/ssl/pg/server.crt -c ssl_key_file=/etc/ssl/pg/server.key
```

Then require it from clients (`sslmode=verify-full`). To refuse non-TLS connections server-side, supply a custom `pg_hba.conf` that uses `hostssl` instead of `host`.

### Scanning the image yourself

```bash
trivy image --config trivy.yaml pgvector-postgis
```

`trivy.yaml` skips `usr/local/bin/gosu`: it comes from the upstream `postgres` image, is built with an older Go toolchain and only runs once at startup (root → `postgres`), so its Go standard-library CVEs are not reachable. Debian packages are scanned in full.

## Configuration

### Environment Variables

All standard [PostgreSQL Docker environment variables](https://hub.docker.com/_/postgres) are supported:

| Variable | Default | Description |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Superuser username |
| `POSTGRES_PASSWORD` | *(required)* | Superuser password |
| `POSTGRES_DB` | Same as `POSTGRES_USER` | Default database name |
| `PGDATA` | `/var/lib/postgresql/18/docker` (PG18), `/var/lib/postgresql/data` (PG17) | Data directory path |
| `POSTGRES_PASSWORD_FILE` | *(unset)* | Read the superuser password from this file (preferred over `POSTGRES_PASSWORD`) |
| `TIMESCALEDB_TUNE` | `false` | Set to `true` to run `timescaledb-tune` once on first start |
| `TS_TUNE_MEMORY` | container memory limit, else host memory | Memory to tune for, e.g. `4GB` |
| `TS_TUNE_NUM_CPUS` | container CPU limit, else host CPUs | CPUs to tune for |

### Build arguments

| Argument | Default | Description |
|---|---|---|
| `PG_MAJOR` | `18` | PostgreSQL major version (`17` or `18`) |
| `PGVECTOR_VERSION` | pinned release | pgvector release used for the base image tag |
| `BUILD_DATE` | `unset` | Change it to force `apt-get upgrade` to re-run despite the layer cache (CI sets the ISO year-week) |
| `PRUNE_OLD_TIMESCALEDB` | `false` | `true` deletes all but the newest TimescaleDB library (~370 MB smaller). Only for fresh databases — see below |

## Performance

### Defaults set by this image

| Setting | Value | Why |
|---|---|---|
| `jit` | `off` | PostGIS functions have high cost estimates, so the planner triggers JIT on queries that then run slower. |
| `random_page_cost` | `1.1` | Containers almost always run on SSD/NVMe |
| `wal_compression` | `lz4` | Less WAL for little CPU |
| `timescaledb.telemetry_level` | `off` | No usage data leaves the container |

PostgreSQL's memory settings are otherwise left at upstream defaults (`shared_buffers` 128 MB, `work_mem` 4 MB, `maintenance_work_mem` 64 MB), which are far too small for real workloads. Size them for your container:

### Automatic tuning (opt-in)

```bash
docker run -d --memory=4g --cpus=2 -e TIMESCALEDB_TUNE=true ... pgvector-postgis
```

On first start `timescaledb-tune` writes `shared_buffers`, `effective_cache_size`, `work_mem`, `maintenance_work_mem`, WAL and worker settings to `postgresql.conf`, based on the container's memory/CPU limit (override with `TS_TUNE_MEMORY` / `TS_TUNE_NUM_CPUS`). To change the values later, run `docker exec -u postgres postgres timescaledb-tune --yes --conf-path "$PGDATA/postgresql.conf"` and restart, or mount your own config:

```bash
docker run -d \
  -v ./custom-postgresql.conf:/etc/postgresql/postgresql.conf \
  pgvector-postgis \
  postgres -c config_file=/etc/postgresql/postgresql.conf
```

Keep `shared_preload_libraries = 'timescaledb'` in a custom file.

### Shared memory

Give the container `--shm-size=1g` (Compose: `shm_size: 1g`) or larger. The Docker default of 64 MB makes large parallel queries and parallel index builds fail.

### Many short-lived connections

A new connection costs roughly 8 ms (authentication plus process start). If your application opens many short connections, put PgBouncer in front of the database.

### pgvector index tuning

For large vector datasets, increase `maintenance_work_mem` and parallel workers before building HNSW indexes (needs `--shm-size`, above):

```sql
SET maintenance_work_mem = '2GB';
SET max_parallel_maintenance_workers = 4;
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
```

### Image size and `PRUNE_OLD_TIMESCALEDB`

The TimescaleDB package ships every release's shared library (26 versions, ~370 MB) so existing databases can be upgraded in place. Building with `--build-arg PRUNE_OLD_TIMESCALEDB=true` keeps only the newest. Do **not** use it for an image that will run against an existing data volume: a database still on an older TimescaleDB version cannot start until that version's library exists. If you do use it, update the extension (`ALTER EXTENSION timescaledb UPDATE;`) with a non-pruned image first.

## License

This project is licensed under the [MIT License](LICENSE).

The bundled extensions are subject to their own licenses:

- **pgvector** — [PostgreSQL License](https://github.com/pgvector/pgvector/blob/master/LICENSE)
- **PostGIS** — [GPLv2](https://postgis.net/development/rfcs/rfc-1/)
- **TimescaleDB** — [Timescale License (TSL)](https://github.com/timescale/timescaledb/blob/main/tsl/LICENSE-TIMESCALE)
- **Apache AGE** — [Apache License 2.0](https://github.com/apache/age/blob/master/LICENSE)

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Maintainer

**samaasi** — [dev.bensonsamaasi@gmail.com](mailto:dev.bensonsamaasi@gmail.com)
