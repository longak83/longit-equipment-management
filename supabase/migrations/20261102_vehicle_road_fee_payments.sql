-- Longit: vehicle road maintenance fee payment periods and payment history.
-- Payment date is distinct from the period covered by the payment.
begin;
create table if not exists public.vehicle_road_fee_payments (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete cascade,
  paid_at date not null,
  period_start date not null,
  period_end date not null,
  amount numeric(14,2) check (amount is null or amount >= 0),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_road_fee_period_valid check (period_end > period_start)
);
create index if not exists vehicle_road_fee_payments_asset_period_idx
  on public.vehicle_road_fee_payments(asset_id, period_start desc);
create index if not exists vehicle_road_fee_payments_paid_at_idx
  on public.vehicle_road_fee_payments(paid_at desc);
alter table public.vehicle_road_fee_payments enable row level security;
drop policy if exists "authenticated read vehicle road fee payments" on public.vehicle_road_fee_payments;
create policy "authenticated read vehicle road fee payments"
  on public.vehicle_road_fee_payments for select to authenticated using (true);
drop policy if exists "editors insert vehicle road fee payments" on public.vehicle_road_fee_payments;
create policy "editors insert vehicle road fee payments"
  on public.vehicle_road_fee_payments for insert to authenticated
  with check (public.has_write_access() and (created_by is null or created_by = auth.uid()));
drop policy if exists "editors update vehicle road fee payments" on public.vehicle_road_fee_payments;
create policy "editors update vehicle road fee payments"
  on public.vehicle_road_fee_payments for update to authenticated
  using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete vehicle road fee payments" on public.vehicle_road_fee_payments;
create policy "admins delete vehicle road fee payments"
  on public.vehicle_road_fee_payments for delete to authenticated
  using (public.current_user_role() = 'admin');
grant select, insert, update, delete on public.vehicle_road_fee_payments to authenticated;
commit;
