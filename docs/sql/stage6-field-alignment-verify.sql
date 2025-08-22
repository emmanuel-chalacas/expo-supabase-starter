-- Omnivia — Stage 6: Field Alignment Verification (Task 8)
-- Context/spec:
--   - Consolidated Task 8: docs/product/projects-data-field-inventory.md §8
--   - Stage 6 migration (columns/constraints/indexes): supabase/migrations/20250820100000_stage6_projects_field_alignment.sql
--   - Stage 6 functions alignment (checksum + merge): supabase/migrations/20250820101500_stage6_functions_alignment.sql
-- Execution notes:
--   - Idempotent; no explicit transaction.
--   - Emits OK markers via final SELECT rows (label/pass).
--   - Requires insert into public.staging_imports to satisfy fn_projects_import_merge() lineage lookup.

-- ========== 1) Schema presence checks ==========
with
cols as (
  select count(*) as matches
  from information_schema.columns
  where table_schema='public' and table_name='projects'
    and column_name in ('address','suburb','state','build_type','fod_id','premises_count','residential','commercial','essential','latitude','longitude','development_type','practical_completion_notified')
),
assert_cols as (
  select 'schema: projects has Stage 6 columns'::text as label,
         (matches = 13) as pass,
         matches,
         null::int as rows,
         null::text as details
  from cols
),
cons as (
  select count(*) as matches
  from pg_constraint
  where conrelid = 'public.projects'::regclass
    and conname in ('projects_premises_count_nonneg_chk','projects_residential_nonneg_chk','projects_commercial_nonneg_chk','projects_essential_nonneg_chk','projects_development_type_enum_chk')
),
assert_cons as (
  select 'schema: projects named CHECK constraints present'::text as label,
         (matches = 5) as pass, matches, null::int as rows, null::text as details
  from cons
),
idx as (
  select count(*) as matches
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relname in ('projects_devtype_idx','projects_build_type_idx')
),
assert_idx as (
 select 'schema: projects indexes present (devtype, build_type)'::text as label,
        (matches = 2) as pass, matches, null::int as rows, null::text as details
 from idx
),
contacts as (
  select count(*) as matches
  from information_schema.columns
  where table_schema='public' and table_name='contacts'
    and column_name in ('company','role')
),
assert_contacts as (
  select 'schema: contacts has company and role columns'::text as label, (matches = 2) as pass, matches, null::int as rows, null::text as details
  from contacts
),

-- ========== 2) Minimal data exercise: build rows JSON, insert staging, call merge ==========
seed as (
  select
    'verify_tenant_stage6'::text as tenant_id,
    substr(replace(gen_random_uuid()::text,'-',''),1,8) as token
),
keys as (
  select
    'VERIF-RES-'||token as k_res,
    'VERIF-COM-'||token as k_com,
    'VERIF-MIX-'||token as k_mix,
    'VERIF-NONE-'||token as k_none
  from seed
),
rows as (
  select jsonb_build_array(
    jsonb_build_object(
      'stage_application', (select k_res from keys),
      'address','12 Alpha St',
      'suburb','Adelaide',
      'state','SA',
      'eFscd', null,
      'build_type', null,
      'delivery_partner','',
      'fod_id', null,
      'premises_count', 10,
      'residential', 10,
      'commercial', 0,
      'essential', 0,
      'developer_class', null,
      'latitude', null,
      'longitude', null,
      'relationship_manager', null,
      'deployment_specialist', null,
      'stage_application_created', null,
      'developer_design_submitted', null,
      'developer_design_accepted', null,
      'issued_to_delivery_partner', null,
      'practical_completion_notified', null,
      'practical_completion_certified', null,
      'delivery_partner_pc_sub', null,
      'in_service', null
    ),
    jsonb_build_object(
      'stage_application', (select k_com from keys),
      'address','34 Beta Ave',
      'suburb','Adelaide',
      'state','SA',
      'eFscd', null,
      'build_type', null,
      'delivery_partner','',
      'fod_id', null,
      'premises_count', 5,
      'residential', 0,
      'commercial', 5,
      'essential', 0,
      'developer_class', null,
      'latitude', null,
      'longitude', null,
      'relationship_manager', null,
      'deployment_specialist', null,
      'stage_application_created', null,
      'developer_design_submitted', null,
      'developer_design_accepted', null,
      'issued_to_delivery_partner', null,
      'practical_completion_notified', null,
      'practical_completion_certified', null,
      'delivery_partner_pc_sub', null,
      'in_service', null
    ),
    jsonb_build_object(
      'stage_application', (select k_mix from keys),
      'address','56 Gamma Rd',
      'suburb','Adelaide',
      'state','SA',
      'eFscd', null,
      'build_type', null,
      'delivery_partner','',
      'fod_id', null,
      'premises_count', 7,
      'residential', 3,
      'commercial', 4,
      'essential', 0,
      'developer_class', null,
      'latitude', null,
      'longitude', null,
      'relationship_manager', null,
      'deployment_specialist', null,
      'stage_application_created', null,
      'developer_design_submitted', null,
      'developer_design_accepted', null,
      'issued_to_delivery_partner', null,
      'practical_completion_notified', '2024-12-15',
      'practical_completion_certified', null,
      'delivery_partner_pc_sub', null,
      'in_service', null
    ),
    jsonb_build_object(
      'stage_application', (select k_none from keys),
      'address','78 Delta Dr',
      'suburb','Adelaide',
      'state','SA',
      'eFscd', null,
      'build_type', null,
      'delivery_partner','',
      'fod_id', null,
      'premises_count', 0,
      'residential', 0,
      'commercial', 0,
      'essential', 0,
      'developer_class', null,
      'latitude', null,
      'longitude', null,
      'relationship_manager', null,
      'deployment_specialist', null,
      'stage_application_created', null,
      'developer_design_submitted', null,
      'developer_design_accepted', null,
      'issued_to_delivery_partner', null,
      'practical_completion_notified', null,
      'practical_completion_certified', null,
      'delivery_partner_pc_sub', null,
      'in_service', null
    )
  ) as rows
),
cs as (
  select public.fn_rows_checksum((select rows from rows)) as checksum
),
staging as (
  insert into public.staging_imports (tenant_id, batch_checksum, raw)
  select (select tenant_id from seed), (select checksum from cs), (select rows from rows)
  on conflict (tenant_id, batch_checksum) do nothing
  returning id
),
merge_call as (
  select (public.fn_projects_import_merge(
    (select tenant_id from seed),
    'verify',
    'stage6-verify',
    (select rows from rows),
    gen_random_uuid()
  )) as result
),
assert_residential_ok as (
  select
    'merge: Residential derivation → "Residential"'::text as label,
    exists (
      select 1 from public.projects p
      where p.tenant_id = (select tenant_id from seed)
        and p.stage_application = (select k_res from keys)
        and p.development_type = 'Residential'
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
assert_commercial_ok as (
  select
    'merge: Commercial derivation → "Commercial"'::text as label,
    exists (
      select 1 from public.projects p
      where p.tenant_id = (select tenant_id from seed)
        and p.stage_application = (select k_com from keys)
        and p.development_type = 'Commercial'
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
assert_mixed_ok as (
  select
    'merge: Mixed Use derivation → "Mixed Use"'::text as label,
    exists (
      select 1 from public.projects p
      where p.tenant_id = (select tenant_id from seed)
        and p.stage_application = (select k_mix from keys)
        and p.development_type = 'Mixed Use'
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
assert_none_ok as (
  select
    'merge: Zero counters → development_type is NULL'::text as label,
    exists (
      select 1 from public.projects p
      where p.tenant_id = (select tenant_id from seed)
        and p.stage_application = (select k_none from keys)
        and p.development_type is null
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
assert_pcn_ok as (
  select
    'merge: practical_completion_notified persisted'::text as label,
    exists (
      select 1 from public.projects p
      where p.tenant_id = (select tenant_id from seed)
        and p.stage_application = (select k_mix from keys)
        and p.practical_completion_notified = '2024-12-15'::date
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
assert_addr_ok as (
  select
    'merge: address/suburb/state persisted'::text as label,
    exists (
      select 1 from public.projects p
      where p.tenant_id = (select tenant_id from seed)
        and p.stage_application = (select k_res from keys)
        and p.address = '12 Alpha St'
        and p.suburb = 'Adelaide'
        and p.state = 'SA'
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
)
select * from assert_cols
union all select * from assert_cons
union all select * from assert_idx
union all select * from assert_contacts
union all select * from assert_residential_ok
union all select * from assert_commercial_ok
union all select * from assert_mixed_ok
union all select * from assert_none_ok
union all select * from assert_pcn_ok
union all select * from assert_addr_ok
order by label;