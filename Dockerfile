# Use the official pgvector image for PostgreSQL 17
FROM pgvector/pgvector:pg17

# Metadata labels
LABEL maintainer="samaasi <dev.bensonsamaasi@gmail.com>"
LABEL description="PostgreSQL 17 image with pgvector, PostGIS (Raster, Topology, SFCGAL), and TimescaleDB"

# Set environment variables to optimize build
ENV DEBIAN_FRONTEND=noninteractive

# Apply security patches from the base image
RUN apt-get update && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

# Install PostGIS with all requested features
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      postgresql-17-postgis-3 \
      postgresql-17-postgis-3-scripts \
      postgresql-17-postgis-3-raster \
      postgresql-17-postgis-3-topology \
      postgresql-17-postgis-3-sfcgal \
    && apt-get clean \
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
# Note: Using .sql instead of .sh for faster, standard initialization
COPY init.sql /docker-entrypoint-initdb.d/

# Add a healthcheck to ensure the database is ready
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
    CMD pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres}