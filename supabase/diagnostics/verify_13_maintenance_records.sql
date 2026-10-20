-- READ-ONLY verification for the 13 historical maintenance records.
-- Run in Supabase SQL Editor. This script does not INSERT/UPDATE/DELETE.
-- Expected source codes come from the workbook's 03_SU_CO_SUA_CHUA sheet.

with expected(source_record_code, asset_code, record_type, reported_at, completed_at) as (
  values
    ('SC-0001','PRN-KTAT-003','Sửa chữa',date '2026-08-04',date '2026-08-05'),
    ('SC-0002','PRN-KTAT-004','Sửa chữa',date '2026-08-04',date '2026-08-05'),
    ('SC-0003','CPY-KHVT-001','Sửa chữa',date '2026-08-17',date '2026-08-18'),
    ('SC-0004','CPY-KHVT-001','Sửa chữa',date '2026-08-17',date '2026-08-18'),
    ('SC-0005','CPY-KHVT-001','Sửa chữa',date '2026-08-17',date '2026-08-18'),
    ('SC-0006','PRN-TCHC-004','Sửa chữa',date '2026-08-24',date '2026-08-25'),
    ('SC-0007','CPY-KD-001','Sửa chữa',date '2026-08-27',date '2026-08-28'),
    ('SC-0008','PRN-TCHC-001','Sửa chữa',date '2026-09-07',date '2026-09-08'),
    ('SC-0009','PRN-BKS-001','Kiểm tra',date '2026-10-07',date '2026-10-14'),
    ('SC-0010','PRN-GD-001','Sửa chữa',date '2026-10-13',date '2026-10-14'),
    ('SC-0011','PRN-TCKT-002','Sửa chữa',date '2026-10-13',date '2026-10-14'),
    ('SC-0012','PRN-TTGS-001','Sửa chữa',date '2026-10-13',date '2026-10-14'),
    ('SC-0013','CPY-TCHC-001','Sửa chữa',date '2026-10-13',date '2026-10-14')
),
actual as (
  select
    mr.source_record_code,
    a.asset_code,
    mr.record_type,
    mr.reported_at,
    mr.completed_at,
    mr.status,
    mr.cost,
    count(*) over (partition by mr.source_record_code) as occurrences
  from public.maintenance_records mr
  left join public.assets a on a.id = mr.asset_id
  where mr.source_record_code between 'SC-0001' and 'SC-0013'
)
select
  e.source_record_code,
  e.asset_code as expected_asset_code,
  a.asset_code as actual_asset_code,
  e.record_type as expected_type,
  a.record_type as actual_type,
  e.reported_at as expected_reported_at,
  a.reported_at as actual_reported_at,
  e.completed_at as expected_completed_at,
  a.completed_at as actual_completed_at,
  a.status,
  a.cost,
  coalesce(a.occurrences, 0) as occurrences,
  case
    when a.source_record_code is null then 'MISSING'
    when a.occurrences > 1 then 'DUPLICATE'
    when a.asset_code is distinct from e.asset_code
      or a.record_type is distinct from e.record_type
      or a.reported_at is distinct from e.reported_at
      or a.completed_at is distinct from e.completed_at then 'MISMATCH'
    else 'OK'
  end as verification
from expected e
left join actual a on a.source_record_code = e.source_record_code
order by e.source_record_code;

-- Expected: 13 rows and verification = OK for each row.
-- cost = 0 means the workbook had no cost value; it does not confirm a free repair.
