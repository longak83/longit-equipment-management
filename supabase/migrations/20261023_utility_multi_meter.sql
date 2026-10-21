-- Longit: multiple rooms/meters, readings with auditable consumption overrides, and bill line snapshots.
-- Additive only. This migration is committed to the feature branch; it is not run against Supabase.
begin;

alter table public.utility_tenants
  add column if not exists billing_cycle text not null default 'monthly'
    check (billing_cycle in ('monthly','quarterly'));

create table if not exists public.utility_rooms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.utility_tenants(id) on delete cascade,
  room_name text not null,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, room_name)
);
create index if not exists utility_rooms_tenant_idx on public.utility_rooms(tenant_id, active);

create table if not exists public.utility_meters (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.utility_rooms(id) on delete cascade,
  utility_type text not null check (utility_type in ('electricity','water')),
  serial_number text not null,
  meter_label text,
  custom_rate numeric(14,2) check (custom_rate is null or custom_rate >= 0),
  active boolean not null default true,
  installed_at date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (utility_type, serial_number)
);
create index if not exists utility_meters_room_idx on public.utility_meters(room_id, active);

-- One reading per meter per reading date. Both raw readings and calculated/overridden usage are preserved.
create table if not exists public.utility_meter_readings (
  id uuid primary key default gen_random_uuid(),
  meter_id uuid not null references public.utility_meters(id) on delete restrict,
  reading_date date not null,
  reading_value numeric(16,3) not null check (reading_value >= 0),
  previous_reading_value numeric(16,3) check (previous_reading_value is null or previous_reading_value >= 0),
  calculated_usage numeric(16,3) check (calculated_usage is null or calculated_usage >= 0),
  billed_usage numeric(16,3) check (billed_usage is null or billed_usage >= 0),
  usage_overridden boolean not null default false,
  override_reason text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (meter_id, reading_date),
  check (not usage_overridden or nullif(trim(override_reason), '') is not null)
);
create index if not exists utility_meter_readings_meter_date_idx on public.utility_meter_readings(meter_id, reading_date desc);

-- Immutable snapshots for each meter included in a generated bill.
create table if not exists public.utility_bill_meter_lines (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.utility_bills(id) on delete cascade,
  meter_id uuid references public.utility_meters(id) on delete set null,
  room_name_snapshot text not null,
  meter_type_snapshot text not null check (meter_type_snapshot in ('electricity','water')),
  meter_serial_snapshot text not null,
  previous_reading numeric(16,3),
  current_reading numeric(16,3),
  calculated_usage numeric(16,3),
  billed_usage numeric(16,3) not null default 0,
  usage_overridden boolean not null default false,
  override_reason text,
  unit_rate numeric(14,2) not null default 0,
  line_amount numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  check (not usage_overridden or nullif(trim(override_reason), '') is not null)
);
create index if not exists utility_bill_meter_lines_bill_idx on public.utility_bill_meter_lines(bill_id);

alter table public.utility_rooms enable row level security;
alter table public.utility_meters enable row level security;
alter table public.utility_meter_readings enable row level security;
alter table public.utility_bill_meter_lines enable row level security;

drop policy if exists "authenticated read utility rooms" on public.utility_rooms;
create policy "authenticated read utility rooms" on public.utility_rooms for select to authenticated using (true);
drop policy if exists "editors insert utility rooms" on public.utility_rooms;
create policy "editors insert utility rooms" on public.utility_rooms for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update utility rooms" on public.utility_rooms;
create policy "editors update utility rooms" on public.utility_rooms for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete utility rooms" on public.utility_rooms;
create policy "admins delete utility rooms" on public.utility_rooms for delete to authenticated using (public.current_user_role() = 'admin');

drop policy if exists "authenticated read utility meters" on public.utility_meters;
create policy "authenticated read utility meters" on public.utility_meters for select to authenticated using (true);
drop policy if exists "editors insert utility meters" on public.utility_meters;
create policy "editors insert utility meters" on public.utility_meters for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update utility meters" on public.utility_meters;
create policy "editors update utility meters" on public.utility_meters for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete utility meters" on public.utility_meters;
create policy "admins delete utility meters" on public.utility_meters for delete to authenticated using (public.current_user_role() = 'admin');

drop policy if exists "authenticated read utility readings" on public.utility_meter_readings;
create policy "authenticated read utility readings" on public.utility_meter_readings for select to authenticated using (true);
drop policy if exists "editors insert utility readings" on public.utility_meter_readings;
create policy "editors insert utility readings" on public.utility_meter_readings for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update utility readings" on public.utility_meter_readings;
create policy "editors update utility readings" on public.utility_meter_readings for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete utility readings" on public.utility_meter_readings;
create policy "admins delete utility readings" on public.utility_meter_readings for delete to authenticated using (public.current_user_role() = 'admin');

drop policy if exists "authenticated read utility bill lines" on public.utility_bill_meter_lines;
create policy "authenticated read utility bill lines" on public.utility_bill_meter_lines for select to authenticated using (true);
drop policy if exists "editors insert utility bill lines" on public.utility_bill_meter_lines;
create policy "editors insert utility bill lines" on public.utility_bill_meter_lines for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update utility bill lines" on public.utility_bill_meter_lines;
create policy "editors update utility bill lines" on public.utility_bill_meter_lines for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete utility bill lines" on public.utility_bill_meter_lines;
create policy "admins delete utility bill lines" on public.utility_bill_meter_lines for delete to authenticated using (public.current_user_role() = 'admin');

grant select, insert, update, delete on public.utility_rooms to authenticated;
grant select, insert, update, delete on public.utility_meters to authenticated;
grant select, insert, update, delete on public.utility_meter_readings to authenticated;
grant select, insert, update, delete on public.utility_bill_meter_lines to authenticated;

commit;
