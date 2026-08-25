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

    -- attribution = first-listed suspect (FAERS convention: primary suspect
    -- first). 47% of reports carry 2+ suspects, so this is a simplification,
    -- not a fact about the data; n_suspect_drugs keeps it visible.
    -- one name per drug: multi-element generic_name arrays (12.2% of reports,
    -- measured 2026-08-25) are overwhelmingly variant spellings of ONE
    -- ingredient -- salt forms, dosage forms, typos, biosimilar suffixes --
    -- not combination products. the plain ingredient name is almost always
    -- the shortest variant, so: sort by length, ties alphabetical, take the
    -- first. residual mis-picks (~215 reports: typos, brand names) are the
    -- Step 4 crosswalk's job. name tiers: openfda 93.9%, verbatim 5.4%,
    -- none 0.6%.
    --
    -- example: ["METHOTREXATE SODIUM", "METHOTREXATE", "METHOTREXATE INJECTION"]
    --   lengths: [20, 12, 22]
    --   sorted: ["METHOTREXATE", "METHOTREXATE SODIUM", "METHOTREXATE INJECTION"]
    --   result: "METHOTREXATE" (shortest, plain ingredient name)
    coalesce(
        nullif(upper(trim(try_element_at(
            array_sort(
                suspect.openfda.generic_name, -- noqa: RF01
                (l, r) -> case
                    when length(l) < length(r) then -1
                    when length(l) > length(r) then 1
                    when l < r then -1
                    when l > r then 1
                    else 0
                end
            ),
            1
        ))), ''),
        nullif(upper(trim(suspect.medicinalproduct)), ''), -- noqa: RF01
        'NO SUSPECT DRUG REPORTED'
    ) as drug_name,

    case
        when suspect is null then 'none'
        when suspect.openfda.generic_name is not null then 'openfda_generic' -- noqa: RF01
        else 'medicinalproduct'
    end as drug_name_source

from first_suspect
