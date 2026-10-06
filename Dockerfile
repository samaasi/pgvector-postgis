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

# Install TimescaleDB from the official repository using explicit GPG verification
# (avoids piping curl to bash which is a security risk)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      lsb-release \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey \
       | gpg --dearmor -o /etc/apt/keyrings/timescale.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/timescale.gpg] https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/timescaledb.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      timescaledb-2-postgresql-17 \
    && apt-get purge -y curl gnupg lsb-release \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure TimescaleDB to be preloaded at server start
RUN echo "shared_preload_libraries = 'timescaledb'" >> /usr/share/postgresql/postgresql.conf.sample

# Add initialization script
COPY --chmod=755 init.sh /docker-entrypoint-initdb.d/
