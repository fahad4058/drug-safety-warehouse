-- Probe 9b — EXPECTED TO FAIL: CLUSTER BY on an already-partitioned table.
CREATE OR REPLACE TABLE dev.probes.part_toy (id BIGINT, part STRING) PARTITIONED BY (part);
ALTER TABLE dev.probes.part_toy CLUSTER BY (id);
