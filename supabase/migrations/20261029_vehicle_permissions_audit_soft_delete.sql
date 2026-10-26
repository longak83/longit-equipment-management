-- Longit vehicle module permissions, soft deletion and immutable audit trail.
-- Additive migration. Review and run in Supabase SQL Editor before using these features.
begin;

create table if not exists public.module_permissions (
  user_id uuid not null references auth.users(id) on delete cascade,
  module_key text not null,
  can_view boolean not null default false,
  can_create boolean not null default false,
  can_update boolean not null default false,
  can_delete boolean not null default false,
  can_export boolean not null default false,
  data_scope text not null default 'all' check (data_scope in ('all','assigned')),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key (user_id, module_key),
  constraint module_permissions_module_key_check
    check (module_key ~ '^[a-z][a-z0-9_-]{1,40}$')
);
alter table public.module_permissions enable row level security;
drop policy if exists "users read own module permissions" on public.module_permissions;
create policy "users read own module permissions"
  on public.module_permissions for select to authenticated
  using (user_id = auth.uid() or public.current_user_role() = 'admin');
drop policy if exists "admins manage module permissions" on public.module_permissions;
create policy "admins manage module permissions"
  on public.module_permissions for all to authenticated
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');
grant select, insert, update, delete on public.module_permissions to authenticated;

create or replace function public.has_module_permission(p_module text, p_action text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_role text;
  v_perm public.module_permissions%rowtype;
  v_found boolean := false;
begin
  if auth.uid() is null then return false; end if;
  v_role := public.current_user_role();
  if v_role = 'admin' then return true; end if;

  select * into v_perm
  from public.module_permissions
  where user_id = auth.uid() and module_key = p_module;
  v_found := found;

  -- Preserve legacy Admin/Editor/Viewer behavior until an explicit module
  -- permission is assigned to that user. Once assigned, that row is authoritative.
  if not v_found then
    if p_action = 'view' then return v_role in ('editor','viewer'); end if;
    if p_action in ('create','update') then return v_role = 'editor'; end if;
    return false;
  end if;

  case p_action
    when 'view' then return v_perm.can_view;
    when 'create' then return v_perm.can_create;
    when 'update' then return v_perm.can_update;
    when 'delete' then return v_perm.can_delete;
    when 'export' then return v_perm.can_export;
    else return false;
  end case;
end;
$$;
grant execute on function public.has_module_permission(text,text) to authenticated;

-- Soft-delete markers keep deleted records available for audit/recovery.
alter table public.assets
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;
alter table public.maintenance_records
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;
alter table public.vehicle_details
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

create index if not exists assets_active_category_idx on public.assets(category, deleted_at);
create index if not exists maintenance_active_asset_idx on public.maintenance_records(asset_id, deleted_at, reported_at desc);
create index if not exists vehicle_details_active_expiry_idx on public.vehicle_details(deleted_at, registration_expiry_date, insurance_expiry_date);

-- Common audit trigger records the full before/after row and the authenticated actor.
create or replace function public.log_sensitive_record_changes()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_id text;
  v_table text := TG_TABLE_NAME;
begin
  if TG_OP = 'UPDATE' then v_before := to_jsonb(old); end if;
  if TG_OP = 'DELETE' then v_before := to_jsonb(old); end if;
  if TG_OP = 'INSERT' then v_after := to_jsonb(new); end if;
  if TG_OP = 'UPDATE' then v_after := to_jsonb(new); end if;
  if TG_TABLE_NAME = 'vehicle_details' then
    if TG_OP = 'DELETE' then v_id := old.asset_id::text; else v_id := new.asset_id::text; end if;
  elsif TG_TABLE_NAME = 'module_permissions' then
    if TG_OP = 'DELETE' then v_id := old.user_id::text || ':' || old.module_key;
    else v_id := new.user_id::text || ':' || new.module_key; end if;
  else
    if TG_OP = 'DELETE' then v_id := old.id::text; else v_id := new.id::text; end if;
  end if;

  insert into public.audit_logs(actor_id, table_name, record_id, action, before_data, after_data)
  values(auth.uid(), v_table, v_id,
    case
      when TG_OP = 'UPDATE' and (to_jsonb(new)->>'deleted_at') is distinct from (to_jsonb(old)->>'deleted_at')
        and (to_jsonb(new)->>'deleted_at') is not null then 'SOFT_DELETE'
      when TG_OP = 'UPDATE' and (to_jsonb(new)->>'deleted_at') is distinct from (to_jsonb(old)->>'deleted_at')
        and (to_jsonb(new)->>'deleted_at') is null then 'RESTORE'
      else TG_OP
    end,
    v_before, v_after);
  if TG_OP = 'DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists module_permissions_sensitive_audit on public.module_permissions;
create trigger module_permissions_sensitive_audit after insert or update or delete on public.module_permissions
for each row execute function public.log_sensitive_record_changes();

drop trigger if exists assets_audit_log on public.assets;
drop trigger if exists assets_sensitive_audit on public.assets;
create trigger assets_sensitive_audit after insert or update or delete on public.assets
for each row execute function public.log_sensitive_record_changes();
drop trigger if exists maintenance_sensitive_audit on public.maintenance_records;
create trigger maintenance_sensitive_audit after insert or update or delete on public.maintenance_records
for each row execute function public.log_sensitive_record_changes();
drop trigger if exists vehicle_details_sensitive_audit on public.vehicle_details;
create trigger vehicle_details_sensitive_audit after insert or update or delete on public.vehicle_details
for each row execute function public.log_sensitive_record_changes();

-- Protect audit records against direct client mutation; only database triggers write them.
revoke insert, update, delete, truncate on public.audit_logs from anon, authenticated;

-- Vehicle master data: module-specific permissions override legacy Editor rights.
drop policy if exists "authenticated read assets" on public.assets;
create policy "authenticated read assets" on public.assets for select to authenticated
  using (
    (category <> 'Ô tô' or public.has_module_permission('vehicles','view'))
    and (deleted_at is null or public.current_user_role() = 'admin')
  );
drop policy if exists "editors insert assets" on public.assets;
create policy "insert assets by module permission" on public.assets for insert to authenticated
  with check (
    (category = 'Ô tô' and public.has_module_permission('vehicles','create'))
    or (category <> 'Ô tô' and public.has_write_access())
  );
drop policy if exists "editors update assets" on public.assets;
create policy "update assets by module permission" on public.assets for update to authenticated
  using (
    (category = 'Ô tô' and public.has_module_permission('vehicles','update'))
    or (category <> 'Ô tô' and public.has_write_access())
  )
  with check (
    (category = 'Ô tô' and public.has_module_permission('vehicles','update')
      and (deleted_at is null or public.has_module_permission('vehicles','delete')))
    or (category <> 'Ô tô' and public.has_write_access()
      and (deleted_at is null or public.current_user_role() = 'admin'))
  );
drop policy if exists "admins delete assets" on public.assets;
create policy "no hard delete assets" on public.assets for delete to authenticated using (false);

-- Vehicle detail rows have their own permission checks. Soft-deletion is an UPDATE.
drop policy if exists "authenticated read vehicle details" on public.vehicle_details;
create policy "authenticated read vehicle details" on public.vehicle_details for select to authenticated
  using (public.has_module_permission('vehicles','view')
    and (deleted_at is null or public.current_user_role() = 'admin'));
drop policy if exists "editors insert vehicle details" on public.vehicle_details;
create policy "vehicle managers insert vehicle details" on public.vehicle_details for insert to authenticated
  with check (public.has_module_permission('vehicles','create'));
drop policy if exists "editors update vehicle details" on public.vehicle_details;
create policy "vehicle managers update vehicle details" on public.vehicle_details for update to authenticated
  using (public.has_module_permission('vehicles','update'))
  with check (public.has_module_permission('vehicles','update')
    and (deleted_at is null or public.has_module_permission('vehicles','delete')));
drop policy if exists "admins delete vehicle details" on public.vehicle_details;
create policy "no hard delete vehicle details" on public.vehicle_details for delete to authenticated using (false);

-- Vehicle repair/inspection history follows vehicle permissions when linked to a car.
drop policy if exists "authenticated read maintenance" on public.maintenance_records;
create policy "authenticated read maintenance" on public.maintenance_records for select to authenticated
  using (
    deleted_at is null and (
      exists (select 1 from public.assets a where a.id = maintenance_records.asset_id and a.category = 'Ô tô'
        and public.has_module_permission('vehicles','view'))
      or exists (select 1 from public.assets a where a.id = maintenance_records.asset_id and a.category <> 'Ô tô')
    )
    or public.current_user_role() = 'admin'
  );
drop policy if exists "editors insert maintenance" on public.maintenance_records;
create policy "insert maintenance by module permission" on public.maintenance_records for insert to authenticated
  with check (
    exists (select 1 from public.assets a where a.id = maintenance_records.asset_id and a.category = 'Ô tô'
      and public.has_module_permission('vehicles','create'))
    or exists (select 1 from public.assets a where a.id = maintenance_records.asset_id and a.category <> 'Ô tô'
      and public.has_write_access())
  );
drop policy if exists "editors update maintenance" on public.maintenance_records;
create policy "update maintenance by module permission" on public.maintenance_records for update to authenticated
  using (
    exists (select 1 from public.assets a where a.id = maintenance_records.asset_id and a.category = 'Ô tô'
      and public.has_module_permission('vehicles','update'))
    or exists (select 1 from public.assets a where a.id = maintenance_records.asset_id and a.category <> 'Ô tô'
      and public.has_write_access())
  )
  with check (
    exists (select 1 from public.assets a where a.id = maintenance_records.asset_id and a.category = 'Ô tô'
      and public.has_module_permission('vehicles','update')
      and (maintenance_records.deleted_at is null or public.has_module_permission('vehicles','delete')))
    or exists (select 1 from public.assets a where a.id = maintenance_records.asset_id and a.category <> 'Ô tô'
      and public.has_write_access() and (maintenance_records.deleted_at is null or public.current_user_role() = 'admin'))
  );
drop policy if exists "admins delete maintenance" on public.maintenance_records;
create policy "no hard delete maintenance records" on public.maintenance_records for delete to authenticated using (false);

-- Users with explicit vehicle permissions can inspect the audit trail; only Admin
-- can see the complete system audit history.
drop policy if exists "admins read audit logs" on public.audit_logs;
create policy "admins or vehicle managers read audit logs" on public.audit_logs for select to authenticated
  using (public.current_user_role() = 'admin' or
    (table_name in ('assets','vehicle_details','maintenance_records') and public.has_module_permission('vehicles','view')));

commit;
