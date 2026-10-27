-- Asset handover and inter-unit transfer workflow.
-- Additive migration: preserves existing assignment/transfer rows and legacy columns.
-- Public history is served through sanitized views; raw assignment/transfer tables are no longer anon-readable.

begin;

alter table public.asset_transfers
  add column if not exists status text not null default 'completed',
  add column if not exists requested_by uuid references auth.users(id) on delete set null,
  add column if not exists requested_at timestamptz,
  add column if not exists approved_by_user_id uuid references auth.users(id) on delete set null,
  add column if not exists approved_at timestamptz,
  add column if not exists completed_by uuid references auth.users(id) on delete set null,
  add column if not exists completed_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists updated_at timestamptz not null default now();

-- Existing history is preserved and treated as completed legacy transfers.
update public.asset_transfers
set status = 'completed',
    completed_at = coalesce(completed_at, transfer_date::timestamp at time zone 'UTC'),
    requested_at = coalesce(requested_at, created_at)
where status is null or status = '' or completed_at is null or requested_at is null;

alter table public.asset_transfers
  alter column status set default 'pending';

alter table public.asset_transfers
  drop constraint if exists asset_transfers_status_check;
alter table public.asset_transfers
  add constraint asset_transfers_status_check
  check (status in ('pending','approved','rejected','completed','cancelled'));

create index if not exists asset_transfers_status_date_idx
  on public.asset_transfers(status, requested_at desc);
create index if not exists asset_transfers_asset_date_idx
  on public.asset_transfers(asset_id, transfer_date desc);

-- Explicit approver list. Admins manage this table; users can read their own assignment.
create table if not exists public.asset_transfer_approvers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.asset_transfer_approvers enable row level security;
drop policy if exists "admins manage transfer approvers" on public.asset_transfer_approvers;
create policy "admins manage transfer approvers"
  on public.asset_transfer_approvers for all to authenticated
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');
drop policy if exists "users read own transfer approver status" on public.asset_transfer_approvers;
create policy "users read own transfer approver status"
  on public.asset_transfer_approvers for select to authenticated
  using (user_id = auth.uid() or public.current_user_role() = 'admin');
grant select, insert, update, delete on public.asset_transfer_approvers to authenticated;

create or replace function public.is_asset_transfer_approver()
returns boolean
language sql stable security definer set search_path = public
as $$
  select auth.uid() is not null and (
    public.current_user_role() = 'admin'
    or exists (
      select 1 from public.asset_transfer_approvers p
      where p.user_id = auth.uid() and p.active
    )
  );
$$;
grant execute on function public.is_asset_transfer_approver() to authenticated;

-- Keep workflow state transitions inside RPCs, rather than trusting client-supplied status.
create or replace function public.guard_asset_transfer_workflow()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if current_setting('longit.transfer_workflow', true) = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.status := 'pending';
    new.requested_by := auth.uid();
    new.requested_at := coalesce(new.requested_at, now());
    new.approved_by_user_id := null;
    new.approved_at := null;
    new.completed_by := null;
    new.completed_at := null;
    new.rejection_reason := null;
    new.updated_at := now();
    return new;
  end if;
  if new.status is distinct from old.status
     or new.approved_by_user_id is distinct from old.approved_by_user_id
     or new.approved_at is distinct from old.approved_at
     or new.completed_by is distinct from old.completed_by
     or new.completed_at is distinct from old.completed_at
     or new.requested_by is distinct from old.requested_by
     or new.requested_at is distinct from old.requested_at then
    raise exception 'Trạng thái điều chuyển chỉ được thay đổi qua quy trình phê duyệt.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists asset_transfer_workflow_guard on public.asset_transfers;
create trigger asset_transfer_workflow_guard
before insert or update on public.asset_transfers
for each row execute function public.guard_asset_transfer_workflow();

create or replace function public.submit_asset_transfer(
  p_asset_id uuid,
  p_to_department text,
  p_to_location text,
  p_transfer_date date,
  p_reason text
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_asset public.assets%rowtype;
begin
  if auth.uid() is null then raise exception 'Vui lòng đăng nhập.'; end if;
  if not (
    public.has_module_permission('assets','create')
    or public.has_module_permission('vehicles','create')
  ) then raise exception 'Bạn không có quyền lập đề xuất điều chuyển.'; end if;
  if nullif(trim(p_to_department), '') is null then raise exception 'Vui lòng chọn đơn vị nhận.'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Vui lòng nhập lý do điều chuyển.'; end if;

  select * into v_asset from public.assets where id = p_asset_id and deleted_at is null for update;
  if not found then raise exception 'Không tìm thấy tài sản đang hoạt động.'; end if;

  perform set_config('longit.transfer_workflow','on',true);
  insert into public.asset_transfers(
    asset_id, from_department, to_department, from_location, to_location,
    transfer_date, reason, status, requested_by, requested_at, created_by, created_at, updated_at
  ) values (
    p_asset_id, v_asset.department, trim(p_to_department), v_asset.location,
    nullif(trim(p_to_location),''), p_transfer_date, trim(p_reason), 'pending',
    auth.uid(), now(), auth.uid(), now(), now()
  ) returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.submit_asset_transfer(uuid,text,text,date,text) to authenticated;

create or replace function public.review_asset_transfer(
  p_transfer_id uuid,
  p_approve boolean,
  p_rejection_reason text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_transfer public.asset_transfers%rowtype;
begin
  if auth.uid() is null or not public.is_asset_transfer_approver() then
    raise exception 'Bạn không có quyền phê duyệt điều chuyển.';
  end if;
  select * into v_transfer from public.asset_transfers where id = p_transfer_id for update;
  if not found then raise exception 'Không tìm thấy đề xuất điều chuyển.'; end if;
  if v_transfer.status <> 'pending' then raise exception 'Chỉ đề xuất đang chờ duyệt mới được xử lý.'; end if;
  if not p_approve and nullif(trim(p_rejection_reason),'') is null then
    raise exception 'Vui lòng nhập lý do từ chối.';
  end if;
  perform set_config('longit.transfer_workflow','on',true);
  update public.asset_transfers
  set status = case when p_approve then 'approved' else 'rejected' end,
      approved_by_user_id = case when p_approve then auth.uid() else null end,
      approved_at = now(),
      approved_by = case when p_approve then auth.uid()::text else approved_by end,
      rejection_reason = case when p_approve then null else trim(p_rejection_reason) end,
      updated_at = now()
  where id = p_transfer_id;
end;
$$;
grant execute on function public.review_asset_transfer(uuid,boolean,text) to authenticated;

create or replace function public.complete_asset_transfer(p_transfer_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_transfer public.asset_transfers%rowtype;
begin
  if auth.uid() is null then raise exception 'Vui lòng đăng nhập.'; end if;
  select * into v_transfer from public.asset_transfers where id = p_transfer_id for update;
  if not found then raise exception 'Không tìm thấy đề xuất điều chuyển.'; end if;
  if v_transfer.status <> 'approved' then raise exception 'Chỉ điều chuyển đã duyệt mới được hoàn tất.'; end if;
  if not (
    public.has_module_permission('assets','update')
    or public.has_module_permission('vehicles','update')
  ) then raise exception 'Bạn không có quyền xác nhận hoàn tất điều chuyển.'; end if;

  perform set_config('longit.transfer_workflow','on',true);
  update public.assets
  set department = v_transfer.to_department,
      location = v_transfer.to_location
  where id = v_transfer.asset_id and deleted_at is null;
  if not found then raise exception 'Không thể cập nhật tài sản; vui lòng kiểm tra hồ sơ.'; end if;

  update public.asset_transfers
  set status = 'completed', completed_by = auth.uid(),
      completed_at = now(), updated_at = now()
  where id = p_transfer_id;
end;
$$;
grant execute on function public.complete_asset_transfer(uuid) to authenticated;

-- Sanitize public history. Anonymous users can see asset/location/date/reason,
-- but not named custodians, creator IDs, approver IDs, or internal notes.
drop policy if exists "public read assignments for review" on public.asset_assignments;
drop policy if exists "public read transfers for review" on public.asset_transfers;

create or replace view public.public_asset_assignment_history
with (security_barrier = true)
as
select id, asset_id, department, location, assigned_at, returned_at
from public.asset_assignments;

create or replace view public.public_asset_transfer_history
with (security_barrier = true)
as
select id, asset_id, from_department, to_department, from_location, to_location,
       transfer_date, reason, status
from public.asset_transfers
where status = 'completed';

grant select on public.public_asset_assignment_history to anon, authenticated;
grant select on public.public_asset_transfer_history to anon, authenticated;

commit;
