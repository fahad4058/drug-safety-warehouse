-- copy the data from the uc volume into dev schema copy_probe
-- idempotency check: run it twice, the second time should be a no-op
CREATE TABLE IF NOT EXISTS dev.probes.copy_probe;
COPY INTO dev.probes.copy_probe
FROM '/Volumes/raw/landing/landing_files/probes/'
FILEFORMAT = JSON
FORMAT_OPTIONS (
    'infer_schema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');
SELECT * FROM dev.probes.copy_probe;

