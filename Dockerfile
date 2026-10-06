# PostgreSQL major version and pinned pgvector release (override with --build-arg)
ARG PG_MAJOR=18
ARG PGVECTOR_VERSION=0.8.2

# Use the official pgvector image as the base
FROM pgvector/pgvector:${PGVECTOR_VERSION}-pg${PG_MAJOR}-trixie

# Install PostGIS and Apache AGE from the PGDG repo configured in the base image
# (PG_MAJOR is set as an env var by the base image)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      postgresql-${PG_MAJOR}-postgis-3 \
      postgresql-${PG_MAJOR}-postgis-3-scripts \
      postgresql-${PG_MAJOR}-age \
    && rm -rf /var/lib/apt/lists/*

# Add initialization script
COPY --chmod=755 init.sh /docker-entrypoint-initdb.d/
