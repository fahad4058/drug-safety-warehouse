with source as (

    select * from {{ source('mesh', 'descriptors') }}

),

renamed as (

    select
        descriptor_ui,
        descriptor_name,

        -- array carried through untouched, like ctgov's arm groups and faers's
        -- drugs. 53% of descriptors hold more than one tree number (max 24);
        -- the fan-out to one row per tree number is intermediate-layer work.
        tree_numbers,

        -- landing metadata
        cast(_pulled_at as timestamp) as _pulled_at,
        _loaded_at,
        _source_file,
        _batch_id

    from source

)

select *
from renamed
qualify row_number() over (partition by descriptor_ui order by _pulled_at desc) = 1
