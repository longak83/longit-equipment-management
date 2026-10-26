-- Longit asset management schema
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);
create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','editor','viewer')) default 'viewer',
  created_at timestamptz not null default now()
);
create or replace function public.current_user_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.user_roles where user_id = auth.uid() $$;
create or replace function public.has_write_access()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.current_user_role() in ('admin','editor'), false) $$;
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(), name text not null unique, created_at timestamptz not null default now()
);
create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(), name text not null, department_id uuid references public.departments(id) on delete set null, description text, created_at timestamptz not null default now()
);
create table if not exists public.asset_categories (
  id uuid primary key default gen_random_uuid(), name text not null unique, description text, created_at timestamptz not null default now()
);
insert into public.asset_categories(name) values ('Máy in'),('Máy photocopy'),('Máy tính'),('Thiết bị mạng/camera'),('Thang máy'),('Thiết bị chuyên ngành khác') on conflict (name) do nothing;
create table if not exists public.assets (
  id uuid primary key default gen_random_uuid(),
  asset_code text not null unique,
  name text not null,
  category text not null,
  manufacturer text,
  model text,
  serial_number text,
  department text,
  location text,
  custodian text,
  purchase_date date,
  purchase_cost numeric(14,2) not null default 0 check (purchase_cost >= 0),
  warranty_end date,
  status text not null default 'Đang sử dụng' check (status in ('Đang sử dụng','Dự phòng','Đang sửa chữa','Ngừng sử dụng','Đã thanh lý')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists assets_category_idx on public.assets(category);
create index if not exists assets_status_idx on public.assets(status);
create index if not exists assets_department_idx on public.assets(department);
create index if not exists assets_name_idx on public.assets using gin (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(asset_code,'') || ' ' || coalesce(manufacturer,'') || ' ' || coalesce(model,'')));
create or replace function public.set_asset_audit_fields()
returns trigger language plpgsql security invoker set search_path = public
as $$ begin
  if TG_OP = 'INSERT' then new.created_by := auth.uid(); end if;
  new.updated_by := auth.uid(); new.updated_at := now(); return new;
end $$;
drop trigger if exists assets_audit_fields on public.assets;
create trigger assets_audit_fields before insert or update on public.assets for each row execute function public.set_asset_audit_fields();
create table if not exists public.maintenance_records (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete restrict,
  record_type text not null default 'Sự cố' check (record_type in ('Sự cố','Sửa chữa','Bảo trì','Kiểm định')),
  reported_at date not null default current_date,
  description text not null,
  cause text,
  action_taken text,
  vendor text,
  cost numeric(14,2) not null default 0 check (cost >= 0),
  status text not null default 'Mới ghi nhận' check (status in ('Mới ghi nhận','Đang xử lý','Chờ vật tư','Đã hoàn thành','Đã hủy')),
  completed_at date,
  next_due_date date,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists maintenance_asset_idx on public.maintenance_records(asset_id, reported_at desc);
create table if not exists public.asset_assignments (
  id uuid primary key default gen_random_uuid(), asset_id uuid not null references public.assets(id) on delete restrict,
  custodian text not null, department text, location text, assigned_at date not null default current_date,
  returned_at date, handover_note text, created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.asset_transfers (
  id uuid primary key default gen_random_uuid(), asset_id uuid not null references public.assets(id) on delete restrict,
  from_department text, to_department text, from_location text, to_location text,
  transfer_date date not null default current_date, reason text, approved_by text,
  created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);
create table if not exists public.asset_attribute_definitions (
  id uuid primary key default gen_random_uuid(), category text not null, attribute_key text not null,
  label text not null, data_type text not null default 'text' check (data_type in ('text','number','date','boolean')),
  required boolean not null default false, unique(category, attribute_key)
);
create table if not exists public.asset_attribute_values (
  id uuid primary key default gen_random_uuid(), asset_id uuid not null references public.assets(id) on delete cascade,
  definition_id uuid not null references public.asset_attribute_definitions(id) on delete cascade,
  value_text text, value_number numeric, value_date date, value_boolean boolean,
  unique(asset_id, definition_id)
);
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key, actor_id uuid references auth.users(id) on delete set null,
  table_name text not null, record_id text, action text not null, before_data jsonb, after_data jsonb,
  created_at timestamptz not null default now()
);
create or replace function public.log_asset_changes()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  insert into public.audit_logs(actor_id,table_name,record_id,action,before_data,after_data)
  values(auth.uid(),'assets',coalesce(new.id,old.id)::text,TG_OP,
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('INSERT','UPDATE') then to_jsonb(new) else null end);
  if TG_OP = 'DELETE' then return old; else return new; end if;
end $$;
drop trigger if exists assets_audit_log on public.assets;
create trigger assets_audit_log after insert or update or delete on public.assets for each row execute function public.log_asset_changes();

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.departments enable row level security;
alter table public.locations enable row level security;
alter table public.asset_categories enable row level security;
alter table public.assets enable row level security;
alter table public.maintenance_records enable row level security;
alter table public.asset_assignments enable row level security;
alter table public.asset_transfers enable row level security;
alter table public.asset_attribute_definitions enable row level security;
alter table public.asset_attribute_values enable row level security;
alter table public.audit_logs enable row level security;
-- Public website: signed-in users can read assets; only admin/editor can write.
create policy "authenticated read assets" on public.assets for select to authenticated using (true);
create policy "editors insert assets" on public.assets for insert to authenticated with check (public.has_write_access());
create policy "editors update assets" on public.assets for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
create policy "admins delete assets" on public.assets for delete to authenticated using (public.current_user_role() = 'admin');
create policy "authenticated read categories" on public.asset_categories for select to authenticated using (true);
create policy "admins manage categories" on public.asset_categories for all to authenticated using (public.current_user_role()='admin') with check (public.current_user_role()='admin');
alter table public.user_roles enable row level security;
alter table public.profiles enable row level security;
drop policy if exists "admins manage roles" on public.user_roles;
drop policy if exists "users read own profile" on public.profiles;
drop policy if exists "users update own profile" on public.profiles;
create policy "users read own role or admins read all" on public.user_roles for select to authenticated using (user_id = auth.uid() or public.current_user_role() = 'admin');
create policy "admins manage roles" on public.user_roles for all to authenticated using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');
create policy "users read own profile or admins read all" on public.profiles for select to authenticated using (id = auth.uid() or public.current_user_role() = 'admin');
create policy "users update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "authenticated read departments" on public.departments for select to authenticated using (true);
create policy "admins manage departments" on public.departments for all to authenticated using (public.current_user_role()='admin') with check (public.current_user_role()='admin');
create policy "authenticated read locations" on public.locations for select to authenticated using (true);
create policy "admins manage locations" on public.locations for all to authenticated using (public.current_user_role()='admin') with check (public.current_user_role()='admin');
create policy "authenticated read maintenance" on public.maintenance_records for select to authenticated using (true);
create policy "editors insert maintenance" on public.maintenance_records for insert to authenticated with check (public.has_write_access());
create policy "editors update maintenance" on public.maintenance_records for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
create policy "admins delete maintenance" on public.maintenance_records for delete to authenticated using (public.current_user_role()='admin');
create policy "authenticated read assignments" on public.asset_assignments for select to authenticated using (true);
create policy "editors manage assignments" on public.asset_assignments for all to authenticated using (public.has_write_access()) with check (public.has_write_access());
create policy "authenticated read transfers" on public.asset_transfers for select to authenticated using (true);
create policy "editors manage transfers" on public.asset_transfers for all to authenticated using (public.has_write_access()) with check (public.has_write_access());
create policy "authenticated read attribute definitions" on public.asset_attribute_definitions for select to authenticated using (true);
create policy "admins manage attribute definitions" on public.asset_attribute_definitions for all to authenticated using (public.current_user_role()='admin') with check (public.current_user_role()='admin');
create policy "authenticated read attribute values" on public.asset_attribute_values for select to authenticated using (true);
create policy "editors manage attribute values" on public.asset_attribute_values for all to authenticated using (public.has_write_access()) with check (public.has_write_access());
create policy "admins read audit logs" on public.audit_logs for select to authenticated using (public.current_user_role()='admin');
-- No client-side insert/update/delete policy on audit_logs: audit entries are trigger-generated.
grant usage on schema public to anon, authenticated;
grant select on public.asset_categories to authenticated;
grant select, insert, update, delete on public.assets to authenticated;
grant select, insert, update, delete on public.maintenance_records, public.asset_assignments, public.asset_transfers, public.asset_attribute_values to authenticated;
grant select, insert, update, delete on public.asset_categories, public.departments, public.locations, public.asset_attribute_definitions, public.user_roles, public.profiles, public.audit_logs to authenticated;
