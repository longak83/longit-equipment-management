-- Longit migration: software licenses, digital signatures and renewals
-- Safe additive migration: creates new tables/views only; does not alter or delete existing asset data.
begin;

create table if not exists public.license_records (
  id uuid primary key default gen_random_uuid(),
  record_code text not null unique,
  item_name text not null,
  item_type text not null check (item_type in (
    'Phần mềm','Chữ ký số','Chứng thư số','Dịch vụ trực tuyến','Tên miền/SSL','Khác'
  )),
  provider text,
  contract_number text,
  contract_start_date date,
  expiry_date date not null,
  annual_cost numeric(14,2) not null default 0 check (annual_cost >= 0),
  department text,
  responsible_person text,
  responsible_email text,
  quantity integer not null default 1 check (quantity > 0),
  status text not null default 'Còn hiệu lực' check (status in (
    'Còn hiệu lực','Sắp hết hạn','Đang gia hạn','Đã gia hạn','Quá hạn','Đã ngừng'
  )),
  reminder_days integer[] not null default array[90,60,30,7],
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint license_reminder_days_allowed check (
    reminder_days <@ array[90,60,30,7]::integer[]
    and cardinality(reminder_days) > 0
  )
);

create index if not exists license_records_expiry_idx
  on public.license_records(expiry_date) where status <> 'Đã ngừng';
create index if not exists license_records_department_idx
  on public.license_records(department);
create index if not exists license_records_type_idx
  on public.license_records(item_type);

create table if not exists public.license_renewal_history (
  id uuid primary key default gen_random_uuid(),
  license_id uuid not null references public.license_records(id) on delete restrict,
  previous_expiry_date date,
  new_expiry_date date not null,
  renewal_date date not null default current_date,
  renewal_cost numeric(14,2) not null default 0 check (renewal_cost >= 0),
  provider text,
  contract_number text,
  reference_number text,
  handled_by text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists license_renewal_history_license_idx
  on public.license_renewal_history(license_id, renewal_date desc);

create or replace function public.set_license_audit_fields()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    new.created_by := auth.uid();
  end if;
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists license_records_audit_fields on public.license_records;
create trigger license_records_audit_fields
before insert or update on public.license_records
for each row execute function public.set_license_audit_fields();

create or replace function public.log_license_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs(actor_id, table_name, record_id, action, before_data, after_data)
  values (
    auth.uid(),
    'license_records',
    coalesce(new.id, old.id)::text,
    TG_OP,
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );
  if TG_OP = 'DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists license_records_audit_log on public.license_records;
create trigger license_records_audit_log
after insert or update or delete on public.license_records
for each row execute function public.log_license_changes();

alter table public.license_records enable row level security;
alter table public.license_renewal_history enable row level security;

drop policy if exists "authenticated read license records" on public.license_records;
create policy "authenticated read license records"
on public.license_records for select to authenticated using (true);

drop policy if exists "editors insert license records" on public.license_records;
create policy "editors insert license records"
on public.license_records for insert to authenticated
with check (public.has_write_access());

drop policy if exists "editors update license records" on public.license_records;
create policy "editors update license records"
on public.license_records for update to authenticated
using (public.has_write_access()) with check (public.has_write_access());

drop policy if exists "admins delete license records" on public.license_records;
create policy "admins delete license records"
on public.license_records for delete to authenticated
using (public.current_user_role() = 'admin');

drop policy if exists "authenticated read license renewal history" on public.license_renewal_history;
create policy "authenticated read license renewal history"
on public.license_renewal_history for select to authenticated using (true);

drop policy if exists "editors insert license renewal history" on public.license_renewal_history;
create policy "editors insert license renewal history"
on public.license_renewal_history for insert to authenticated
with check (public.has_write_access());

drop policy if exists "editors update license renewal history" on public.license_renewal_history;
create policy "editors update license renewal history"
on public.license_renewal_history for update to authenticated
using (public.has_write_access()) with check (public.has_write_access());

drop policy if exists "admins delete license renewal history" on public.license_renewal_history;
create policy "admins delete license renewal history"
on public.license_renewal_history for delete to authenticated
using (public.current_user_role() = 'admin');

grant select, insert, update, delete on public.license_records, public.license_renewal_history to authenticated;

-- Security-invoker view: respects RLS and exposes calculated expiry warnings.
create or replace view public.license_expiry_overview
with (security_invoker = true)
as
select
  l.*,
  (l.expiry_date - current_date) as days_until_expiry,
  case
    when l.status = 'Đã ngừng' then 'Đã ngừng'
    when l.expiry_date < current_date then 'Quá hạn'
    when l.expiry_date = current_date then 'Hết hạn hôm nay'
    when l.expiry_date - current_date <= 7 then 'Còn 7 ngày trở xuống'
    when l.expiry_date - current_date <= 30 then 'Còn 30 ngày trở xuống'
    when l.expiry_date - current_date <= 60 then 'Còn 60 ngày trở xuống'
    when l.expiry_date - current_date <= 90 then 'Còn 90 ngày trở xuống'
    else 'Còn hiệu lực'
  end as expiry_alert
from public.license_records l;

grant select on public.license_expiry_overview to authenticated;

commit;
