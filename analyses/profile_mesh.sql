-- Every measured MeSH number this repo would otherwise write into prose.
-- Same shape as profile_faers: counts only, `denominator` names what to
-- divide by.
--
--   uv run dbt show -s profile_mesh --limit -1 --target prod --output json

with landed as (

    select
        count(*) as raw_rows,
        count(distinct descriptor_ui) as raw_distinct_descriptors

    from {{ source('mesh', 'descriptors') }}

),

staged as (

    select
        count(*) as staged_descriptors,
        count_if(size(tree_numbers) > 1) as descriptors_multi_tree,
        count_if(tree_numbers is null or size(tree_numbers) = 0) as descriptors_no_tree,
        max(size(tree_numbers)) as max_tree_numbers_per_descriptor

    from {{ ref('stg_mesh__descriptors') }}

),

tree as (

    select
        count(t.tree_number) as tree_numbers_total, -- noqa: RF01
        count(distinct t.tree_number) as tree_numbers_distinct -- noqa: RF01

    from {{ ref('stg_mesh__descriptors') }} as d -- noqa
        lateral view explode(d.tree_numbers) t as tree_number

)

select
    m.metric, -- noqa: RF01
    m.value, -- noqa: RF01
    m.denominator -- noqa: RF01

from landed as l -- noqa: AL05
cross join staged as s -- noqa: AL05
cross join tree as x -- noqa: AL05
    lateral view stack(
        8,
        'raw_rows', cast(l.raw_rows as bigint), cast(null as string),
        'raw_distinct_descriptors', cast(l.raw_distinct_descriptors as bigint), 'raw_rows',
        'staged_descriptors', cast(s.staged_descriptors as bigint), cast(null as string),
        'descriptors_multi_tree', cast(s.descriptors_multi_tree as bigint), 'staged_descriptors',
        'descriptors_no_tree', cast(s.descriptors_no_tree as bigint), 'staged_descriptors',
        'max_tree_numbers_per_descriptor', cast(s.max_tree_numbers_per_descriptor as bigint), cast(null as string),
        'tree_numbers_total', cast(x.tree_numbers_total as bigint), cast(null as string),
        'tree_numbers_distinct', cast(x.tree_numbers_distinct as bigint), 'tree_numbers_total'
    ) m as metric, value, denominator

order by 1
