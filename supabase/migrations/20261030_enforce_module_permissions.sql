-- Enforce per-module permissions on business data tables.
-- Run only after the account-management and vehicle-permission migrations,
-- plus the license, outsourced-services and utility migrations, are installed.
begin;

-- Assets & equipment (non-vehicle assets).
drop policy if exists "authenticated read assets" on public.assets;
drop policy if exists "insert assets by module permission" on public.assets;
drop policy if exists "update assets by module permission" on public.assets;
drop policy if exists "editors insert assets" on public.assets;
drop policy if exists "editors update assets" on public.assets;
create policy "read assets by module permission"
on public.assets for select to authenticated
using (
  ((category = 'Ô tô' and public.has_module_permission('vehicles','view'))
   or (category <> 'Ô tô' and public.has_module_permission('assets','view')))
  and (deleted_at is null or public.current_user_role() = 'admin')
);
create policy "insert assets by module permission"
on public.assets for insert to authenticated
with check (
  (category = 'Ô tô' and public.has_module_permission('vehicles','create'))
  or (category <> 'Ô tô' and public.has_module_permission('assets','create'))
);
create policy "update assets by module permission"
on public.assets for update to authenticated
using (
  (category = 'Ô tô' and public.has_module_permission('vehicles','update'))
  or (category <> 'Ô tô' and public.has_module_permission('assets','update'))
)
with check (
  ((category = 'Ô tô' and public.has_module_permission('vehicles','update'))
   or (category <> 'Ô tô' and public.has_module_permission('assets','update')))
  and (deleted_at is null
       or (category = 'Ô tô' and public.has_module_permission('vehicles','delete'))
       or (category <> 'Ô tô' and public.has_module_permission('assets','delete'))
       or public.current_user_role() = 'admin')
);
drop policy if exists "no hard delete assets" on public.assets;
drop policy if exists "admins delete assets" on public.assets;
create policy "no hard delete assets"
on public.assets for delete to authenticated using (false);

-- Maintenance: vehicle records use vehicle permissions; other records use maintenance permissions.
drop policy if exists "authenticated read maintenance" on public.maintenance_records;
drop policy if exists "insert maintenance by module permission" on public.maintenance_records;
drop policy if exists "update maintenance by module permission" on public.maintenance_records;
drop policy if exists "editors insert maintenance" on public.maintenance_records;
drop policy if exists "editors update maintenance" on public.maintenance_records;
create policy "read maintenance by module permission"
on public.maintenance_records for select to authenticated
using (
  (deleted_at is null or public.current_user_role() = 'admin')
  and (
    public.current_user_role() = 'admin'
    or exists (
      select 1 from public.assets a
      where a.id = maintenance_records.asset_id
        and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','view'))
          or (a.category <> 'Ô tô' and public.has_module_permission('maintenance','view')))
    )
  )
);
create policy "insert maintenance by module permission"
on public.maintenance_records for insert to authenticated
with check (
  exists (
    select 1 from public.assets a
    where a.id = maintenance_records.asset_id
      and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','create'))
        or (a.category <> 'Ô tô' and public.has_module_permission('maintenance','create')))
  )
);
create policy "update maintenance by module permission"
on public.maintenance_records for update to authenticated
using (
  exists (
    select 1 from public.assets a
    where a.id = maintenance_records.asset_id
      and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','update'))
        or (a.category <> 'Ô tô' and public.has_module_permission('maintenance','update')))
  )
)
with check (
  exists (
    select 1 from public.assets a
    where a.id = maintenance_records.asset_id
      and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','update')
            and (maintenance_records.deleted_at is null or public.has_module_permission('vehicles','delete')))
        or (a.category <> 'Ô tô' and public.has_module_permission('maintenance','update')
            and (maintenance_records.deleted_at is null or public.has_module_permission('maintenance','delete'))))
  )
);
drop policy if exists "no hard delete maintenance records" on public.maintenance_records;
drop policy if exists "admins delete maintenance" on public.maintenance_records;
create policy "no hard delete maintenance records"
on public.maintenance_records for delete to authenticated using (false);

-- Assignment and transfer history follows the corresponding asset module.
drop policy if exists "authenticated read assignments" on public.asset_assignments;
drop policy if exists "editors manage assignments" on public.asset_assignments;
create policy "read assignments by module permission"
on public.asset_assignments for select to authenticated
using (exists (
  select 1 from public.assets a where a.id = asset_assignments.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','view'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','view')))
));
create policy "manage assignments by module permission"
on public.asset_assignments for all to authenticated
using (exists (
  select 1 from public.assets a where a.id = asset_assignments.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','update'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','update')))
))
with check (exists (
  select 1 from public.assets a where a.id = asset_assignments.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','update'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','update')))
));
drop policy if exists "authenticated read transfers" on public.asset_transfers;
drop policy if exists "editors manage transfers" on public.asset_transfers;
create policy "read transfers by module permission"
on public.asset_transfers for select to authenticated
using (exists (
  select 1 from public.assets a where a.id = asset_transfers.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','view'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','view')))
));
create policy "manage transfers by module permission"
on public.asset_transfers for all to authenticated
using (exists (
  select 1 from public.assets a where a.id = asset_transfers.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','update'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','update')))
))
with check (exists (
  select 1 from public.assets a where a.id = asset_transfers.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','update'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','update')))
));

drop policy if exists "authenticated read attribute values" on public.asset_attribute_values;
drop policy if exists "editors manage attribute values" on public.asset_attribute_values;
create policy "read attribute values by module permission"
on public.asset_attribute_values for select to authenticated
using (exists (
  select 1 from public.assets a where a.id = asset_attribute_values.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','view'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','view')))
));
create policy "manage attribute values by module permission"
on public.asset_attribute_values for all to authenticated
using (exists (
  select 1 from public.assets a where a.id = asset_attribute_values.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','update'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','update')))
))
with check (exists (
  select 1 from public.assets a where a.id = asset_attribute_values.asset_id
    and ((a.category = 'Ô tô' and public.has_module_permission('vehicles','update'))
      or (a.category <> 'Ô tô' and public.has_module_permission('assets','update')))
));

-- License / renewal module.
drop policy if exists "authenticated read license records" on public.license_records;
drop policy if exists "editors insert license records" on public.license_records;
drop policy if exists "editors update license records" on public.license_records;
drop policy if exists "admins delete license records" on public.license_records;
create policy "read license records by module permission" on public.license_records
for select to authenticated using (public.has_module_permission('licenses','view'));
create policy "insert license records by module permission" on public.license_records
for insert to authenticated with check (public.has_module_permission('licenses','create'));
create policy "update license records by module permission" on public.license_records
for update to authenticated using (public.has_module_permission('licenses','update'))
with check (public.has_module_permission('licenses','update'));
create policy "delete license records by module permission" on public.license_records
for delete to authenticated using (public.has_module_permission('licenses','delete'));

drop policy if exists "authenticated read license renewal history" on public.license_renewal_history;
drop policy if exists "editors insert license renewal history" on public.license_renewal_history;
drop policy if exists "editors update license renewal history" on public.license_renewal_history;
drop policy if exists "admins delete license renewal history" on public.license_renewal_history;
create policy "read license renewal history by module permission" on public.license_renewal_history
for select to authenticated using (public.has_module_permission('licenses','view'));
create policy "insert license renewal history by module permission" on public.license_renewal_history
for insert to authenticated with check (public.has_module_permission('licenses','create'));
create policy "update license renewal history by module permission" on public.license_renewal_history
for update to authenticated using (public.has_module_permission('licenses','update'))
with check (public.has_module_permission('licenses','update'));
create policy "delete license renewal history by module permission" on public.license_renewal_history
for delete to authenticated using (public.has_module_permission('licenses','delete'));

-- Outsourced services / renewals.
drop policy if exists "authenticated read outsourced services" on public.outsourced_services;
drop policy if exists "editors insert outsourced services" on public.outsourced_services;
drop policy if exists "editors update outsourced services" on public.outsourced_services;
drop policy if exists "admins delete outsourced services" on public.outsourced_services;
create policy "read outsourced services by module permission" on public.outsourced_services
for select to authenticated using (public.has_module_permission('services','view'));
create policy "insert outsourced services by module permission" on public.outsourced_services
for insert to authenticated with check (public.has_module_permission('services','create'));
create policy "update outsourced services by module permission" on public.outsourced_services
for update to authenticated using (public.has_module_permission('services','update'))
with check (public.has_module_permission('services','update'));
create policy "delete outsourced services by module permission" on public.outsourced_services
for delete to authenticated using (public.has_module_permission('services','delete'));

drop policy if exists "authenticated read outsourced service renewals" on public.outsourced_service_renewals;
drop policy if exists "editors insert outsourced service renewals" on public.outsourced_service_renewals;
drop policy if exists "editors update outsourced service renewals" on public.outsourced_service_renewals;
drop policy if exists "admins delete outsourced service renewals" on public.outsourced_service_renewals;
create policy "read outsourced service renewals by module permission" on public.outsourced_service_renewals
for select to authenticated using (public.has_module_permission('services','view'));
create policy "insert outsourced service renewals by module permission" on public.outsourced_service_renewals
for insert to authenticated with check (public.has_module_permission('services','create'));
create policy "update outsourced service renewals by module permission" on public.outsourced_service_renewals
for update to authenticated using (public.has_module_permission('services','update'))
with check (public.has_module_permission('services','update'));
create policy "delete outsourced service renewals by module permission" on public.outsourced_service_renewals
for delete to authenticated using (public.has_module_permission('services','delete'));

-- Utility meters, bills, company totals and explanatory notes.
-- The reading / bill-line tables are also covered so direct API calls cannot bypass UI permissions.
drop policy if exists "authenticated read utility settings" on public.utility_settings;
drop policy if exists "editors update utility settings" on public.utility_settings;
drop policy if exists "editors insert utility settings" on public.utility_settings;
create policy "read utility settings by module permission" on public.utility_settings
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility settings by module permission" on public.utility_settings
for insert to authenticated with check (public.has_module_permission('utilities','update'));
create policy "update utility settings by module permission" on public.utility_settings
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));

drop policy if exists "authenticated read utility tenants" on public.utility_tenants;
drop policy if exists "editors insert utility tenants" on public.utility_tenants;
drop policy if exists "editors update utility tenants" on public.utility_tenants;
drop policy if exists "admins delete utility tenants" on public.utility_tenants;
create policy "read utility tenants by module permission" on public.utility_tenants
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility tenants by module permission" on public.utility_tenants
for insert to authenticated with check (public.has_module_permission('utilities','create'));
create policy "update utility tenants by module permission" on public.utility_tenants
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));
create policy "delete utility tenants by module permission" on public.utility_tenants
for delete to authenticated using (public.has_module_permission('utilities','delete'));

drop policy if exists "authenticated read utility bills" on public.utility_bills;
drop policy if exists "editors insert utility bills" on public.utility_bills;
drop policy if exists "editors update utility bills" on public.utility_bills;
drop policy if exists "admins delete utility bills" on public.utility_bills;
create policy "read utility bills by module permission" on public.utility_bills
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility bills by module permission" on public.utility_bills
for insert to authenticated with check (public.has_module_permission('utilities','create'));
create policy "update utility bills by module permission" on public.utility_bills
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));
create policy "delete utility bills by module permission" on public.utility_bills
for delete to authenticated using (public.has_module_permission('utilities','delete'));

drop policy if exists "authenticated read utility rooms" on public.utility_rooms;
drop policy if exists "editors insert utility rooms" on public.utility_rooms;
drop policy if exists "editors update utility rooms" on public.utility_rooms;
drop policy if exists "admins delete utility rooms" on public.utility_rooms;
create policy "read utility rooms by module permission" on public.utility_rooms
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility rooms by module permission" on public.utility_rooms
for insert to authenticated with check (public.has_module_permission('utilities','create'));
create policy "update utility rooms by module permission" on public.utility_rooms
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));
create policy "delete utility rooms by module permission" on public.utility_rooms
for delete to authenticated using (public.has_module_permission('utilities','delete'));

drop policy if exists "authenticated read utility meters" on public.utility_meters;
drop policy if exists "editors insert utility meters" on public.utility_meters;
drop policy if exists "editors update utility meters" on public.utility_meters;
drop policy if exists "admins delete utility meters" on public.utility_meters;
create policy "read utility meters by module permission" on public.utility_meters
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility meters by module permission" on public.utility_meters
for insert to authenticated with check (public.has_module_permission('utilities','create'));
create policy "update utility meters by module permission" on public.utility_meters
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));
create policy "delete utility meters by module permission" on public.utility_meters
for delete to authenticated using (public.has_module_permission('utilities','delete'));

drop policy if exists "authenticated read utility readings" on public.utility_meter_readings;
drop policy if exists "editors insert utility readings" on public.utility_meter_readings;
drop policy if exists "editors update utility readings" on public.utility_meter_readings;
drop policy if exists "admins delete utility readings" on public.utility_meter_readings;
create policy "read utility readings by module permission" on public.utility_meter_readings
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility readings by module permission" on public.utility_meter_readings
for insert to authenticated with check (public.has_module_permission('utilities','create'));
create policy "update utility readings by module permission" on public.utility_meter_readings
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));
create policy "delete utility readings by module permission" on public.utility_meter_readings
for delete to authenticated using (public.has_module_permission('utilities','delete'));

drop policy if exists "authenticated read utility bill lines" on public.utility_bill_meter_lines;
drop policy if exists "editors insert utility bill lines" on public.utility_bill_meter_lines;
drop policy if exists "editors update utility bill lines" on public.utility_bill_meter_lines;
drop policy if exists "admins delete utility bill lines" on public.utility_bill_meter_lines;
create policy "read utility bill lines by module permission" on public.utility_bill_meter_lines
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility bill lines by module permission" on public.utility_bill_meter_lines
for insert to authenticated with check (public.has_module_permission('utilities','create'));
create policy "update utility bill lines by module permission" on public.utility_bill_meter_lines
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));
create policy "delete utility bill lines by module permission" on public.utility_bill_meter_lines
for delete to authenticated using (public.has_module_permission('utilities','delete'));

drop policy if exists "authenticated read utility company totals" on public.utility_company_totals;
drop policy if exists "editors insert utility company totals" on public.utility_company_totals;
drop policy if exists "editors update utility company totals" on public.utility_company_totals;
drop policy if exists "admins delete utility company totals" on public.utility_company_totals;
create policy "read utility company totals by module permission" on public.utility_company_totals
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility company totals by module permission" on public.utility_company_totals
for insert to authenticated with check (public.has_module_permission('utilities','create'));
create policy "update utility company totals by module permission" on public.utility_company_totals
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));
create policy "delete utility company totals by module permission" on public.utility_company_totals
for delete to authenticated using (public.has_module_permission('utilities','delete'));

drop policy if exists "authenticated read utility report notes" on public.utility_report_notes;
drop policy if exists "editors insert utility report notes" on public.utility_report_notes;
drop policy if exists "editors update utility report notes" on public.utility_report_notes;
drop policy if exists "editors delete utility report notes" on public.utility_report_notes;
create policy "read utility report notes by module permission" on public.utility_report_notes
for select to authenticated using (public.has_module_permission('utilities','view'));
create policy "insert utility report notes by module permission" on public.utility_report_notes
for insert to authenticated with check (public.has_module_permission('utilities','create'));
create policy "update utility report notes by module permission" on public.utility_report_notes
for update to authenticated using (public.has_module_permission('utilities','update'))
with check (public.has_module_permission('utilities','update'));
create policy "delete utility report notes by module permission" on public.utility_report_notes
for delete to authenticated using (public.has_module_permission('utilities','delete'));

-- Utility settings / reports are protected through the same utilities permission key.
commit;
