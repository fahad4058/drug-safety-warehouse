CREATE TABLE IF NOT EXISTS raw.landing.faers_reports;

COPY INTO raw.landing.faers_reports
FROM (
  SELECT
    *,
    current_timestamp()                                AS _loaded_at,
    _metadata.file_path                                AS _source_file,
    date_format(current_timestamp(), 'yyyyMMddHHmmss') AS _batch_id
  FROM '/Volumes/raw/landing/landing_files/faers/'
)
FILEFORMAT = JSON
PATTERN = '*.ndjson.gz'
FORMAT_OPTIONS ('mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');
