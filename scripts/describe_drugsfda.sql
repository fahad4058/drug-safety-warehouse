SELECT column_name, full_data_type
FROM raw.information_schema.columns
WHERE table_schema = 'landing' AND table_name = 'drugsfda_applications'
ORDER BY ordinal_position;

SELECT
  count(*)                              AS rows_total,
  count(DISTINCT application_number)    AS distinct_applications,
  count(DISTINCT _batch_id)             AS batches,
  count(DISTINCT _pulled_at)            AS pulls,
  count_if(products IS NULL OR size(products) = 0) AS no_products,
  sum(size(products))                   AS products_total,
  count_if(openfda IS NULL)             AS null_openfda
FROM raw.landing.drugsfda_applications;

SELECT regexp_extract(application_number, '^([A-Z]+)', 1) AS application_type, count(*) AS n
FROM raw.landing.drugsfda_applications
GROUP BY 1
ORDER BY 2 DESC;
