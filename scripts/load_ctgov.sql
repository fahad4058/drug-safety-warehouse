CREATE TABLE IF NOT EXISTS raw.landing.ctgov_studies;

COPY INTO raw.landing.ctgov_studies  FROM (
    SELECT
        *,
        current_timestamp() as _loaded_at,
        _metadata.file_path as _source_file,
        date_format(current_timestamp(), 'yyyyMMddHHmmss') as _batch_id
    FROM
        '/Volumes/raw/landing/landing_files/ctgov/'
)
FILEFORMAT = JSON
PATTERN = '*.ndjson.gz'
FORMAT_OPTIONS ('mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');
