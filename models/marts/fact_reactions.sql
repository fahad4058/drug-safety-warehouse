with reactions as (

    select * from {{ ref('int_faers__reactions') }}

)

select
    -- grain: one reported reaction within one case report
    {{ surrogate_key(['safety_report_id', 'reaction_seq']) }} as reaction_event_key,

    -- foreign keys, rebuilt from the same natural values the dims hash --
    -- fact and dim agree by construction
    cast(date_format(receive_date, 'yyyyMMdd') as int) as receive_date_key,
    {{ surrogate_key(['drug_name']) }} as drug_key,
    {{ surrogate_key(['outcome_code']) }} as outcome_key,
    {{ surrogate_key(['reaction_term']) }} as reaction_key,

    -- degenerate dimension
    safety_report_id,

    receive_date,
    is_serious,
    is_report_death,
    is_probable_duplicate,
    n_suspect_drugs

from reactions
