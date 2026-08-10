--one-time idempotent databricks workspace boostrap script
CREATE CATALOG IF NOT EXISTS raw;
CREATE CATALOG IF NOT EXISTS dev;
CREATE CATALOG IF NOT EXISTS prod;
CREATE CATALOG IF NOT EXISTS ci;

CREATE SCHEMA IF NOT EXISTS raw.landing;
CREATE VOLUME IF NOT EXISTS raw.landing.landing_files;
