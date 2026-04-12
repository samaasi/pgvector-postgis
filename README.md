# pgvector-postgis

A production-ready PostgreSQL 17 Docker image combining **pgvector**, **PostGIS**, and **TimescaleDB** — providing vector search, geospatial analysis, and time-series capabilities in a single, hardened container.

## Extensions

| Extension | Version Source | Purpose |
|---|---|---|
| **pgvector** (`vector`) | Base image | Vector similarity search (cosine, L2, inner product) for AI/ML embeddings |
| **PostGIS** (`postgis`) | Debian packages | Core geospatial data types and spatial functions |
| **PostGIS Raster** (`postgis_raster`) | Debian packages | Raster data types and analysis functions |
| **PostGIS Topology** (`postgis_topology`) | Debian packages | Topology types for network and boundary modelling |
| **PostGIS SFCGAL** (`postgis_sfcgal`) | Debian packages | Advanced 2D/3D spatial operations |
| **TimescaleDB** (`timescaledb`) | Official TimescaleDB repo | Time-series hypertables, continuous aggregates, compression |

## Quick Start

### Build the image

```bash
docker build -t pgvector-postgis .
```

### Run the container

```bash
docker run -d \
  --name postgres \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypassword \
  -e POSTGRES_DB=mydb \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  pgvector-postgis
```

All extensions are automatically enabled on the first start via `init.sql`.

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
      - pgdata:/var/lib/postgresql/data
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

## Project Structure

```
├── Dockerfile          # Multi-extension PostgreSQL 17 image
├── init.sql            # Extension initialization (runs on first start)
├── .dockerignore       # Excludes non-essential files from build context
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
| `PGDATA` | `/var/lib/postgresql/data` | Data directory path |

### TimescaleDB Tuning

For production workloads, mount a custom configuration file:

```bash
docker run -d \
  -v ./custom-postgresql.conf:/etc/postgresql/postgresql.conf \
  -e POSTGRES_ARGS="-c config_file=/etc/postgresql/postgresql.conf" \
  pgvector-postgis
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

This Dockerfile is provided as-is. The bundled extensions are subject to their own licenses:

- **pgvector** — [PostgreSQL License](https://github.com/pgvector/pgvector/blob/master/LICENSE)
- **PostGIS** — [GPLv2](https://postgis.net/development/rfcs/rfc-1/)
- **TimescaleDB** — [Timescale License (TSL)](https://github.com/timescale/timescaledb/blob/main/tsl/LICENSE-TIMESCALE)

## Maintainer

**samaasi** — [dev.bensonsamaasi@gmail.com](mailto:dev.bensonsamaasi@gmail.com)
