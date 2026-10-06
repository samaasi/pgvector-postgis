# PostgreSQL major version and pinned pgvector release (override with --build-arg)
# Renovate keeps PGVECTOR_VERSION up to date (see renovate.json).
ARG PG_MAJOR=18
ARG PGVECTOR_VERSION=0.8.2

# Use the official pgvector image as the base
FROM pgvector/pgvector:${PGVECTOR_VERSION}-pg${PG_MAJOR}-trixie

# Metadata labels
LABEL maintainer="samaasi <dev.bensonsamaasi@gmail.com>"
LABEL description="PostgreSQL image with pgvector, PostGIS (Raster, Topology, SFCGAL), TimescaleDB and Apache AGE"

# Build-time only: avoid interactive apt prompts without persisting into the image
ARG DEBIAN_FRONTEND=noninteractive

# Changing this value (CI passes the ISO year-week) invalidates the layer cache so the
# weekly rebuild really re-runs `apt-get upgrade` and picks up OS security patches.
ARG BUILD_DATE=unset

# Expected fingerprint of the TimescaleDB package signing key. The build fails if the
# key downloaded from packagecloud does not match.
ARG TIMESCALE_SIGNING_FPR=1005FB68604CE9B8F6879CF759F18EDF47F24417

# Set to "true" to delete every TimescaleDB library except the newest one (~370 MB
# smaller). Only safe for fresh databases: a data volume that still has an older
# TimescaleDB version installed cannot start until that version's library exists.
ARG PRUNE_OLD_TIMESCALEDB=false

# PG_MAJOR is also set as an env var by the base image, so it is available here.
# One layer: patch the OS, add PostGIS + Apache AGE (PGDG repo, already configured in the
# base image) and TimescaleDB (its own signed repo), then remove build-only tooling.
RUN set -eux; \
    echo "Build week: ${BUILD_DATE}"; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
      postgresql-${PG_MAJOR}-postgis-3 \
      postgresql-${PG_MAJOR}-postgis-3-scripts \
      postgresql-${PG_MAJOR}-age \
      ca-certificates \
      curl \
      gnupg; \
    \
    # Verify the TimescaleDB signing key fingerprint before trusting the repository
    # (avoids piping curl to bash, and avoids trusting whatever key is served).
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey -o /tmp/timescale.asc; \
    gpg --show-keys --with-colons /tmp/timescale.asc \
      | awk -F: '$1 == "fpr" { print $10; exit }' \
      | grep -qx "${TIMESCALE_SIGNING_FPR}"; \
    gpg --dearmor -o /etc/apt/keyrings/timescale.gpg /tmp/timescale.asc; \
    . /etc/os-release; \
    echo "deb [signed-by=/etc/apt/keyrings/timescale.gpg] https://packagecloud.io/timescale/timescaledb/debian/ ${VERSION_CODENAME} main" \
      > /etc/apt/sources.list.d/timescaledb.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      timescaledb-2-postgresql-${PG_MAJOR} \
      timescaledb-tools; \
    \
    # JIT is disabled by default below. From PostgreSQL 18 it is a separate package, and
    # dropping it also drops LLVM (~40 MB). On PG17 it is part of the main package.
    if dpkg -s "postgresql-${PG_MAJOR}-jit" >/dev/null 2>&1; then \
      apt-get purge -y --auto-remove "postgresql-${PG_MAJOR}-jit"; \
    fi; \
    \
    if [ "${PRUNE_OLD_TIMESCALEDB}" = "true" ]; then \
      libdir="$(pg_config --pkglibdir)"; \
      for prefix in timescaledb timescaledb-tsl; do \
        newest="$(ls "${libdir}" | grep -E "^${prefix}-[0-9]+\.[0-9]+\.[0-9]+\.so$" | sort -V | tail -n 1)"; \
        ls "${libdir}" | grep -E "^${prefix}-[0-9]+\.[0-9]+\.[0-9]+\.so$" | grep -vx "${newest}" \
          | while read -r old; do rm -f "${libdir}/${old}"; done; \
      done; \
    fi; \
    \
    apt-get purge -y --auto-remove curl gnupg; \
    rm -rf /var/lib/apt/lists/* /tmp/timescale.asc

# Server defaults (applied to every new cluster via the sample config):
#  - timescaledb must be preloaded at server start
#  - telemetry off: no usage data leaves the container
#  - jit off: PostGIS cost estimates trigger JIT on queries that then run slower
#  - random_page_cost 1.1: containers almost always sit on SSD/NVMe
#  - wal_compression lz4: less WAL volume for little CPU
RUN set -eux; \
    { \
      echo "shared_preload_libraries = 'timescaledb'"; \
      echo "timescaledb.telemetry_level = off"; \
      echo "jit = off"; \
      echo "random_page_cost = 1.1"; \
      echo "wal_compression = lz4"; \
    } >> /usr/share/postgresql/postgresql.conf.sample

# Add initialization script
COPY --chmod=755 init.sh /docker-entrypoint-initdb.d/

# Report healthy only once the database accepts connections. Check over TCP:
# the temporary server used while init scripts run listens on the Unix socket only,
# so this stays unhealthy until initialization has fully finished.
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
    CMD pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}"
