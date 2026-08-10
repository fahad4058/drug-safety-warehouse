-- Probe 4: MV creation tests the one-active-pipeline-per-type budget.
CREATE SCHEMA IF NOT EXISTS dev.probes;
CREATE TABLE IF NOT EXISTS dev.probes.toy AS SELECT 1 AS id, 'a' AS val;
CREATE MATERIALIZED VIEW dev.probes.toy_mv AS SELECT count(*) AS c FROM dev.probes.toy;
SELECT * FROM dev.probes.toy_mv;
DROP MATERIALIZED VIEW dev.probes.toy_mv;
