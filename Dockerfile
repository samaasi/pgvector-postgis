# Use the official pgvector image for PostgreSQL 17
FROM pgvector/pgvector:pg17

# Metadata labels
LABEL maintainer="Maintainer"
LABEL description="PostgreSQL 17 image with pgvector and PostGIS (including Raster, Topology, and SFCGAL)"

# Set environment variables to optimize build
ENV DEBIAN_FRONTEND=noninteractive

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

# Add initialization script
# Note: Using .sql instead of .sh for faster, standard initialization
COPY init.sql /docker-entrypoint-initdb.d/

# Add a healthcheck to ensure the database is ready
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
    CMD pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres}