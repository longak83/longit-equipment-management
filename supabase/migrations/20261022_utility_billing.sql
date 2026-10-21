-- Longit: tenant utility meters, configurable rates, and immutable monthly bill snapshots.
-- Additive migration only. No anon/public read policy is created.
begin;

create table if not exists public.utility_settings (
  id boolean primary key default true check (id = true),
  default_electric_rate numeric(14,2) not null default 0 check (default_electric_rate >= 0),
  default_water_rate numeric(14,2) not null default 0 check (default_water_rate >= 0),
  default_vat_rate numeric(5,2) not null default 8 check (default_vat_rate >= 0 and default_vat_rate <= 100),
  updated_at timestamptz not null default now()
);

insert into public.utility_settings (id, default_electric_rate, default_water_rate, default_vat_rate)
values (true, 0, 0, 8) on conflict (id) do nothing;

create table if not exists public.utility_tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_person text,
  electric_meter_number text,
  water_meter_number text,
  uses_electricity boolean not null default true,
  uses_water boolean not null default true,
  custom_electric_rate numeric(14,2) check (custom_electric_rate is null or custom_electric_rate >= 0),
  custom_water_rate numeric(14,2) check (custom_water_rate is null or custom_water_rate >= 0),
  vat_mode text not null default 'default' check (vat_mode in ('default','yes','no')),
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint utility_tenant_has_service check (uses_electricity or uses_water)
);
create index if not exists utility_tenants_name_idx on public.utility_tenants(name);

create table if not exists public.utility_bills (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.utility_tenants(id) on delete restrict,
  billing_period date not null,
  bill_date date not null default current_date,
  include_electricity boolean not null default false,
  include_water boolean not null default false,
  electric_previous numeric(14,3),
  electric_current numeric(14,3),
  electric_usage numeric(14,3),
  electric_rate numeric(14,2),
  electric_amount numeric(14,2),
  water_previous numeric(14,3),
  water_current numeric(14,3),
  water_usage numeric(14,3),
  water_rate numeric(14,2),
  water_amount numeric(14,2),
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  vat_enabled boolean not null default true,
  vat_rate numeric(5,2) not null default 8 check (vat_rate >= 0 and vat_rate <= 100),
  vat_amount numeric(14,2) not null default 0 check (vat_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  notes text,
  created_at timestamptz not null default now(),
  constraint utility_bill_has_service check (include_electricity or include_water),
  constraint utility_bill_electric_values check (not include_electricity or (electric_previous is not null and electric_current is not null and electric_usage is not null and electric_rate is not null and electric_amount is not null and electric_current >= electric_previous)),
  constraint utility_bill_water_values check (not include_water or (water_previous is not null and water_current is not null and water_usage is not null and water_rate is not null and water_amount is not null and water_current >= water_previous)),
  constraint utility_bill_one_per_tenant_period unique (tenant_id, billing_period)
);
create index if not exists utility_bills_period_idx on public.utility_bills(billing_period desc);
create index if not exists utility_bills_tenant_idx on public.utility_bills(tenant_id, billing_period desc);

alter table public.utility_settings enable row level security;
alter table public.utility_tenants enable row level security;
alter table public.utility_bills enable row level security;

drop policy if exists "authenticated read utility settings" on public.utility_settings;
create policy "authenticated read utility settings" on public.utility_settings for select to authenticated using (true);
drop policy if exists "editors update utility settings" on public.utility_settings;
create policy "editors update utility settings" on public.utility_settings for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "editors insert utility settings" on public.utility_settings;
create policy "editors insert utility settings" on public.utility_settings for insert to authenticated with check (public.has_write_access());

drop policy if exists "authenticated read utility tenants" on public.utility_tenants;
create policy "authenticated read utility tenants" on public.utility_tenants for select to authenticated using (true);
drop policy if exists "editors insert utility tenants" on public.utility_tenants;
create policy "editors insert utility tenants" on public.utility_tenants for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update utility tenants" on public.utility_tenants;
create policy "editors update utility tenants" on public.utility_tenants for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete utility tenants" on public.utility_tenants;
create policy "admins delete utility tenants" on public.utility_tenants for delete to authenticated using (public.current_user_role() = 'admin');

drop policy if exists "authenticated read utility bills" on public.utility_bills;
create policy "authenticated read utility bills" on public.utility_bills for select to authenticated using (true);
drop policy if exists "editors insert utility bills" on public.utility_bills;
create policy "editors insert utility bills" on public.utility_bills for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update utility bills" on public.utility_bills;
create policy "editors update utility bills" on public.utility_bills for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete utility bills" on public.utility_bills;
create policy "admins delete utility bills" on public.utility_bills for delete to authenticated using (public.current_user_role() = 'admin');

grant select, insert, update, delete on public.utility_settings to authenticated;
grant select, insert, update, delete on public.utility_tenants to authenticated;
grant select, insert, update, delete on public.utility_bills to authenticated;

commit;
