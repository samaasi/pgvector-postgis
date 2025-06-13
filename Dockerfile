# Use the official pgvector image for PostgreSQL 17
FROM pgvector/pgvector:pg17

# Install PostGIS with minimal dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      postgresql-17-postgis-3 \
      postgresql-17-postgis-3-scripts \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure PostgreSQL
RUN echo "shared_preload_libraries = 'pgvector'" >> /usr/share/postgresql/postgresql.conf.sample