# drug-safety-warehouse

Tested dbt warehouse on Databricks over FDA adverse-event, trial and approval data, with CI/CD and a live dashboard

[![pr](https://github.com/fahad4058/drug-safety-warehouse/actions/workflows/pr.yml/badge.svg)](https://github.com/fahad4058/drug-safety-warehouse/actions/workflows/pr.yml)
[![deploy](https://github.com/fahad4058/drug-safety-warehouse/actions/workflows/deploy.yml/badge.svg)](https://github.com/fahad4058/drug-safety-warehouse/actions/workflows/deploy.yml)
[![nightly](https://github.com/fahad4058/drug-safety-warehouse/actions/workflows/nightly.yml/badge.svg)](https://github.com/fahad4058/drug-safety-warehouse/actions/workflows/nightly.yml)

Four public sources — ClinicalTrials.gov, openFDA FAERS, Drugs@FDA and the NLM
MeSH vocabulary — landed append-only into Unity Catalog, modelled in dbt as
staging → intermediate → a Kimball star, tested at every layer, built into
`dev`, `ci` and `prod` catalogs by GitHub Actions, and served as a native
Databricks dashboard over one complete year of FDA adverse-event case reports.
Every design decision is written up with the number that justified it.

## Table of Contents

- [Background](#background)
- [The product](#the-product)
- [Architecture](#architecture)
- [Stack](#stack)
- [Install](#install)
- [Usage](#usage)
- [Data model](#data-model)
- [Design decisions](#design-decisions)
- [Development and CI/CD](#development-and-cicd)
- [Roadmap](#roadmap)
- [Maintainer](#maintainer)
- [Contributing](#contributing)
- [Data and disclaimer](#data-and-disclaimer)
- [License](#license)

## Background

### Problem statement

Public drug-safety data is analytically hostile in exactly the ways that make
it a good analytics-engineering problem. The question the warehouse exists to
answer — *which drugs are accumulating adverse-event reports, and what does the
trial and approval pipeline around them look like?* — cannot be answered by
counting rows. Each source breaks a naive count in its own way:

| problem in the data | how this repo handles it | status |
|---|---|---|
| **FAERS case versioning inflates counts.** One case produces several report versions; count them all and every number is wrong by the amendment rate. | Staging keeps the newest version per `safetyreportid`, ordered by an integer-cast version so `'9'` never beats `'103'`. Across four quarters that collapses 97,262 rows (6.3%). | done |
| **The grain explodes on contact.** Every report carries arrays of drugs and arrays of reactions. "Events per drug" is meaningless until a grain is declared. | Staging never explodes an array; the intermediate layer does, once. The fact is declared at one reaction within one report, and death metrics count reports, not rows. | done |
| **Drug names are chaos.** Brands, generics, salt forms, dosage forms, typos. openFDA harmonizes only some of them. | The harmonized generic name where it exists (shortest spelling variant), the product name as reported otherwise — ~11% of cases. Brand-to-ingredient resolution via Drugs@FDA is next. | partial |
| **ClinicalTrials.gov overwrites itself.** A trial's status flips and the history is gone at the source. | The raw layer is an append-only log; a daily pull keeps every version. Turning that log into slowly changing dimensions is next. | partial |
| **Dates are dirty and reports arrive late.** ~40% of trial dates are month-precision; FDA receipt lags onset by years. | Parsed with a precision flag per date rather than silently nulled; late re-transmission is documented on the dashboard rather than hidden. | partial |
| **Conditions only mean something through a hierarchy.** MeSH descriptors sit in several tree positions at once — a DAG, not a tree. | Tree numbers are carried whole in staging so deduplication precedes fan-out; traversal is next. | next |

### Sources

| source | what it is | grain | publishing cadence | freshness warn / error |
|---|---|---|---|---|
| ClinicalTrials.gov API v2 | interventional oncology trials, phase 2/3 | one study per `nctId` | continuous; pulled nightly | 12h / 24h |
| openFDA FAERS | adverse-event case reports, four complete quarters (Q3 2025 – Q2 2026) | one report per `safetyreportid` | quarterly, with late republication | 45d / 120d |
| Drugs@FDA | approved applications, sponsors, products, ingredients | one application per `application_number` | bulk file, refreshed weekly | 14d / 30d |
| MeSH | descriptor vocabulary with tree numbers | one descriptor per `descriptor_ui` | annual | opted out |

Row counts are deliberately not listed here — they change with every pull.
`analyses/staging_row_reconciliation.sql` recomputes them from the warehouse;
dated readings live in [`docs/raw_counts.md`](docs/raw_counts.md) and
warehouse capability probes in [`docs/verification.md`](docs/verification.md).

## The product

An adverse-event outcomes dashboard over one complete year of FDA case
reports, served natively in Databricks on a Kimball star in the `prod`
catalog. Every merge to `main` redeploys prod; a nightly job pulls new trial
registrations and rebuilds it. The live dashboard requires registration in
the Databricks account (the free tier has no public links);
[`docs/adverse_event_outcomes.pdf`](docs/adverse_event_outcomes.pdf) is a
full export.

Measured 2026-08-25, four complete FAERS quarters (Q3 2025 – Q2 2026):
1,533,685 raw rows collapse to **1,436,423 cases** and **4,638,022 reaction
events** across 5,040 drugs and 16,849 reaction terms. With the FDA's
probable-duplicate flag excluded, the dashboard shows 1.17M cases, 3.55M
reactions and 79k cases with a fatal outcome. The caveats in its header are
part of the product: reporting rates are not risk rates, deaths are counted
per case rather than per symptom, and the duplicate flag (~19% of cases) is
excluded by default.

## Architecture

```text
  ClinicalTrials.gov       openFDA FAERS         Drugs@FDA            NLM MeSH
  API v2, pulled daily     quarterly zip parts   bulk file            annual XML
         |                        |                   |                   |
         +------------------------+---------+---------+-------------------+
                                            |
                                            v
                      src/loaders/*.py  -->  data/   ndjson.gz, parquet
                                            |
                                            |  databricks fs cp
                                            v
                      Volume   raw.landing.landing_files
                                            |
                                            |  COPY INTO   skips files already ingested
                                            v
                      raw.landing.*         append-only log: every pull kept, nothing overwritten
                                            |
                                            |  dbt build   into the dev, ci or prod catalog
                                            v
              +-----------------------------+------------------------------------+
              |  staging        one row per source entity; arrays carried whole  |
              |  intermediate   arrays exploded; one suspect drug per report     |
              |  marts          fact_reactions + date, drug, outcome, reaction   |
              +-----------------------------+------------------------------------+
                                            |
                                            v
                      AI/BI dashboard on prod.analytics
```

Every step is idempotent: the loaders skip output files that already exist,
`COPY INTO` skips files it has already ingested, and dbt rebuilds are
deterministic, so re-running any target is safe.

## Stack

| layer | tool | pinned |
|---|---|---|
| warehouse | Databricks Free Edition — serverless SQL warehouse (2X-Small), Unity Catalog, Volumes, Delta Lake, `COPY INTO` | — |
| transformation | dbt Core + dbt-databricks | 1.11.8 (`~=1.11.0`) |
| ingestion | Python — `httpx`, `ijson` (streaming JSON), `pyarrow`; Databricks CLI; `make` | Python 3.12 |
| environment | uv, lockfile-installed everywhere | `>=0.12.5,<0.13` via `required-version` |
| quality gate | sqlfluff (databricks dialect), pre-commit | 4.3.0 |
| CI/CD | GitHub Actions — required PR check, deploy on merge, nightly cron | — |
| consumption | Databricks AI/BI dashboard | — |

## Install

### Requirements

- [uv](https://docs.astral.sh/uv/) 0.12.x, [Databricks CLI](https://docs.databricks.com/dev-tools/cli/), `make`
- A Databricks workspace with a SQL warehouse and Unity Catalog. Free Edition
  is enough; the catalogs `raw`, `dev`, `ci`, `prod` and the Volume are created
  by `scripts/bootstrap_workspace.sql`.
- Disk for the data you pull: the sampled FAERS load is ~2 GB, four complete
  quarters ~12 GB.

### Steps

```sh
git clone https://github.com/fahad4058/drug-safety-warehouse.git
cd drug-safety-warehouse
uv sync                                   # installs the pinned toolchain from uv.lock
cp .env.example .env 2>/dev/null || true  # then fill in the three values below
source .env
uv run dbt debug                          # confirms the connection
pre-commit install                        # lint on commit, and block commits to main
```

`.env` holds `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH` and
`DBT_ENV_SECRET_DATABRICKS_TOKEN`. `profiles.yml` reads only those three
environment variables, so the same file serves the laptop and CI.

## Usage

```sh
make load-all                              # all four sources; FAERS defaults to a 3-part sample per quarter
make load-faers ARGS="--parts 40"          # every part of the two newest quarters (~3 GB each)
make load-ctgov ARGS="--since 2026-01-01"  # loader flags go through ARGS
make raw-counts                            # row counts straight from the warehouse

uv run dbt build                           # models, seeds and every test
uv run dbt source freshness                # writes target/sources.json; non-zero exit on error
```

Each `make load-<source>` runs the same three steps for one source: pull to
`data/`, upload to the Unity Catalog Volume, `COPY INTO raw.landing`. A build
ends with the line worth reading — the node count is the signal that every
test was found and run:

```text
Found 11 models, 1 analysis, 1 seed, 46 data tests, 4 sources, 733 macros
...
Done. PASS=58 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=58
```

Use `uv run dbt`, never bare `dbt` — the pinned dbt-core lives in the project's
virtual environment, and a globally installed dbt is a different program.

### Layout

```text
src/loaders/          one Python puller per source, writing to data/
scripts/              raw SQL sent straight to the warehouse: bootstrap,
                      COPY INTO, rerunnable profiling and marts checks
models/staging/       one folder per source — source declarations, staging
                      models, and their tests
models/intermediate/  the fan-out staging defers: arrays exploded, one
                      suspect drug resolved per report
models/marts/         the star: fact_reactions plus four dimensions
macros/               surrogate_key()
seeds/                reference data whose source of truth is this repo
analyses/             SQL that dbt compiles but never runs
docs/                 dated measurements, capability probes, dashboard export
.github/workflows/    pr (required check), deploy (CD), nightly (refresh)
Makefile              the landing pipeline, one target per source
```

Three directories hold `.sql` files and they are not interchangeable:
`scripts/` is raw SQL with no dbt involvement — `{{ ref() }}` in there reaches
the warehouse verbatim and fails; `models/` builds objects in the warehouse;
`analyses/` is compiled and handed back, never executed.

## Data model

```text
                    dim_date                          dim_outcome
                    date_key  (yyyymmdd)              outcome_key
                    year, quarter, month, weekday     E2B code, label, 'Not stated'
                           \                              /
                            \                            /
   dim_drug ----------- fact_reactions ------------------ dim_reaction
   drug_key             GRAIN  one reaction in one        reaction_key
   drug_name                   case report                reaction_term (MedDRA)
   name source          FK     date, drug, outcome, reaction
   reports              DD     safety_report_id
                        flags  is_serious, is_report_death,
                               is_probable_duplicate, n_suspect_drugs
```

`raw.landing` is an append-only log. Staging turns it into current state: one
row per source entity, casts applied, columns renamed to snake_case.

**Staging may correct grain. It may never create grain.** Collapsing several
pulls of the same study back to one row is correction, and belongs here.
Exploding a trial's arm groups into one row per arm is creation, and does not —
that is intermediate-layer work. Every array is carried through whole:
`armGroups`, `interventions`, `conditions`, `patient.drug`, `patient.reaction`,
`products`, `submissions`, `openfda`, `tree_numbers`. The consequence is that
deduplication always happens before any fan-out, which is the correct order: a
tree number that a later MeSH edition removed cannot come back to life.

Three of the four staging models keep the latest row per key. `drugsfda` is
different: it is scoped to the newest `_batch_id` first, because the source
re-publishes its entire catalogue on every pull, so the newest batch is a
mirror and a key missing from it means the application was withdrawn. Applying
that scoping to ClinicalTrials.gov would be wrong — its newest batch is a
seven-day delta, not a mirror. Same config, opposite answers, decided by what
the loader actually fetches.

The marts layer is a Kimball star. Dimensions are joined by md5 surrogate keys
rebuilt identically on both sides, so fact and dimension agree by
construction. Null keys never reach the fact — missing outcomes and drugs
route to explicit default rows, so the relationship tests cover every row.
Two documented attributions keep the model honest. A report's drug is its
first-listed suspect, though many reports name more than one. A drug's name is
openFDA's harmonized generic name where one exists — the shortest of its
spelling variants, since multi-element name arrays are variants of one
ingredient, not combination products — and otherwise the product name as the
reporter wrote it, the case for about 11% of reports, so a brand and its
generic can appear as separate rows until the Drugs@FDA crosswalk lands.
Death metrics count distinct reports, never reaction rows: a fatal report
marks all its reactions, so counting rows overstates deaths severalfold.

## Design decisions

### The raw layer is append-only, not upserted

```text
  pull A   90-day window   --+
  pull B   full backfill   --+-->  raw.landing.ctgov_studies   --QUALIFY row_number()-->  stg_ctgov__studies
  pull C.. daily deltas    --+     every pull kept                over _pulled_at desc      one row per study
```

Rows are only ever added, never updated, merged or deduplicated at load time.
Every row carries `_loaded_at`, `_source_file` and `_batch_id`; current state
is **derived** in staging, not stored in raw. The rejected alternative was
upsert — a tidier table that destroys history irreversibly. A log can always
be collapsed into current state; current state can never be expanded back
into a log.

**The cost, stated plainly.** Storage: the same entity lands again on every
pull that touches it — measured 2026-08-23, ClinicalTrials.gov holds 55,991
rows behind 49,131 studies, 12.3% pure duplication and growing; FAERS carries
97,262 follow-up versions across four quarters. And a permanent deduplication
obligation on every consumer: a staging model that forgets over-counts
silently, and the edges are sharp — FAERS `safetyreportversion` is a *string*,
so an uncast `order by` sorts `'9' > '103'` and keeps the oldest revision
while looking correct. Both costs are accepted: a raw layer you cannot replay
is just a slow copy of the source.

### Freshness thresholds follow publishing cadence, not a single rule

One threshold for every source does not survive contact with `COPY INTO`,
which skips files it has already ingested: a faultless daily run inserts
nothing and leaves `max(_loaded_at)` exactly where it was. Under a flat
26h/50h rule, FAERS and Drugs@FDA would go red within days and stay red no
matter how well the pipeline ran. So freshness here measures **data
recency**, not pipeline liveness, and each threshold matches how often that
source actually publishes. MeSH, published once a year, opts out with an
explicit `freshness: null`.

### `unique` belongs on staging models, not on sources

An append-only raw table holds duplicate natural keys by construction, so
`unique` at source level would be false by design on ClinicalTrials.gov, and
the other three would pass today and fail later — on the first revised FAERS
case, the first Drugs@FDA re-pull, the next MeSH edition. A test that passes
only because the system has not been exercised reads as coverage while
asserting nothing. Sources carry `not_null` on natural keys and load metadata;
`unique` sits on staging, where it verifies that deduplication actually
worked — and on FAERS it now collapses 97,262 rows.

### CI builds for real, not `--empty`

`dbt build --empty` resolves every `ref()` and `source()` to zero rows, and
data tests use the same resolver — every test would pass against nothing. The
full build runs in under four minutes on 1.4M cases, so CI runs it against a
dedicated `ci` catalog. The cost is that CI depends on the warehouse being
reachable.

## Development and CI/CD

```text
  feature branch --push--> pull request --> [pr]      sqlfluff lint + dbt build --target ci
                                                |     required status check, binds admins too
                                                v  green
                                          merge to main --> [deploy]   dbt build --target prod

  cron 02:30 UTC ----------------------------------------> [nightly]  make load-ctgov + dbt build --target prod
```

```sh
uv run sqlfluff lint models analyses                        # databricks dialect, jinja templater
uv run dbt build                                            # models, seeds, and every test
uv run python scripts/run_sql.py scripts/marts_checks.sql   # prod marts spot checks
```

CI always parses from scratch, so its test count is authoritative when it
disagrees with a local run. The toolchain is pinned end to end: packages by
`uv.lock`, `uv` itself by `required-version` in `pyproject.toml`, which the
workflows read. Lint rule exclusions are in `.sqlfluff`, each with the reason
it was excluded. Every pull request carries four headings — what changed,
why, the measured number, the tradeoff — and those descriptions are where the
design-decision notes above come from.

## Roadmap

- Snapshots over the staging views, so dimensions gain history instead of
  being overwritten — the daily pulls have been accumulating change since
  August 2026 for exactly this.
- Entity resolution between trials, approvals and adverse events, including
  the Drugs@FDA brand-to-ingredient crosswalk for the ~11% of cases openFDA
  leaves unharmonized.
- A multivalued bridge for reports with several suspect drugs; MeSH hierarchy
  traversal for condition roll-ups.
- Incremental and microbatch materialisations for the fact, an uploader that
  skips files already in the Volume, Airflow orchestration, hosted dbt docs,
  and a public path to the live dashboard.


## Contributing

Questions and suggestions are welcome as GitHub issues. Pull requests are
accepted: they must pass `sqlfluff lint` and the `lint and build` check, and
use the four-heading template in `.github/pull_request_template.md`.

## Data and disclaimer

Sources: [openFDA](https://open.fda.gov/) (FAERS, Drugs@FDA),
[ClinicalTrials.gov](https://clinicaltrials.gov/), and the
[NLM Medical Subject Headings](https://www.nlm.nih.gov/mesh/). This is an
engineering portfolio, not pharmacovigilance inference: FAERS records what
was *reported*, voluntarily and unevenly; disproportionate report counts are
not causal safety signals, nothing here measures the risk of any drug, and
nothing here is medical advice.
