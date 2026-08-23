SELECT 'ctgov_studies' AS table_name,
       count(*) AS rows,
       count(DISTINCT protocolSection.identificationModule.nctId) AS natural_keys,
       count(DISTINCT _source_file) AS files,
       count(DISTINCT _batch_id) AS batches
FROM raw.landing.ctgov_studies
UNION ALL
SELECT 'faers_event_ingest_v2', count(*), count(DISTINCT safetyreportid),
       count(DISTINCT _source_file), count(DISTINCT _batch_id)
FROM raw.landing.faers_event_ingest_v2
UNION ALL
SELECT 'drugsfda_applications', count(*), count(DISTINCT application_number),
       count(DISTINCT _source_file), count(DISTINCT _batch_id)
FROM raw.landing.drugsfda_applications
UNION ALL
SELECT 'mesh_descriptors', count(*), count(DISTINCT descriptor_ui),
       count(DISTINCT _source_file), count(DISTINCT _batch_id)
FROM raw.landing.mesh_descriptors
ORDER BY 1;
