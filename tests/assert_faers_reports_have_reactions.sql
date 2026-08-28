-- Singular test: any row returned is a failure.
select safety_report_id
from {{ ref('stg_faers__reports') }}
where reactions is null or size(reactions) = 0
