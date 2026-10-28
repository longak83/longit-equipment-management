-- Tighten transfer RPC authorization by checking the permission for the actual asset module.
-- This is a follow-up to 20261031_asset_handover_transfer_workflow.sql.

begin;

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
  v_module text;
begin
  if auth.uid() is null then raise exception 'Vui lòng đăng nhập.'; end if;
  if nullif(trim(p_to_department), '') is null then raise exception 'Vui lòng chọn đơn vị nhận.'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Vui lòng nhập lý do điều chuyển.'; end if;

  select * into v_asset
  from public.assets
  where id = p_asset_id and deleted_at is null
  for update;
  if not found then raise exception 'Không tìm thấy tài sản đang hoạt động.'; end if;

  v_module := case when v_asset.category = 'Ô tô' then 'vehicles' else 'assets' end;
  if not public.has_module_permission(v_module, 'create') then
    raise exception 'Bạn không có quyền lập đề xuất điều chuyển cho loại tài sản này.';
  end if;

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

create or replace function public.complete_asset_transfer(p_transfer_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_transfer public.asset_transfers%rowtype;
  v_asset public.assets%rowtype;
  v_module text;
begin
  if auth.uid() is null then raise exception 'Vui lòng đăng nhập.'; end if;

  select * into v_transfer
  from public.asset_transfers
  where id = p_transfer_id
  for update;
  if not found then raise exception 'Không tìm thấy đề xuất điều chuyển.'; end if;
  if v_transfer.status <> 'approved' then raise exception 'Chỉ điều chuyển đã duyệt mới được hoàn tất.'; end if;

  select * into v_asset
  from public.assets
  where id = v_transfer.asset_id and deleted_at is null
  for update;
  if not found then raise exception 'Không tìm thấy tài sản đang hoạt động.'; end if;

  v_module := case when v_asset.category = 'Ô tô' then 'vehicles' else 'assets' end;
  if not public.has_module_permission(v_module, 'update') then
    raise exception 'Bạn không có quyền hoàn tất điều chuyển cho loại tài sản này.';
  end if;

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

commit;
