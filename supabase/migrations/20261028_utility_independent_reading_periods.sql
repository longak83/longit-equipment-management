-- Allow electricity and water company totals to use independent meter-reading periods.
-- Existing period_start_date / period_end_date are retained for backwards compatibility.
begin;

alter table public.utility_company_totals
  add column if not exists electric_start_date date,
  add column if not exists electric_end_date date,
  add column if not exists water_start_date date,
  add column if not exists water_end_date date;

-- Preserve previously saved ranges for both resources until the editor is updated.
update public.utility_company_totals
set
  electric_start_date = coalesce(electric_start_date, period_start_date),
  electric_end_date = coalesce(electric_end_date, period_end_date),
  water_start_date = coalesce(water_start_date, period_start_date),
  water_end_date = coalesce(water_end_date, period_end_date)
where electric_start_date is null
   or electric_end_date is null
   or water_start_date is null
   or water_end_date is null;

alter table public.utility_company_totals
  drop constraint if exists utility_company_totals_electric_dates_check;
alter table public.utility_company_totals
  add constraint utility_company_totals_electric_dates_check
  check (electric_start_date is null or electric_end_date is null or electric_start_date <= electric_end_date);

alter table public.utility_company_totals
  drop constraint if exists utility_company_totals_water_dates_check;
alter table public.utility_company_totals
  add constraint utility_company_totals_water_dates_check
  check (water_start_date is null or water_end_date is null or water_start_date <= water_end_date);

commit;
