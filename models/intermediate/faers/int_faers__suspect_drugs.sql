with reports as (

    select
        safety_report_id,
        filter(drugs, d -> d.drugcharacterization = '1') as suspects

    from {{ ref('stg_faers__reports') }}

),

first_suspect as (

    select
        safety_report_id,
        size(suspects) as n_suspect_drugs,
        try_element_at(suspects, 1) as suspect

    from reports

)

select
    safety_report_id,
    n_suspect_drugs,

    coalesce(
        nullif(upper(trim(array_join(suspect.openfda.generic_name, ' / '))), ''),
        nullif(upper(trim(suspect.medicinalproduct)), ''),
        'NO SUSPECT DRUG REPORTED'
    ) as drug_name,

    case
        when suspect is null then 'none'
        when suspect.openfda.generic_name is not null then 'openfda_generic'
        else 'medicinalproduct'
    end as drug_name_source

from first_suspect
