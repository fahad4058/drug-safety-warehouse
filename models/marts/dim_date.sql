with spine as (

    select explode(sequence(to_date('1960-01-01'), to_date('2027-12-31'), interval 1 day)) as date_day

)

select
    cast(date_format(date_day, 'yyyyMMdd') as int) as date_key,
    date_day,
    year(date_day) as year_number,
    quarter(date_day) as quarter_of_year,
    month(date_day) as month_of_year,
    date_format(date_day, 'MMMM') as month_name,
    concat(year(date_day), '-Q', quarter(date_day)) as year_quarter,
    dayofweek(date_day) as day_of_week,
    date_format(date_day, 'EEEE') as day_name,
    dayofweek(date_day) in (1, 7) as is_weekend

from spine
