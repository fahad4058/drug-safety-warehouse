# Raw layer — counts and idempotency proof

Landed 2026-08-14 → 08-15 into `raw.landing` on Databricks Free Edition
(2X-Small serverless). All four sources are **append-only**: each load stamps
`_loaded_at`, `_source_file` and a per-run `_batch_id`, and nothing is updated,
merged or deduplicated at load time.

## Row counts

| table | rows | natural keys | source files | batches |
|---|---:|---:|---:|---:|
| `raw.landing.ctgov_studies` | 54,394 | 49,045 | 2 | 1 |
| `raw.landing.drugsfda_applications` | 29,267 | 29,267 | 1 | 1 |
| `raw.landing.faers_event_ingest_v2` | 144,000 | 144,000 | 12 | 1 |
| `raw.landing.mesh_descriptors` | 31,110 | 31,110 | 1 | 1 |
| **total** | **258,771** | | **16** | |

Natural keys are `protocolSection.identificationModule.nctId`,
`application_number`, `safetyreportid` and `descriptor_ui` respectively.
Reproduce with `make raw-counts` (`scripts/raw_counts.sql`).

Every source's row count was known **before** it was loaded and matched exactly
on arrival: ClinicalTrials reported `totalCount=49045` for the backfill window,
openFDA's download index declares `records` per part-file, and the MeSH XML
yielded 31,110 descriptors locally. Landing changed none of those numbers.

### The one intentional duplication

`ctgov_studies` is the only table where rows exceed natural keys, and the gap is
by design: **54,394 − 49,045 = 5,349** studies appear twice, once from the
initial 90-day pull and once from the full backfill, distinguished by
`_pulled_at`. Resolving that to one row per study belongs to
`stg_ctgov__studies`, not to the loader.

`faers_reports` shows 144,000 rows against 144,000 distinct `safetyreportid`
because openFDA's quarterly extracts hold exactly one row per case, partitioned
by `receiptdate` — a revised case *moves* to a later partition rather than
appearing in both. Verified: every record's `receiptdate` falls inside its own
file's quarter, across all twelve files. Duplicate cases can therefore only
arrive through repeated pulls over time, never within a single pull.

## Double-load idempotency proof

`COPY INTO` records every file it ingests in the target table's Delta log and
skips files it has already seen. Each load script was run a second time,
completely unchanged:

| table | first run | second run | rows after both |
|---|---:|---:|---:|
| `mesh_descriptors` | 31,110 inserted | **0 inserted** | 31,110 |
| `ctgov_studies` | 54,394 inserted | **0 inserted** | 54,394 |
| `drugsfda_applications` | 29,267 inserted | **0 inserted** | 29,267 |
| `faers_reports` | 144,000 inserted | **0 inserted** | 144,000 |

`num_skipped_corrupt_files = 0` on every run.

Two supporting signals. `_batch_id` stayed at **one distinct value per table** —
a second batch id appearing would mean rows had been re-ingested even if a row
count happened to look stable. And `mesh_descriptors._loaded_at` remained
byte-identical at `2026-08-14 13:13:36.854093+00:00` across both runs; a
re-ingest would have moved it.

Two identical numbers is the whole proof.

## How rows land

`scripts/load_<source>.sql`, executed by `scripts/run_sql.py`:

- schema-less `CREATE TABLE IF NOT EXISTS`, letting `COPY INTO` establish the
  schema by inference;
- `COPY INTO … FROM (SELECT *, …)` over a **directory**, not a file, which is
  what makes later loads incremental;
- `FILEFORMAT = JSON` (`PARQUET` for mesh) with a `PATTERN` filter;
- `mergeSchema` in **both** `FORMAT_OPTIONS` (merge across the source files being
  read) and `COPY_OPTIONS` (evolve the target table to accept them).

Three metadata columns are stamped on every row:

| column | expression | answers |
|---|---|---|
| `_loaded_at` | `current_timestamp()` | when this row entered the warehouse |
| `_source_file` | `_metadata.file_path` | which physical file it came from |
| `_batch_id` | `date_format(current_timestamp(), 'yyyyMMddHHmmss')` | which load run produced it |

`_batch_id` uses `date_format` rather than `uuid()` deliberately: `uuid()` is
evaluated **per row** and would give every row its own "batch", while
`current_timestamp()` is constant for the query. Hard-delete snapshot
depends on being able to ask what the newest bulk file contained, which an
append-only log cannot answer without this column.

Beyond those three columns raw stays permissive — strings and structs exactly as
they arrived. Casting is staging's job.

## Volumes

Files land in the UC Volume `raw.landing.landing_files`, one subdirectory per
source, before `COPY INTO` reads them. `data/mesh/desc2026.xml` (313 MB) is a
cached parser input, deliberately **not** uploaded; only the 1.4 MB Parquet it
produces is a landing artifact.
