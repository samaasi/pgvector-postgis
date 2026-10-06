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
docker run -d \
  --name postgres \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypassword \
  -e POSTGRES_DB=mydb \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql \
  pgvector-postgis
```

All extensions are automatically enabled on the first start via `init.sh`.

> **Volume path:** from PostgreSQL 18 the volume is mounted at `/var/lib/postgresql` (data lives in `/var/lib/postgresql/18/docker`). For the `pg17` image, mount `/var/lib/postgresql/data` instead.

### Docker Compose

```yaml
services:
  postgres:
    build: .
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: mydb
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myuser -d mydb"]
      interval: 10s
      timeout: 5s
      retries: 5

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
├── init.sh             # Extension initialization (runs on first start)
├── .dockerignore       # Excludes non-essential files from build context
├── .gitignore          # Git ignore rules
├── CONTRIBUTING.md     # Contribution guidelines
├── LICENSE             # MIT License
└── README.md           # This file
```

## Security

This image follows Docker security best practices:

- **GPG-verified packages** — TimescaleDB is installed via explicit GPG key verification (no `curl | bash`)
- **Base image patching** — `apt-get upgrade` is run during build to apply CVE patches
- **Minimal attack surface** — Build-only dependencies (`curl`, `gnupg`, `lsb-release`) are purged after use
- **No secrets baked in** — Credentials are passed via environment variables at runtime
- **Non-root runtime** — The official PostgreSQL image drops to the `postgres` user at runtime
- **Built-in healthcheck** — `pg_isready` ensures the container reports healthy only when accepting connections

## Configuration

### Environment Variables

All standard [PostgreSQL Docker environment variables](https://hub.docker.com/_/postgres) are supported:

| Variable | Default | Description |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Superuser username |
| `POSTGRES_PASSWORD` | *(required)* | Superuser password |
| `POSTGRES_DB` | Same as `POSTGRES_USER` | Default database name |
| `PGDATA` | `/var/lib/postgresql/18/docker` (PG18), `/var/lib/postgresql/data` (PG17) | Data directory path |

### TimescaleDB Tuning

For production workloads, mount a custom configuration file (keep `shared_preload_libraries = 'timescaledb'` in it):

```bash
docker run -d \
  -v ./custom-postgresql.conf:/etc/postgresql/postgresql.conf \
  pgvector-postgis \
  postgres -c config_file=/etc/postgresql/postgresql.conf
```

Or use `timescaledb-tune` inside the container:

```bash
docker exec -it postgres timescaledb-tune --yes
```

### pgvector Index Tuning

For large vector datasets, increase `maintenance_work_mem` before building HNSW indexes:

```sql
SET maintenance_work_mem = '2GB';
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
```

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
