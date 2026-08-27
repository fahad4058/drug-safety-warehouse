-- Every measured FAERS number this repo would otherwise write into prose.
-- Long format, one row per metric, so a new metric appends without changing
-- the shape -- and so this promotes to a materialized data_profile model
-- later without a rewrite.
--
--   uv run dbt show -s profile_faers --limit -1 --target prod
--
-- Counts only, never percentages: a percentage is a ratio of two facts, and
-- one stored beside its numerator is one more thing that can disagree with
-- it. `denominator` names the metric to divide by instead.
--
-- One statement, not seven: dbt compiles an analysis as a single node, and
-- the cross join means each source is scanned exactly once rather than once
-- per CTE reference.

with landed as (

    select
        count(*) as raw_rows,
        count(distinct safetyreportid) as raw_distinct_cases,
        count(distinct receiptdateformat) as receipt_date_format_variants

    from {{ source('faers', 'events') }}

),

staged as (

    select
        count(*) as staged_cases,
        count_if(duplicate is not null) as cases_flagged_duplicate,
        count_if(reactions is null or size(reactions) = 0) as cases_no_reactions,
        max(safety_report_version) as max_report_version

    from {{ ref('stg_faers__reports') }}

),

suspects as (

    select
        count_if(drug_name_source = 'openfda_generic') as drug_name_from_openfda,
        count_if(drug_name_source = 'medicinalproduct') as drug_name_from_verbatim,
        count_if(drug_name_source = 'none') as drug_name_absent,
        count_if(n_suspect_drugs >= 2) as cases_multi_suspect

    from {{ ref('int_faers__suspect_drugs') }}

),

reactions as (

    select
        count(*) as reaction_events,
        count_if(outcome_code = '-1') as reactions_no_outcome_code,
        count_if(not is_probable_duplicate) as reaction_events_ex_duplicates,
        count(distinct case
            when not is_probable_duplicate then safety_report_id
        end) as cases_ex_duplicates,
        count(distinct case
            when not is_probable_duplicate and outcome_code = '5'
                then safety_report_id
        end) as fatal_cases_ex_duplicates

    from {{ ref('int_faers__reactions') }}

),

drug_names as (

    select count(*) as distinct_drug_names
    from {{ ref('dim_drug') }}

),

reaction_terms as (

    select count(*) as distinct_reaction_terms
    from {{ ref('dim_reaction') }}

)

select
    m.metric, -- noqa: RF01
    m.value, -- noqa: RF01
    m.denominator -- noqa: RF01

from landed as l -- noqa
    cross join staged as s -- noqa
    cross join suspects as p -- noqa
    cross join reactions as r -- noqa
    cross join drug_names as d -- noqa
    cross join reaction_terms as t -- noqa
    lateral view stack(
        18,
        'raw_rows', cast(l.raw_rows as bigint), cast(null as string),
        'raw_distinct_cases', cast(l.raw_distinct_cases as bigint), 'raw_rows',
        'receipt_date_format_variants', cast(l.receipt_date_format_variants as bigint), cast(null as string),
        'staged_cases', cast(s.staged_cases as bigint), cast(null as string),
        'cases_flagged_duplicate', cast(s.cases_flagged_duplicate as bigint), 'staged_cases',
        'cases_no_reactions', cast(s.cases_no_reactions as bigint), 'staged_cases',
        'max_report_version', cast(s.max_report_version as bigint), cast(null as string),
        'drug_name_from_openfda', cast(p.drug_name_from_openfda as bigint), 'staged_cases',
        'drug_name_from_verbatim', cast(p.drug_name_from_verbatim as bigint), 'staged_cases',
        'drug_name_absent', cast(p.drug_name_absent as bigint), 'staged_cases',
        'cases_multi_suspect', cast(p.cases_multi_suspect as bigint), 'staged_cases',
        'reaction_events', cast(r.reaction_events as bigint), cast(null as string),
        'reactions_no_outcome_code', cast(r.reactions_no_outcome_code as bigint), 'reaction_events',
        'reaction_events_ex_duplicates', cast(r.reaction_events_ex_duplicates as bigint), 'reaction_events',
        'cases_ex_duplicates', cast(r.cases_ex_duplicates as bigint), 'staged_cases',
        'fatal_cases_ex_duplicates', cast(r.fatal_cases_ex_duplicates as bigint), 'cases_ex_duplicates',
        'distinct_drug_names', cast(d.distinct_drug_names as bigint), cast(null as string),
        'distinct_reaction_terms', cast(t.distinct_reaction_terms as bigint), cast(null as string)
    ) m as metric, value, denominator

order by 1
