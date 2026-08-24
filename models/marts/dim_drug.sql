with drugs as (

    select
        drug_name,
        min(drug_name_source) as drug_name_source,
        count(*) as n_reports

    from {{ ref('int_faers__suspect_drugs') }}
    group by drug_name

)

select
    {{ surrogate_key(['drug_name']) }} as drug_key,
    drug_name,
    drug_name_source,
    n_reports

from drugs
