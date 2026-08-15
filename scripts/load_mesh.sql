CREATE TABLE IF NOT EXISTS raw.landing.mesh_descriptors (
  descriptor_ui   STRING,
  descriptor_name STRING,
  tree_numbers    ARRAY<STRING>,
  _pulled_at      STRING,
  _loaded_at      TIMESTAMP,
  _source_file    STRING,
  _batch_id       STRING
);

COPY INTO raw.landing.mesh_descriptors
FROM (
  SELECT
    descriptor_ui,
    descriptor_name,
    tree_numbers,
    _pulled_at,
    current_timestamp()                                       AS _loaded_at,
    _metadata.file_path                                       AS _source_file,
    date_format(current_timestamp(), 'yyyyMMddHHmmss')        AS _batch_id
  FROM '/Volumes/raw/landing/landing_files/mesh/'
)
FILEFORMAT = PARQUET
PATTERN = '*.parquet';
