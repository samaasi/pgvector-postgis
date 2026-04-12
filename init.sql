-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Enable PostGIS core extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- Enable PostGIS Raster support
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- Enable PostGIS Topology support
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Enable PostGIS SFCGAL support
CREATE EXTENSION IF NOT EXISTS postgis_sfcgal;

-- Enable TimescaleDB for time-series data
CREATE EXTENSION IF NOT EXISTS timescaledb;
