-- Query 1 — fact row and report counts:

-- select
--     count(*) as n_rows,
--     count(distinct safety_report_id) as n_reports,
--     sum(case when is_probable_duplicate then 1 else 0 end) as dup_rows
-- from dev.analytics.fact_reactions;

-- -- Query 2 — top drugs by report count, with fatal case breakdown:

-- select
--     d.drug_name,
--     count(distinct f.safety_report_id) as reports,
--     count(distinct case when o.outcome_code = '5' then f.safety_report_id end) as fatal_reports
-- from dev.analytics.fact_reactions as f
-- inner join dev.analytics.dim_drug as d on f.drug_key = d.drug_key
-- inner join dev.analytics.dim_outcome as o on f.outcome_key = o.outcome_key
-- where not f.is_probable_duplicate
-- group by 1
-- order by 2 desc
-- limit 20;

-- Query 3 - check prod.analytics data objects
-- select table_name
-- from prod.information_schema.tables
-- where table_schema = 'analytics'
-- order by 1

-- Query 4 — How many drug names per suspect (distribution):

-- with s as (
--   select try_element_at(filter(drugs, d -> d.drugcharacterization = '1'), 1) as suspect
--   from dev.analytics.stg_faers__reports
-- )
-- select
--   size(suspect.openfda.generic_name) as n_names,
--   count(*) as reports
-- from s
-- group by 1
-- order by 1;

-- -- Query 5 — Which drugs have multiple names (combination drugs):

-- with s as (
--   select try_element_at(filter(drugs, d -> d.drugcharacterization = '1'), 1) as suspect
--   from dev.analytics.stg_faers__reports
-- )
-- select
--   suspect.openfda.generic_name as names,
--   count(*) as reports
-- from s
-- where size(suspect.openfda.generic_name) >= 2
-- group by 1
-- order by 2 desc;

-- Query 6 -
-- Spot check: verify ACETAMINOPHEN and MYCOPHENOLATE variants merged correctly
-- Expected: plain names on top with n_reports including all variants
select drug_name, n_reports
from dev.analytics.dim_drug
where drug_name like 'ACETAMINOPHEN%' or drug_name like 'MYCOPHENOLATE%'
order by 2 desc;

-- Query 7 -
-- Spot check: total drug count after consolidation
-- Expected: ~200-500 fewer drugs than before (variants now merged into single rows)
select count(*) as n_drugs
from dev.analytics.dim_drug;
