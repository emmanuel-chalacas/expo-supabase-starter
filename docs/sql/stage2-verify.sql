-- Omnivia — Stage 2 Verification SQL
-- Purpose: Produce a consolidated verification report for Stage 2 assets as a single result set.
-- Usage: Run this entire file in Supabase SQL Editor (no text selection) to get one result grid.
-- References: Bootstrap [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1), Apply [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1)

with
tables as (
  select 'table: public.projects'::text as label, (to_regclass('public.projects') is not null) as pass, null::int as matches, null::int as rows, null::text as details
  union all select 'table: public.project_membership', (to_regclass('public.project_membership') is not null), null, null, null
  union all select 'table: public.contacts', (to_regclass('public.contacts') is not null), null, null, null
  union all select 'table: public.engagements', (to_regclass('public.engagements') is not null), null, null, null
  union all select 'table: public.attachments_meta', (to_regclass('public.attachments_meta') is not null), null, null, null
  union all select 'table: public.partner_org', (to_regclass('public.partner_org') is not null), null, null, null
  union all select 'table: public.partner_normalization', (to_regclass('public.partner_normalization') is not null), null, null, null
  union all select 'table: public.ds_directory', (to_regclass('public.ds_directory') is not null), null, null, null
  union all select 'table: public.rm_directory', (to_regclass('public.rm_directory') is not null), null, null, null
  union all select 'table: public.user_profiles', (to_regclass('public.user_profiles') is not null), null, null, null
  union all select 'table: public.user_roles', (to_regclass('public.user_roles') is not null), null, null, null
  union all select 'table: public.features', (to_regclass('public.features') is not null), null, null, null
  union all select 'table: public.staging_imports', (to_regclass('public.staging_imports') is not null), null, null, null
),
idx_stage as (
  select count(*) as c
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'projects'
    and indexdef ilike '% on public.projects % (stage_application%'
),
idx_partner as (
  select count(*) as c
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'projects'
    and indexdef ilike '% on public.projects % (partner_org_id%'
),
idx_status as (
  select count(*) as c
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'projects'
    and indexdef ilike '% on public.projects % (derived_status%'
),
idx_tenant as (
  select count(*) as c
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'projects'
    and indexdef ilike '% on public.projects % (tenant_id%'
),
indexes as (
  select 'index: projects(stage_application, ...)'::text as label, ((select c from idx_stage) > 0) as pass, (select c from idx_stage) as matches, null::int as rows, null::text as details
  union all select 'index: projects(partner_org_id)', ((select c from idx_partner) > 0), (select c from idx_partner), null, null
  union all select 'index: projects(derived_status)', ((select c from idx_status) > 0), (select c from idx_status), null, null
  union all select 'index: projects(tenant_id)', ((select c from idx_tenant) > 0), (select c from idx_tenant), null, null
),
bucket as (
  select 'storage: bucket attachments exists'::text as label,
         exists (select 1 from storage.buckets where name = 'attachments') as pass,
         null::int as matches, null::int as rows, null::text as details
),
pol_present as (
  select 'storage: attachments_* policies present'::text as label,
         (c >= 3) as pass,
         c as matches,
         null::int as rows,
         null::text as details
  from (
    select count(*) as c
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in ('attachments_read','attachments_insert','attachments_delete')
  ) s
),
pol_pred as (
  select 'storage: policy predicates include bucket_id=''attachments'''::text as label,
         (c >= 1) as pass,
         c as matches,
         null::int as rows,
         null::text as details
  from (
    select count(*) as c
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and (
        coalesce(qual, '') ilike '%bucket_id = ''attachments''%'
        or coalesce(with_check, '') ilike '%bucket_id = ''attachments''%'
      )
  ) s
),
seed_po as (
  select 'seed: partner_org count >= 1'::text as label,
         (c >= 1) as pass,
         null::int as matches,
         c as rows,
         null::text as details
  from (select count(*) as c from public.partner_org) s
),
seed_po_labels as (
  select 'seed: canonical partner_org labels present (sample)'::text as label,
         (c >= 1) as pass,
         null::int as matches,
         c as rows,
         'samples: ' || coalesce((select string_agg(name, ', ' order by name)
                                  from (select name from public.partner_org order by name limit 3) l), '') as details
  from (
    select count(*) as c
    from public.partner_org
    where lower(trim(name)) in ('fulton hogan','ventia','ugl','enerven','servicestream')
  ) s
),
seed_pn as (
  select 'seed: partner_normalization mapped to partner_org'::text as label,
         (c > 0) as pass,
         null::int as matches,
         c as rows,
         null::text as details
  from (
    select count(*) as c
    from public.partner_normalization pn
    join public.partner_org po on po.id = pn.partner_org_id
  ) s
),
seed_feats as (
  select 'seed: features ENABLE_* present'::text as label,
         ((ep > 0) and (ea > 0) and (eo > 0)) as pass,
         null::int as matches,
         (ep + ea + eo) as rows,
         null::text as details
  from (
    select
      (select count(*) from public.features where name = 'ENABLE_PROJECTS') as ep,
      (select count(*) from public.features where name = 'ENABLE_ATTACHMENTS_UPLOAD') as ea,
      (select count(*) from public.features where name = 'ENABLE_OKTA_AUTH') as eo
  ) s
),
seed_telco as (
  select 'seed: TELCO has 3 feature rows'::text as label,
         (c = 3) as pass,
         null::int as matches,
         c as rows,
         null::text as details
  from (
    select count(*) as c
    from public.features
    where tenant_id = 'TELCO' and name in ('ENABLE_PROJECTS','ENABLE_ATTACHMENTS_UPLOAD','ENABLE_OKTA_AUTH')
  ) s
),
info_counts as (
  select 'info: partner_org rows'::text as label, null::boolean as pass, null::int as matches, count(*) as rows, null::text as details from public.partner_org
  union all
  select 'info: partner_normalization rows', null, null, count(*), null from public.partner_normalization
  union all
  select 'info: features rows', null, null, count(*), null from public.features
)
select * from tables
union all select * from indexes
union all select * from bucket
union all select * from pol_present
union all select * from pol_pred
union all select * from seed_po
union all select * from seed_po_labels
union all select * from seed_pn
union all select * from seed_feats
union all select * from seed_telco
union all select * from info_counts
order by label;