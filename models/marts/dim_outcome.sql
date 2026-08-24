with codes as (

    select
        outcome_code,
        outcome_label
    from {{ ref('faers_outcome_codes') }}

    union all

    select
        '-1' as outcome_code,
        'Not stated' as outcome_label

)

select
    {{ surrogate_key(['outcome_code']) }} as outcome_key,
    outcome_code,
    outcome_label

from codes
