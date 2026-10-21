-- Longit: estimated and actual vehicle inspection/insurance costs.
-- Additive migration only; existing vehicle records remain valid.
begin;
alter table public.vehicle_details
  add column if not exists registration_estimated_cost numeric(14,2) check (registration_estimated_cost is null or registration_estimated_cost >= 0),
  add column if not exists registration_actual_cost numeric(14,2) check (registration_actual_cost is null or registration_actual_cost >= 0),
  add column if not exists insurance_estimated_cost numeric(14,2) check (insurance_estimated_cost is null or insurance_estimated_cost >= 0),
  add column if not exists insurance_actual_cost numeric(14,2) check (insurance_actual_cost is null or insurance_actual_cost >= 0);
commit;
