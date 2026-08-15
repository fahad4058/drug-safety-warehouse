# Landing pipeline. Each load-* target runs the same three-step cycle for one
# source: pull to data/, upload to the UC Volume, COPY INTO raw.landing.
#
# Every step is idempotent, so a target is safe to re-run: the loaders skip
# output files that already exist, and COPY INTO skips files it has already
# ingested (tracked in the target table's Delta log).
#
# Loader flags go through ARGS, e.g.
#   make load-ctgov ARGS="--since 2026-01-01"
#   make load-faers ARGS="--dry-run"

VOLUME := dbfs:/Volumes/raw/landing/landing_files
PY     := uv run python

.PHONY: load-all load-ctgov load-faers load-drugsfda load-mesh raw-counts

load-all: load-ctgov load-faers load-drugsfda load-mesh

load-ctgov:
	$(PY) src/loaders/ctgov.py $(ARGS)
	databricks fs cp -r --overwrite data/ctgov $(VOLUME)/ctgov
	$(PY) scripts/run_sql.py scripts/load_ctgov.sql

load-faers:
	$(PY) src/loaders/faers.py $(ARGS)
	databricks fs cp -r --overwrite data/faers $(VOLUME)/faers
	$(PY) scripts/run_sql.py scripts/load_faers.sql

load-drugsfda:
	$(PY) src/loaders/drugsfda.py $(ARGS)
	databricks fs cp -r --overwrite data/drugsfda $(VOLUME)/drugsfda
	$(PY) scripts/run_sql.py scripts/load_drugsfda.sql

# Copies the single Parquet, not the directory: data/mesh also holds the
# 313 MB desc2026.xml parser input, which is not a landing artifact.
load-mesh:
	$(PY) src/loaders/mesh.py $(ARGS)
	databricks fs cp --overwrite data/mesh/mesh_descriptors.parquet $(VOLUME)/mesh/mesh_descriptors.parquet
	$(PY) scripts/run_sql.py scripts/load_mesh.sql

raw-counts:
	$(PY) scripts/run_sql.py scripts/raw_counts.sql
