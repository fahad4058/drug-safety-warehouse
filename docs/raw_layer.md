# The raw layer

`raw.landing` is an append-only log. Rows are only ever added — nothing is
updated, merged or deduplicated at load time — and current state is derived in
staging rather than stored here.

Current row counts are not in this file; they change with every pull.
`analyses/staging_row_reconciliation.sql` computes landed rows, distinct
natural keys, staged rows, source files and batches per source, straight from
the warehouse.

## How rows land

`scripts/load_<source>.sql`, executed by `scripts/run_sql.py`:

- schema-less `CREATE TABLE IF NOT EXISTS`, letting `COPY INTO` establish the
  schema by inference;
- `COPY INTO … FROM (SELECT *, …)` over a **directory**, not a file, which is
  what makes later loads incremental;
- `FILEFORMAT = JSON` (`PARQUET` for mesh) with a `PATTERN` filter;
- `mergeSchema` in **both** `FORMAT_OPTIONS` (merge across the source files
  being read) and `COPY_OPTIONS` (evolve the target table to accept them).

Three metadata columns are stamped on every row:

| column | expression | answers |
|---|---|---|
| `_loaded_at` | `current_timestamp()` | when this row entered the warehouse |
| `_source_file` | `_metadata.file_path` | which physical file it came from |
| `_batch_id` | `date_format(current_timestamp(), 'yyyyMMddHHmmss')` | which load run produced it |

`_batch_id` uses `date_format` rather than `uuid()` deliberately: `uuid()` is
evaluated **per row** and would give every row its own "batch", while
`current_timestamp()` is constant for the query. The hard-delete snapshot
depends on being able to ask what the newest bulk file contained, which an
append-only log cannot answer without this column.

Beyond those three columns raw stays permissive — strings and structs exactly
as they arrived. Casting is staging's job.

## Volumes

Files land in the UC Volume `raw.landing.landing_files`, one subdirectory per
source, before `COPY INTO` reads them. `data/mesh/desc2026.xml` (313 MB) is a
cached parser input, deliberately **not** uploaded; only the Parquet it
produces is a landing artifact.

## Duplication, and where it is resolved

Raw holds more rows than natural keys on two sources, for two different
reasons, and both are resolved in staging rather than at load time.

**ClinicalTrials.gov** re-lands a study on every pull that touches it. The
loader pulls a change window and consecutive windows overlap by design, so a
study that changed appears in more than one file, distinguished by
`_pulled_at`. `stg_ctgov__studies` keeps the newest.

**FAERS** re-publishes a case in a later quarter when it is revised, at a
higher `safetyreportversion`. `stg_faers__reports` keeps the highest version,
ordered on an integer cast so `'9'` never outranks `'103'`.

Neither is resolved by the loader. Collapsing repeated pulls of one entity back
to a single row is grain *correction* and belongs in staging; the raw log keeps
every version so the collapse can be replayed differently later.

## Dated findings

Records of what happened, stamped. Not descriptions of the current state.

### 2026-08-14/15 — first load, and the double-load idempotency proof

Landed into `raw.landing` on Databricks Free Edition (2X-Small serverless).
Counts as of that load — superseded for FAERS by the entry below, and for
everything by `analyses/staging_row_reconciliation.sql`:

| table | rows | natural keys | source files | batches |
|---|---:|---:|---:|---:|
| `raw.landing.ctgov_studies` | 54,394 | 49,045 | 2 | 1 |
| `raw.landing.drugsfda_applications` | 29,267 | 29,267 | 1 | 1 |
| `raw.landing.faers_event_ingest_v2` | 144,000 | 144,000 | 12 | 1 |
| `raw.landing.mesh_descriptors` | 31,110 | 31,110 | 1 | 1 |

Every source's row count was known **before** it was loaded and matched exactly
on arrival: ClinicalTrials.gov reported `totalCount=49045` for the backfill
window, openFDA's download index declares `records` per part-file, and the MeSH
XML yielded 31,110 descriptors locally. Landing changed none of those numbers.

**The idempotency proof.** `COPY INTO` records every file it ingests in the
target table's Delta log and skips files it has already seen. Each load script
was run a second time, completely unchanged:

| table | first run | second run | rows after both |
|---|---:|---:|---:|
| `mesh_descriptors` | 31,110 inserted | **0 inserted** | 31,110 |
| `ctgov_studies` | 54,394 inserted | **0 inserted** | 54,394 |
| `drugsfda_applications` | 29,267 inserted | **0 inserted** | 29,267 |
| `faers_event_ingest_v2` | 144,000 inserted | **0 inserted** | 144,000 |

`num_skipped_corrupt_files = 0` on every run.

Two supporting signals. `_batch_id` stayed at **one distinct value per table** —
a second batch id appearing would mean rows had been re-ingested even if a row
count happened to look stable. And `mesh_descriptors._loaded_at` remained
byte-identical at `2026-08-14 13:13:36.854093+00:00` across both runs; a
re-ingest would have moved it.

Two identical numbers is the whole proof.

### 2026-08-25 — four complete FAERS quarters, and a sample-era conclusion corrected

`raw.landing.faers_event_ingest_v2` was completed from a three-parts-per-quarter
sample to every part of 2025q3–2026q2: 129 files, 11 GB of gzipped JSON, one
`COPY INTO` in 2m41s on the 2X-Small. Upload was the bottleneck, not ingest.

The completion overturned a conclusion drawn from the sample. The sampled load
showed FAERS rows exactly equal to distinct `safetyreportid`, and the
explanation recorded here was that openFDA's quarterly extracts hold one row per
case because a revised case *moves* to a later partition rather than appearing
in both. **That was wrong.** At full scale a case first received in one quarter
and revised in another appears in both files at different versions, and the
version dedup in `stg_faers__reports` — a measured no-op on the sample — removes
a real share of rows.

The sample could not contain that evidence, because the parts are not a random
sample of the corpus. Every part file holds exactly 12,000 records, but sizes
range from 5 MB to 223 MB and the small ones sit at the same positions in every
quarter: openFDA orders parts by something that correlates with report content.
Three of thirty parts is a biased slice, not merely a small one.

The lesson is the record here, not the number: a conclusion about *mechanism*
drawn from a partial load needs the same scepticism as a statistic drawn from
it.
