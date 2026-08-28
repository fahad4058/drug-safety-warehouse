-- Every measured Drugs@FDA number this repo would otherwise write into prose.
--
-- raw_batches is a diagnostic, not decoration: the loader writes a fixed
-- filename and skips if it exists, so a second pull cannot land. If this
-- stays at 1 after a re-run, that is the loader, not the data.
--
--   uv run dbt show -s profile_drugsfda --limit -1 --target prod --output json

with landed as (

    select
        count(*) as raw_rows,
        count(distinct application_number) as raw_distinct_applications,
        count(distinct _batch_id) as raw_batches

    from {{ source('drugsfda', 'applications') }}

),

staged as (

    select
        count(*) as staged_applications,
        count_if(openfda is null) as applications_no_openfda,
        count_if(products is null or size(products) = 0) as applications_no_products,
        sum(size(products)) as products_total,
        max(size(products)) as max_products_per_application

    from {{ ref('stg_drugsfda__applications') }}

)

select
    m.metric, -- noqa: RF01
    m.value, -- noqa: RF01
    m.denominator -- noqa: RF01

from landed as l -- noqa: AL05
cross join staged as s -- noqa: AL05
    lateral view stack(
        8,
        'raw_rows', cast(l.raw_rows as bigint), cast(null as string),
        'raw_distinct_applications', cast(l.raw_distinct_applications as bigint), 'raw_rows',
        'raw_batches', cast(l.raw_batches as bigint), cast(null as string),
        'staged_applications', cast(s.staged_applications as bigint), cast(null as string),
        'applications_no_openfda', cast(s.applications_no_openfda as bigint), 'staged_applications',
        'applications_no_products', cast(s.applications_no_products as bigint), 'staged_applications',
        'products_total', cast(s.products_total as bigint), cast(null as string),
        'max_products_per_application', cast(s.max_products_per_application as bigint), cast(null as string)
    ) m as metric, value, denominator

order by 1
