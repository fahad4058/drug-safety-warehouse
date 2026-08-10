# Verification ledger — Free Edition capability probes

Every assumption this project makes about Databricks Free Edition, tested before
being relied on. Failed probes are logged with their consequence, not silently
dropped. Probe SQL lives in `scripts/probes/`, executed via `scripts/run_sql.py`.

Workspace: `dbc-8f5f7a25-af7b.cloud.databricks.com` (AWS) · Warehouse: 2X-Small serverless `feaa277d26baa9cc`

## Toolchain pins (recorded 2026-08-09)

- dbt-core **1.11.8** · dbt-databricks **1.11.8** (dbt-spark 1.10.3 transitive) · Python 3.12.13
- Databricks CLI v1.11.0 · Astro CLI 1.44.0 · Docker 29.6.2
- sqlfluff 4.3.0 + sqlfluff-templater-dbt · pre-commit 4.6.1

## Probe results

| # | Probe | Result | Consequence |
|---|-------|--------|-------------|
| 1 | PAT auth: Databricks CLI (`current-user me`) | PASS 2026-08-09 | CLI/ingestion path confirmed |
| 2 | PAT auth: `dbt debug` × dev/prod/ci | PASS 2026-08-09 | all three targets connect; env-var-based profile works |
| 3 | Recursive CTE on serverless warehouse | PASS 2026-08-09 | Step 6 hierarchy shootout safe (returned rows 1–5) |
| 4 | CREATE MATERIALIZED VIEW + query + drop | PASS 2026-08-09 | Step 8 MV model proceeds; MV occupies the single pipeline slot |
| 5 | GRANT SELECT to `account users` + SHOW GRANTS | PASS 2026-08-09 | built-in group is grantable; Step 8 grants exercise as planned |
| 6 | Volume upload via CLI + COPY INTO (double-run) | PASS 2026-08-10 | ingestion path confirmed; 2nd run loaded 0 rows — idempotency proven |
| 7 | dbt Python model on serverless job compute | PASS 2026-08-10 | job submitted + table created in 56s (`submission_method: serverless_cluster`); Step 8 Python model proceeds |
| 8 | insert_overwrite on serverless SQL warehouse | PASS 2026-08-10 | works, DBR 17.1+ gated; partition-scoped replacement verified by marker-row test; Step 5 benchmark variant proceeds |
| 9 | liquid_clustered_by + OPTIMIZE + exclusivity errors | PASS 2026-08-10 | CLUSTER BY + OPTIMIZE work; layouts confirmed mutually exclusive |

## Findings

- **Catalog DDL is SQL-only on Free Edition.** `databricks catalogs create` fails with
  "Metastore storage root URL does not exist" — FE accounts have no customer bucket and
  use Default Storage, which the bare REST endpoint doesn't apply. `CREATE CATALOG`
  executed on the SQL warehouse succeeds (DBSQL fills in Default Storage). Workspace
  bootstrap therefore lives in `scripts/bootstrap_workspace.sql`.
- **`COPY INTO` file tracking lives on the target table.** Second run of the same
  `COPY INTO` reported `num_affected_rows=0` — but dropping the table erases that
  ingestion memory, so a re-created table happily reloads everything. Raw tables are
  precious for their *state*, not just their rows.
- **MV creation is pipeline-backed.** `CREATE MATERIALIZED VIEW` returned "operation
  successfully executed" and provisioned a background pipeline; the first `SELECT`
  waits on the initial refresh. This spends the one-active-pipeline-per-type budget.
- **Layout exclusivity, observed verbatim.**
  `ALTER TABLE ... CLUSTER BY` on a partitioned table →
  `DELTA_ALTER_TABLE_CLUSTER_BY_ON_PARTITIONED_TABLE_NOT_ALLOWED`;
  `OPTIMIZE ... ZORDER BY` on a liquid-clustered table →
  `DELTA_CLUSTERING_WITH_ZORDER_BY`.
- **`OPTIMIZE` on a clustered table runs two passes** — a clustering pass, then a
  `post-optimize-compaction` pass — and returns one metrics row per pass. At probe
  scale (1 file, 1.4 KB) all counters are zero; real measurements belong to Step 5.
- **`DESCRIBE DETAIL` is the layout receipt**: `partitionColumns` vs
  `clusteringColumns`, plus `tableFeatures` (`clustering`, `deletionVectors`,
  `rowTracking` all on by default here; parquet compression is zstd).
- **`dbt show` cannot preview Python models.** Its preview wraps the *compiled
  artifact* in `select * from (...) limit 5`; for a Python model that artifact is
  Python source (model fn + dbt's ref/source notebook shims), which the SQL
  warehouse rejects with `PARSE_SYNTAX_ERROR` at `def`. Sibling fact to "Python
  models are not unit-testable" — SQL-assuming dbt tooling doesn't extend to them.
- **`insert_overwrite` compiles to `REPLACE ON` here — always.** On adapter
  1.11.8 + SQL warehouse, the executed DML (read from `target/run/`) is
  `INSERT INTO ... AS t REPLACE ON (t.part <=> s.part) ... AS s`, with or without
  the legacy `use_replace_on_for_insert_overwrite` key (now flagged as a
  deprecated custom config key — the opt-in became the default). `<=>` is
  null-safe equality, so NULL partition values still match. The adapter logs that
  on DBR < 17.1 this strategy silently degrades to full-table replacement — the
  exact blast-radius trap Step 5 rebuilds deliberately at scale.
