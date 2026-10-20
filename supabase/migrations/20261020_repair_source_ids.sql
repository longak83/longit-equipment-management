-- Longit additive migration: preserve source repair IDs and support inspection records.
-- Safe for existing assets and maintenance records; no existing rows are deleted.
begin;

alter table public.maintenance_records
  add column if not exists source_record_code text;

create unique index if not exists maintenance_records_source_record_code_uidx
  on public.maintenance_records(source_record_code)
  where source_record_code is not null;

alter table public.maintenance_records
  drop constraint if exists maintenance_records_record_type_check;

alter table public.maintenance_records
  add constraint maintenance_records_record_type_check
  check (record_type in ('Sự cố','Sửa chữa','Bảo trì','Kiểm định','Kiểm tra'));

commit;
