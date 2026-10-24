-- Utility billing follow-up: per-tenant cycle defaults and water deduction snapshots.
-- Additive and idempotent; do not run on production until reviewed/approved.
begin;

alter table public.utility_tenants
  alter column billing_cycle set default 'quarterly';

-- Only the table-tennis club bills monthly; other existing tenants bill quarterly.
update public.utility_tenants
set billing_cycle = case
  when name ilike '%Câu lạc bộ Bóng bàn%' then 'monthly'
  else 'quarterly'
end;

alter table public.utility_bills
  add column if not exists water_adjustment_m3 numeric(14,3) not null default 0
    check (water_adjustment_m3 >= 0),
  add column if not exists water_adjustment_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'utility_bill_water_adjustment_reason'
      and conrelid = 'public.utility_bills'::regclass
  ) then
    alter table public.utility_bills
      add constraint utility_bill_water_adjustment_reason
      check (water_adjustment_m3 = 0 or nullif(trim(water_adjustment_reason), '') is not null);
  end if;
end $$;

commit;
