with terms as (

    select
        reaction_term,
        count(*) as n_reactions

    from {{ ref('int_faers__reactions') }}
    group by reaction_term

)

select
    {{ surrogate_key(['reaction_term']) }} as reaction_key,
    reaction_term,
    n_reactions

from terms
