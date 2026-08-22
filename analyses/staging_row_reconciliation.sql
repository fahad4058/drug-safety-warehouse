with landed as (

    select
        'ctgov' as source_name,
        count(*) as landed_rows,
        count(distinct protocolSection.identificationModule.nctId) as distinct_keys
    from {{ source('ctgov', 'studies') }}

    union all

    select
        'faers' as source_name,
        count(*) as landed_rows,
        count(distinct safetyreportid) as distinct_keys
    from {{ source('faers', 'events') }}

    union all

    select
        'drugsfda' as source_name,
        count(*) as landed_rows,
        count(distinct application_number) as distinct_keys
    from {{ source('drugsfda', 'applications') }}

    union all

    select
        'mesh' as source_name,
        count(*) as landed_rows,
        count(distinct descriptor_ui) as distinct_keys
    from {{ source('mesh', 'descriptors') }}

),

staged as (

    select
        'ctgov' as source_name,
        count(*) as staged_rows
    from {{ ref('stg_ctgov__studies') }}

    union all

    select
        'faers' as source_name,
        count(*) as staged_rows
    from {{ ref('stg_faers__reports') }}

    union all

    select
        'drugsfda' as source_name,
        count(*) as staged_rows
    from {{ ref('stg_drugsfda__applications') }}

    union all

    select
        'mesh' as source_name,
        count(*) as staged_rows
    from {{ ref('stg_mesh__descriptors') }}

)

select
    l.source_name,
    l.landed_rows,
    l.distinct_keys,
    s.staged_rows,
    l.landed_rows - s.staged_rows as rows_removed,
    s.staged_rows - l.distinct_keys as grain_gap
from landed as l
inner join staged as s
    on l.source_name = s.source_name
order by rows_removed desc
