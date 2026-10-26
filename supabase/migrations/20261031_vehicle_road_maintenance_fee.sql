-- Longit: road maintenance fee tracking for vehicles.
-- Additive migration only; existing vehicle details and costs are preserved.
begin;
alter table public.vehicle_details
  add column if not exists road_maintenance_expiry_date date,
  add column if not exists road_maintenance_reminder_days integer not null default 30
    check (road_maintenance_reminder_days between 0 and 3650),
  add column if not exists road_maintenance_estimated_cost numeric(14,2)
    check (road_maintenance_estimated_cost is null or road_maintenance_estimated_cost >= 0),
  add column if not exists road_maintenance_actual_cost numeric(14,2)
    check (road_maintenance_actual_cost is null or road_maintenance_actual_cost >= 0);
create index if not exists vehicle_details_road_maintenance_expiry_idx
  on public.vehicle_details(road_maintenance_expiry_date);
commit;
