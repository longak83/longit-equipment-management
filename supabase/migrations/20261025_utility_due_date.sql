-- Store the payment deadline as part of the bill snapshot so reprints remain stable.
begin;
alter table public.utility_bills
  add column if not exists due_date date;
update public.utility_bills
set due_date = (date_trunc('month', coalesce(billing_end_date, bill_date, billing_period)::timestamp) + interval '1 month' + interval '14 days')::date
where due_date is null;
commit;
