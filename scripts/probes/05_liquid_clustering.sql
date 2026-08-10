-- Probe 9a: liquid clustering + OPTIMIZE.
CREATE OR REPLACE TABLE dev.probes.lc_toy (id BIGINT, event_date DATE, drug STRING)
CLUSTER BY (drug, event_date);
INSERT INTO dev.probes.lc_toy VALUES
  (1, DATE'2026-01-01', 'asprin'),
  (2, DATE'2026-01-02', 'ibuprufen'),
  (3, DATE'2026-02-01', 'paracetamol');
OPTIMIZE dev.probes.lc_toy;
DESCRIBE DETAIL dev.probes.lc_toy;
