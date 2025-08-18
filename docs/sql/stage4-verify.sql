-- Omnivia — Stage 4 Verification SQL
-- Purpose: Verify Stage 4 DDL, types, and function signatures per design.
-- Usage: node scripts/run-sql.js docs/sql/stage4-verify.sql

with
col_staging_source as (
  select
    'column: staging_imports.source exists with default'::text as label,
    exists (
      select 1
      from information_schema.columns c
      where c.table_schema='public' and c.table_name='staging_imports' and c.column_name='source'
    ) as pass,
    null::int as matches,
    null::int as rows,
    (
      select column_default
      from information_schema.columns
      where table_schema='public' and table_name='staging_imports' and column_name='source'
      limit 1
    )::text as details
),
col_staging_row_count as (
  select
    'column: staging_imports.row_count exists with non-negative check'::text as label,
    (
      exists (
        select 1
        from information_schema.columns c
        where c.table_schema='public' and c.table_name='staging_imports' and c.column_name='row_count' and c.data_type='integer'
      )
      and exists (
        select 1
        from pg_constraint
        where conrelid = 'public.staging_imports'::regclass
          and conname = 'staging_imports_row_count_nonneg_ck'
      )
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
col_staging_correlation as (
  select
    'column: staging_imports.correlation_id exists with default gen_random_uuid()'::text as label,
    (
      exists (
        select 1
        from information_schema.columns c
        where c.table_schema='public' and c.table_name='staging_imports' and c.column_name='correlation_id'
      )
      and coalesce((
        select column_default ilike '%gen_random_uuid%'::text
        from information_schema.columns
        where table_schema='public' and table_name='staging_imports' and column_name='correlation_id'
        limit 1
      ), false)
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
col_staging_batch_checksum as (
  select
    'column: staging_imports.batch_checksum exists and is NOT NULL'::text as label,
    (
      exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='staging_imports' and column_name='batch_checksum'
      )
      and coalesce((
        select is_nullable='NO'
        from information_schema.columns
        where table_schema='public' and table_name='staging_imports' and column_name='batch_checksum'
        limit 1
      ), false)
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
idx_staging_tenant_checksum as (
  select
    'index: staging_imports_tenant_checksum_uniq present (UNIQUE)'::text as label,
    (
      exists (
        select 1 from pg_indexes
        where schemaname='public' and indexname='staging_imports_tenant_checksum_uniq'
          and indexdef ilike '%unique%'
      )
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
idx_staging_imported_at as (
  select
    'index: staging_imports_imported_at_idx present'::text as label,
    exists (
      select 1 from pg_indexes
      where schemaname='public' and indexname='staging_imports_imported_at_idx'
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
idx_projects_tenant_stage as (
  select
    'index: projects_tenant_stage_application_uniq present (UNIQUE)'::text as label,
    (
      exists (
        select 1 from pg_indexes
        where schemaname='public' and indexname='projects_tenant_stage_application_uniq'
          and indexdef ilike '%unique%'
      )
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
cols_projects_added as (
  select
    'columns: projects has deployment_specialist, relationship_manager, rm_preferred_username'::text as label,
    (
      exists (select 1 from information_schema.columns where table_schema='public' and table_name='projects' and column_name='deployment_specialist')
      and exists (select 1 from information_schema.columns where table_schema='public' and table_name='projects' and column_name='relationship_manager')
      and exists (select 1 from information_schema.columns where table_schema='public' and table_name='projects' and column_name='rm_preferred_username')
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
tbl_import_anomalies as (
  select
    'table: import_anomalies exists'::text as label,
    exists (
      select 1 from information_schema.tables
      where table_schema='public' and table_name='import_anomalies'
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
idx_import_anomalies_all as (
  select
    'indexes: import_anomalies indexes present (tenant_batch, staging, created, type)'::text as label,
    (
      exists (select 1 from pg_indexes where schemaname='public' and indexname='import_anomalies_tenant_batch_idx')
      and exists (select 1 from pg_indexes where schemaname='public' and indexname='import_anomalies_staging_idx')
      and exists (select 1 from pg_indexes where schemaname='public' and indexname='import_anomalies_created_idx')
      and exists (select 1 from pg_indexes where schemaname='public' and indexname='import_anomalies_type_idx')
    ) as pass,
    (select count(*) from pg_indexes where schemaname='public' and indexname in (
      'import_anomalies_tenant_batch_idx','import_anomalies_staging_idx','import_anomalies_created_idx','import_anomalies_type_idx'
    )) as matches,
    null::int as rows,
    null::text as details
),
type_merge_result as (
  select
    'type: public.projects_import_merge_result exists'::text as label,
    exists (
      select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace
      where n.nspname='public' and t.typname='projects_import_merge_result'
    ) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
fn_norm_name as (
  select
    'function: fn_normalize_name(text) exists'::text as label,
    (to_regprocedure('public.fn_normalize_name(text)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_norm_devclass as (
  select
    'function: fn_normalize_developer_class(text) exists'::text as label,
    (to_regprocedure('public.fn_normalize_developer_class(text)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_partner_map as (
  select
    'function: fn_partner_org_from_label(text) exists'::text as label,
    (to_regprocedure('public.fn_partner_org_from_label(text)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_find_ds as (
  select
    'function: fn_find_ds_user_id(text) exists'::text as label,
    (to_regprocedure('public.fn_find_ds_user_id(text)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_find_rm as (
  select
    'function: fn_find_rm_user_id(text,text) exists'::text as label,
    (to_regprocedure('public.fn_find_rm_user_id(text,text)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_merge as (
  select
    'function: fn_projects_import_merge(text,text,text,jsonb,uuid) exists'::text as label,
    (to_regprocedure('public.fn_projects_import_merge(text,text,text,jsonb,uuid)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_backfill as (
  select
    'function: fn_projects_membership_backfill() exists'::text as label,
    (to_regprocedure('public.fn_projects_membership_backfill()') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
summary as (
  select * from col_staging_source
  union all select * from col_staging_row_count
  union all select * from col_staging_correlation
  union all select * from col_staging_batch_checksum
  union all select * from idx_staging_tenant_checksum
  union all select * from idx_staging_imported_at
  union all select * from idx_projects_tenant_stage
  union all select * from cols_projects_added
  union all select * from tbl_import_anomalies
  union all select * from idx_import_anomalies_all
  union all select * from type_merge_result
  union all select * from fn_norm_name
  union all select * from fn_norm_devclass
  union all select * from fn_partner_map
  union all select * from fn_find_ds
  union all select * from fn_find_rm
  union all select * from fn_merge
  union all select * from fn_backfill
)
select * from summary
order by label;