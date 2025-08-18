-- Omnivia — Stage 3 Verification SQL
-- Purpose: Verify presence and content of Stage 3 helper/policies and static assertions on Storage predicates.
-- Usage: Run this entire file in Supabase SQL Editor or via: node scripts/run-sql.js docs/sql/stage3-verify.sql

with
fn_present as (
  select
    'function: public.using_rls_for_project(uuid) exists'::text as label,
    (to_regprocedure('public.using_rls_for_project(uuid)') is not null) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
fn_text as (
  select
    'function: helper includes DP hierarchy and role coverage'::text as label,
    (
      -- Ensure function body references parent_partner_org_id (SUB_ORG hierarchy),
      -- and role slugs for dp_admin/dp_pm/dp_cp and telco_ds/telco_rm
      (prosrc ilike '%parent_partner_org_id%')
      and (prosrc ilike '%dp_admin%')
      and (prosrc ilike '%dp_pm%')
      and (prosrc ilike '%dp_cp%')
      and (prosrc ilike '%telco_ds%')
      and (prosrc ilike '%telco_rm%')
    ) as pass,
    null::int as matches,
    null::int as rows,
    ('len=' || length(prosrc))::text as details
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'using_rls_for_project'
  limit 1
),
pol_projects as (
  select
    'policy: projects_select_policy uses helper'::text as label,
    (exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'projects'
        and policyname = 'projects_select_policy'
        and (coalesce(qual,'') ilike '%using_rls_for_project%' or coalesce(with_check,'') ilike '%using_rls_for_project%')
    )) as pass,
    null::int as matches,
    null::int as rows,
    null::text as details
),
pol_storage_present as (
  select
    'storage: attachments_read/insert/delete present'::text as label,
    (select count(*) from pg_policies where schemaname='storage' and tablename='objects' and policyname in ('attachments_read','attachments_insert','attachments_delete')) >= 3 as pass,
    (select count(*) from pg_policies where schemaname='storage' and tablename='objects' and policyname in ('attachments_read','attachments_insert','attachments_delete')) as matches,
    null::int as rows,
    null::text as details
),
pol_storage_bucket_pred as (
  select
    'storage: predicates include bucket_id=''attachments'''::text as label,
    (select count(*) from pg_policies where schemaname='storage' and tablename='objects' and (
      coalesce(qual,'') ilike '%bucket_id = ''attachments''%' or coalesce(with_check,'') ilike '%bucket_id = ''attachments''%'
    )) > 0 as pass,
    (select count(*) from pg_policies where schemaname='storage' and tablename='objects' and (
      coalesce(qual,'') ilike '%bucket_id = ''attachments''%' or coalesce(with_check,'') ilike '%bucket_id = ''attachments''%'
    )) as matches,
    null::int as rows,
    null::text as details
),
pol_storage_uses_helper as (
  select
    'storage: policies reference using_rls_for_project()'::text as label,
    (select count(*) from pg_policies where schemaname='storage' and tablename='objects' and (
      coalesce(qual,'') ilike '%using_rls_for_project%' or coalesce(with_check,'') ilike '%using_rls_for_project%'
    )) > 0 as pass,
    (select count(*) from pg_policies where schemaname='storage' and tablename='objects' and (
      coalesce(qual,'') ilike '%using_rls_for_project%' or coalesce(with_check,'') ilike '%using_rls_for_project%'
    )) as matches,
    null::int as rows,
    null::text as details
),
summary as (
  select * from fn_present
  union all select * from fn_text
  union all select * from pol_projects
  union all select * from pol_storage_present
  union all select * from pol_storage_bucket_pred
  union all select * from pol_storage_uses_helper
)
select * from summary
order by label;
-- Stage 5 — Additional verification: policies on target tables include helper
-- Lists any policies on the specified tables whose predicates do NOT reference using_rls_for_project(
with target(schemaname, tablename) as (
  values
    ('public','projects'),
    ('public','contacts'),
    ('public','engagements'),
    ('public','attachments_meta'),
    ('storage','objects')
),
pol as (
  select p.schemaname, p.tablename, p.policyname,
         btrim(coalesce(p.qual,'') || ' ' || coalesce(p.with_check,'')) as policydef,
         ((coalesce(p.qual,'') || coalesce(p.with_check,'')) ilike '%using_rls_for_project(%') as has_helper
  from pg_policies p
  join target t on t.schemaname = p.schemaname and t.tablename = p.tablename
)
select schemaname, tablename, policyname, policydef, has_helper
from pol
where not has_helper
order by schemaname, tablename, policyname;

-- Stage 5 — Per-table summary: ok = true when all policies for table include helper
with target(schemaname, tablename) as (
  values
    ('public','projects'),
    ('public','contacts'),
    ('public','engagements'),
    ('public','attachments_meta'),
    ('storage','objects')
),
pol as (
  select p.schemaname, p.tablename,
         ((coalesce(p.qual,'') || coalesce(p.with_check,'')) ilike '%using_rls_for_project(%') as has_helper
  from pg_policies p
  join target t on t.schemaname = p.schemaname and t.tablename = p.tablename
),
agg as (
  select schemaname, tablename,
         count(*) as policy_count,
         count(*) filter (where has_helper) as helper_count
  from pol
  group by schemaname, tablename
)
select
  schemaname,
  tablename,
  policy_count,
  helper_count,
  (policy_count = helper_count and policy_count > 0) as ok
from agg
order by schemaname, tablename;