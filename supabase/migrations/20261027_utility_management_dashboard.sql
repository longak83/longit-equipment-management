-- Utility management dashboard: company totals and explanatory report notes.
-- Additive only. Review and run in Supabase SQL Editor before using dashboard persistence.
begin;

create table if not exists public.utility_company_totals (
  period_key text primary key,
  electric_total_kwh numeric(16,3),
  water_total_m3 numeric(16,3),
  source_notes text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint utility_company_totals_period_key_check
    check (period_key ~ '^\d{4}-Q[1-4]$'),
  constraint utility_company_totals_electric_nonnegative
    check (electric_total_kwh is null or electric_total_kwh >= 0),
  constraint utility_company_totals_water_nonnegative
    check (water_total_m3 is null or water_total_m3 >= 0)
);

create table if not exists public.utility_report_notes (
  id uuid primary key default gen_random_uuid(),
  period_key text not null,
  tenant_id uuid references public.utility_tenants(id) on delete set null,
  note_type text not null default 'other'
    check (note_type in ('incident','repair','operation','adjustment','other')),
  resource text not null default 'both'
    check (resource in ('electricity','water','both')),
  content text not null check (length(trim(content)) > 0),
  status text not null default 'monitoring'
    check (status in ('monitoring','in_progress','resolved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint utility_report_notes_period_key_check
    check (period_key ~ '^\d{4}(-Q[1-4]|-\d{2})?$')
);

create index if not exists utility_report_notes_period_idx
  on public.utility_report_notes(period_key, created_at desc);
create index if not exists utility_report_notes_tenant_idx
  on public.utility_report_notes(tenant_id);

alter table public.utility_company_totals enable row level security;
alter table public.utility_report_notes enable row level security;

drop policy if exists "authenticated read utility company totals" on public.utility_company_totals;
create policy "authenticated read utility company totals"
  on public.utility_company_totals for select to authenticated using (true);
drop policy if exists "editors insert utility company totals" on public.utility_company_totals;
create policy "editors insert utility company totals"
  on public.utility_company_totals for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update utility company totals" on public.utility_company_totals;
create policy "editors update utility company totals"
  on public.utility_company_totals for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete utility company totals" on public.utility_company_totals;
create policy "admins delete utility company totals"
  on public.utility_company_totals for delete to authenticated using (public.current_user_role() = 'admin');

drop policy if exists "authenticated read utility report notes" on public.utility_report_notes;
create policy "authenticated read utility report notes"
  on public.utility_report_notes for select to authenticated using (true);
drop policy if exists "editors insert utility report notes" on public.utility_report_notes;
create policy "editors insert utility report notes"
  on public.utility_report_notes for insert to authenticated with check (public.has_write_access());
drop policy if exists "editors update utility report notes" on public.utility_report_notes;
create policy "editors update utility report notes"
  on public.utility_report_notes for update to authenticated using (public.has_write_access()) with check (public.has_write_access());
drop policy if exists "admins delete utility report notes" on public.utility_report_notes;
create policy "admins delete utility report notes"
  on public.utility_report_notes for delete to authenticated using (public.current_user_role() = 'admin');

grant select, insert, update, delete on public.utility_company_totals, public.utility_report_notes to authenticated;

commit;
