select
    safety_report_id,
    reaction_seq,
    count(*) as n_rows

from {{ ref('int_faers__reactions') }}
group by 1, 2
having count(*) > 1
