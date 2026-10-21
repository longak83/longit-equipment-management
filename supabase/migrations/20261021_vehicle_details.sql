-- Longit: private vehicle details and expiry reminders. Additive migration only.
begin;
create table if not exists public.vehicle_details (
  asset_id uuid primary key references public.assets(id) on delete cascade,
  license_plate text not null unique,
  primary_driver text,
  registration_inspection_date date,
  registration_expiry_date date,
  registration_reminder_days integer not null default 30 check (registration_reminder_days between 0 and 3650),
  insurance_expiry_date date,
  insurance_reminder_days integer not null default 30 check (insurance_reminder_days between 0 and 3650),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_inspection_dates_valid check (registration_inspection_date is null or registration_expiry_date is null or registration_expiry_date >= registration_inspection_date)
);
create index if not exists vehicle_details_registration_expiry_idx on public.vehicle_details(registration_expiry_date);
create index if not exists vehicle_details_insurance_expiry_idx on public.vehicle_details(insurance_expiry_date);
alter table public.vehicle_details enable row level security;
drop policy if exists "authenticated read vehicle details" on public.vehicle_details;
create policy "authenticated read vehicle details" on public.vehicle_details for select to authenticated using (true);
drop policy if exists "editors insert vehicle details" on public.vehicle_details;
create policy "editors insert vehicle details" on public.vehicle_details for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update vehicle details" on public.vehicle_details;
create policy "editors update vehicle details" on public.vehicle_details for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete vehicle details" on public.vehicle_details;
create policy "admins delete vehicle details" on public.vehicle_details for delete to authenticated using (public.current_user_role() = 'admin');
grant select, insert, update, delete on public.vehicle_details to authenticated;
-- Intentionally no anon/public policy for vehicle_details.
commit;
