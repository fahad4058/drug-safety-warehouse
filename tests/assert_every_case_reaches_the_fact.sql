select r.safety_report_id

from {{ ref('stg_faers__reports') }} as r
where not exists (
    select 1
    from {{ ref('fact_reactions') }} as f
    where f.safety_report_id = r.safety_report_id
)
