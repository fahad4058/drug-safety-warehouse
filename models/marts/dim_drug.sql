with drugs as (

    select
        drug_name,
        -- a name can resolve by different paths across reports. priority, not
        -- min(): if openFDA harmonized this name for any report then the name IS
        -- an openFDA generic name, and min() would pick 'medicinalproduct'
        -- because it sorts first alphabetically.
        case
            when max(case when drug_name_source = 'openfda_generic' then 1 else 0 end) = 1
                then 'openfda_generic'
            when max(case when drug_name_source = 'medicinalproduct' then 1 else 0 end) = 1
                then 'medicinalproduct'
            else 'none'
        end as drug_name_source,
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
