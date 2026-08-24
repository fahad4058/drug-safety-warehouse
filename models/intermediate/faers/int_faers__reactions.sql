with reports as (

    select
        safety_report_id,
        receive_date,
        serious,
        seriousness_death,
        duplicate,
        reactions

    from {{ ref('stg_faers__reports') }}

),

exploded as (

    select
        r.safety_report_id,
        r.receive_date,
        r.serious,
        r.seriousness_death,
        r.duplicate,
        p.pos as reaction_seq, -- noqa: RF01
        p.col as reaction -- noqa: RF01

    from reports as r
        lateral view posexplode(reactions) p as pos, col

)

select
    e.safety_report_id,
    e.reaction_seq,
    e.receive_date,

    coalesce(nullif(upper(trim(e.reaction.reactionmeddrapt)), ''), 'NOT STATED') as reaction_term, -- noqa: RF01

    coalesce(e.reaction.reactionoutcome, '-1') as outcome_code, -- noqa: RF01

    coalesce(e.serious = '1', false) as is_serious,
    coalesce(e.seriousness_death = '1', false) as is_report_death,
    coalesce(e.duplicate = '1', false) as is_probable_duplicate,

    s.drug_name,
    s.drug_name_source,
    s.n_suspect_drugs

from exploded as e
inner join {{ ref('int_faers__suspect_drugs') }} as s
    on e.safety_report_id = s.safety_report_id
