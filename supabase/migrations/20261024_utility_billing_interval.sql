-- Add billing interval dates to utility bill snapshots.
-- Safe additive migration; do not run automatically against production.
begin;
alter table public.utility_bills
  add column if not exists billing_start_date date,
  add column if not exists billing_end_date date;
update public.utility_bills
set billing_start_date = coalesce(billing_start_date, billing_period),
    billing_end_date = coalesce(billing_end_date, bill_date, billing_period)
where billing_start_date is null or billing_end_date is null;
alter table public.utility_bills
  drop constraint if exists utility_bills_billing_interval_check;
alter table public.utility_bills
  add constraint utility_bills_billing_interval_check
  check (billing_start_date is null or billing_end_date is null or billing_start_date <= billing_end_date);
commit;
