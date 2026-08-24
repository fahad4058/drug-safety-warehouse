-- Query 1 — fact row and report counts:

select
    count(*) as n_rows,
    count(distinct safety_report_id) as n_reports,
    sum(case when is_probable_duplicate then 1 else 0 end) as dup_rows
from dev.analytics.fact_reactions;

-- Query 2 — top drugs by report count, with fatal case breakdown:

select
    d.drug_name,
    count(distinct f.safety_report_id) as reports,
    count(distinct case when o.outcome_code = '5' then f.safety_report_id end) as fatal_reports
from dev.analytics.fact_reactions as f
inner join dev.analytics.dim_drug as d on f.drug_key = d.drug_key
inner join dev.analytics.dim_outcome as o on f.outcome_key = o.outcome_key
where not f.is_probable_duplicate
group by 1
order by 2 desc
limit 10;
