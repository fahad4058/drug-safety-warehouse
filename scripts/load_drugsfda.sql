CREATE TABLE IF NOT EXISTS raw.landing.drugsfda_applications;

COPY INTO raw.landing.drugsfda_applications
FROM (
  SELECT
    *,
    current_timestamp()                                AS _loaded_at,
    _metadata.file_path                                AS _source_file,
    date_format(current_timestamp(), 'yyyyMMddHHmmss') AS _batch_id
  FROM '/Volumes/raw/landing/landing_files/drugsfda/'
)
FILEFORMAT = JSON
PATTERN = '*.ndjson.gz'
FORMAT_OPTIONS ('mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');
