with source as (

    select * from {{ source('drugsfda', 'applications') }}

),

-- the newest bulk file only. drugsfda re-lands the WHOLE catalog every pull, so
-- the latest batch is a faithful mirror of it and an application missing from
-- that batch has been withdrawn. latest-row-per-key across all batches (the
-- ctgov pattern) would keep forever, and the snapshot's / hard_deletes could never fire.
-- ctgov must NOT be scoped this way: its loader
-- pulls only changed studies, so its newest batch is a delta, not a mirror.
latest_batch as (

    select *
    from source
    where _batch_id = (select max(s._batch_id) from source as s)

),

renamed as (

    select
        application_number,
        -- NDA / ANDA / BLA, parsed off the front of the key. brand-vs-generic
        -- is the axis the 24x letrozole fan-out runs along.
        regexp_extract(application_number, '^([A-Z]+)', 1) as application_type,
        sponsor_name,

        -- arrays and structs carried through untouched; the intermediate layer explodes them.
        -- openfda is the harmonization bridge to the same block inside faers
        -- drug entries.
        products,
        submissions,
        openfda,

        -- landing metadata
        cast(_pulled_at as timestamp) as _pulled_at,
        _loaded_at,
        _source_file,
        _batch_id

    from latest_batch

)

select *
from renamed
qualify row_number() over (partition by application_number order by _pulled_at desc) = 1
