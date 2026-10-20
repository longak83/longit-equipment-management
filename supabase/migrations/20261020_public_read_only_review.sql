-- Temporary public read-only access for software review.
-- Anonymous visitors can read asset and maintenance information, but cannot write.
-- Does not grant public access to profiles, roles, or audit logs.
begin;

drop policy if exists "public read assets for review" on public.assets;
create policy "public read assets for review"
  on public.assets for select to anon using (true);

drop policy if exists "public read categories for review" on public.asset_categories;
create policy "public read categories for review"
  on public.asset_categories for select to anon using (true);

drop policy if exists "public read maintenance for review" on public.maintenance_records;
create policy "public read maintenance for review"
  on public.maintenance_records for select to anon using (true);

drop policy if exists "public read assignments for review" on public.asset_assignments;
create policy "public read assignments for review"
  on public.asset_assignments for select to anon using (true);

drop policy if exists "public read transfers for review" on public.asset_transfers;
create policy "public read transfers for review"
  on public.asset_transfers for select to anon using (true);

commit;
