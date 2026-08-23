SELECT
  count(*)                                                    AS rows_total,
  count(DISTINCT safetyreportid)                              AS distinct_report_ids,
  count(DISTINCT _pulled_at)                                  AS distinct_pulls,
  count(DISTINCT _source_file)                                AS source_files,
  count_if(try_cast(safetyreportversion AS int) IS NULL)      AS version_uncastable,
  max(try_cast(safetyreportversion AS int))                   AS max_version,
  count(DISTINCT receiptdateformat)                           AS receiptdate_format_variants,
  max(receiptdateformat)                                      AS receiptdate_format_code,
  count_if(try_to_date(receiptdate, 'yyyyMMdd') IS NULL)      AS receiptdate_unparseable,
  count_if(try_to_date(receivedate, 'yyyyMMdd') IS NULL)      AS receivedate_unparseable,
  count_if(try_to_date(transmissiondate, 'yyyyMMdd') IS NULL) AS transmissiondate_unparseable,
  count_if(duplicate IS NOT NULL)                             AS duplicate_flagged
FROM raw.landing.faers_event_ingest_v2;
