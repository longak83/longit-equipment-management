-- Longit: outsourced services (software, internet, digital signatures, domains and other subscriptions)
-- Additive migration only. No existing asset/maintenance records are changed.
begin;

create table if not exists public.outsourced_services (
  id uuid primary key default gen_random_uuid(),
  service_code text not null unique,
  service_name text not null,
  service_type text not null default 'Khác' check (service_type in (
    'Internet/Viễn thông',
    'Chữ ký số/Chứng thư số',
    'Phần mềm/Bản quyền',
    'Tên miền/Website/SSL',
    'Dịch vụ trực tuyến',
    'Khác'
  )),
  provider text,
  contract_number text,
  start_date date,
  expiry_date date,
  reminder_days integer not null default 90 check (reminder_days >= 0 and reminder_days <= 3650),
  amount numeric(14,2) check (amount is null or amount >= 0),
  currency text not null default 'VND' check (currency in ('VND','USD','EUR','Khác')),
  quantity integer not null default 1 check (quantity > 0),
  department text,
  responsible_person text,
  responsible_email text,
  status text not null default 'Đang sử dụng' check (status in ('Đang sử dụng','Đang gia hạn','Tạm ngưng','Đã ngừng')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint outsourced_service_dates_valid check (start_date is null or expiry_date is null or expiry_date >= start_date)
);

create index if not exists outsourced_services_expiry_idx
  on public.outsourced_services(expiry_date) where status <> 'Đã ngừng';
create index if not exists outsourced_services_type_idx on public.outsourced_services(service_type);
create index if not exists outsourced_services_provider_idx on public.outsourced_services(provider);
create index if not exists outsourced_services_department_idx on public.outsourced_services(department);

create table if not exists public.outsourced_service_renewals (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.outsourced_services(id) on delete restrict,
  previous_expiry_date date,
  new_start_date date,
  new_expiry_date date not null,
  renewal_date date not null default current_date,
  amount numeric(14,2) check (amount is null or amount >= 0),
  provider text,
  contract_number text,
  handled_by text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists outsourced_service_renewals_service_idx
  on public.outsourced_service_renewals(service_id, renewal_date desc);

create or replace function public.set_outsourced_service_audit_fields()
returns trigger language plpgsql security invoker set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then new.created_by := auth.uid(); end if;
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists outsourced_services_audit_fields on public.outsourced_services;
create trigger outsourced_services_audit_fields
before insert or update on public.outsourced_services
for each row execute function public.set_outsourced_service_audit_fields();

alter table public.outsourced_services enable row level security;
alter table public.outsourced_service_renewals enable row level security;

drop policy if exists "authenticated read outsourced services" on public.outsourced_services;
create policy "authenticated read outsourced services"
on public.outsourced_services for select to authenticated using (true);
drop policy if exists "editors insert outsourced services" on public.outsourced_services;
create policy "editors insert outsourced services"
on public.outsourced_services for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update outsourced services" on public.outsourced_services;
create policy "editors update outsourced services"
on public.outsourced_services for update to authenticated
using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete outsourced services" on public.outsourced_services;
create policy "admins delete outsourced services"
on public.outsourced_services for delete to authenticated
using (public.current_user_role() = 'admin');

drop policy if exists "authenticated read outsourced service renewals" on public.outsourced_service_renewals;
create policy "authenticated read outsourced service renewals"
on public.outsourced_service_renewals for select to authenticated using (true);
drop policy if exists "editors insert outsourced service renewals" on public.outsourced_service_renewals;
create policy "editors insert outsourced service renewals"
on public.outsourced_service_renewals for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update outsourced service renewals" on public.outsourced_service_renewals;
create policy "editors update outsourced service renewals"
on public.outsourced_service_renewals for update to authenticated
using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete outsourced service renewals" on public.outsourced_service_renewals;
create policy "admins delete outsourced service renewals"
on public.outsourced_service_renewals for delete to authenticated
using (public.current_user_role() = 'admin');

-- Intentionally no anon/public policies: service contracts, prices and account references are internal data.
commit;
