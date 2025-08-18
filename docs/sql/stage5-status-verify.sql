-- Omnivia — Stage 5 Verification SQL (status compute)
-- Purpose: Verify Stage 5 functions, trigger, constraint, index, and include deterministic examples.
-- Usage:
--   node scripts/run-sql.js docs/sql/stage5-status-verify.sql
--   node scripts/run-sql.js docs/sql/stage5-status-verify.sql --remote

with
fn_business_days as (
  select
    'function: fn_business_days_between(date,date) exists'::text as label,
    (to_regprocedure('public.fn_business_days_between(date,date)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_compute as (
  select
    'function: fn_projects_derived_status_compute(uuid) exists'::text as label,
    (to_regprocedure('public.fn_projects_derived_status_compute(uuid)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_recompute_changed as (
  select
    'function: fn_projects_derived_status_recompute_changed(uuid[]) exists'::text as label,
    (to_regprocedure('public.fn_projects_derived_status_recompute_changed(uuid[])') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_recompute_by_staging as (
  select
    'function: fn_projects_derived_status_recompute_by_staging(uuid) exists'::text as label,
    (to_regprocedure('public.fn_projects_derived_status_recompute_by_staging(uuid)') is not null) as pass,
    null::int as matches, null::int as rows, null::text as details
),
fn_rpc_recompute as (
  select
    'function: rpc_projects_status_recompute(text,uuid[]) exists (SECURITY DEFINER)'::text as label,
    (
      to_regprocedure('public.rpc_projects_status_recompute(text,uuid[])') is not null
      and exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'rpc_projects_status_recompute'
          and p.prosecdef = true
      )
    ) as pass,
    null::int as matches, null::int as rows, null::text as details
),
trg_exists as (
  select
    'trigger: tr_projects_derived_status_after_write exists on public.projects (watches required columns)'::text as label,
    exists (
      select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'projects'
        and t.tgname = 'tr_projects_derived_status_after_write'
        and not t.tgisinternal
        and pg_get_triggerdef(t.oid) ilike '%AFTER INSERT OR UPDATE%'
        and pg_get_triggerdef(t.oid) ilike '%efscd%'
        and pg_get_triggerdef(t.oid) ilike '%stage_application_created%'
        and pg_get_triggerdef(t.oid) ilike '%developer_design_submitted%'
        and pg_get_triggerdef(t.oid) ilike '%developer_design_accepted%'
        and pg_get_triggerdef(t.oid) ilike '%issued_to_delivery_partner%'
        and pg_get_triggerdef(t.oid) ilike '%practical_completion_certified%'
        and pg_get_triggerdef(t.oid) ilike '%delivery_partner_pc_sub%'
        and pg_get_triggerdef(t.oid) ilike '%in_service%'
    ) as pass,
    null::int as matches, null::int as rows,
    (select pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='projects' and t.tgname='tr_projects_derived_status_after_write' limit 1) as details
),
idx_status as (
  select
    'index: projects(derived_status) exists'::text as label,
    exists (
      select 1 from pg_indexes
      where schemaname = 'public'
        and tablename = 'projects'
        and indexdef ilike '%(derived_status)%'
    ) as pass,
    null::int as matches, null::int as rows, null::text as details
),
ck_constraint as (
  select
    'constraint: projects_derived_status_ck exists'::text as label,
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.projects'::regclass
        and conname = 'projects_derived_status_ck'
    ) as pass,
    null::int as matches, null::int as rows, null::text as details
),

-- Deterministic inline examples (insert two projects, recompute, assert results)
setup as (
  select 1
),
ins_examples as (
  with p1 as (
    -- Example 1: Complete (in_service on/before efscd)
    insert into public.projects (tenant_id, stage_application, stage_application_created, efscd, in_service)
    values ('TELCO', 'STG-S5-V-0001', '2099-01-01'::timestamptz, '2099-12-31'::date, '2099-12-01'::date)
    on conflict (tenant_id, stage_application) do nothing
    returning id
  ),
  p2 as (
    -- Example 2: Complete Overdue Late App (in_service after efscd and Late App true)
    -- sac within <70 business days of efscd to trigger Late App (approximate)
    insert into public.projects (tenant_id, stage_application, stage_application_created, efscd, in_service)
    values ('TELCO', 'STG-S5-V-0002', '2099-12-01'::timestamptz, '2099-12-31'::date, '2100-01-31'::date)
    on conflict (tenant_id, stage_application) do nothing
    returning id
  )
  select array_agg(id) as ids from (
    select id from p1
    union all
    select id from p2
  ) s
),
recompute as (
  select coalesce(public.fn_projects_derived_status_recompute_changed((select ids from ins_examples)), 0) as updated
),
assert_complete as (
  select
    'example: compute "Complete" for STG-S5-V-0001'::text as label,
    exists (
      select 1 from public.projects
      where tenant_id='TELCO' and stage_application='STG-S5-V-0001'
        and derived_status = 'Complete'
    ) as pass,
    null::int as matches, null::int as rows, null::text as details
),
assert_complete_overdue_late as (
  select
    'example: compute "Complete Overdue Late App" for STG-S5-V-0002'::text as label,
    exists (
      select 1 from public.projects
      where tenant_id='TELCO' and stage_application='STG-S5-V-0002'
        and derived_status = 'Complete Overdue Late App'
    ) as pass,
    null::int as matches, null::int as rows, null::text as details
),
summary as (
  select * from fn_business_days
  union all select * from fn_compute
  union all select * from fn_recompute_changed
  union all select * from fn_recompute_by_staging
  union all select * from fn_rpc_recompute
  union all select * from trg_exists
  union all select * from idx_status
  union all select * from ck_constraint
  union all select * from assert_complete
  union all select * from assert_complete_overdue_late
)
select * from summary
order by label;

-- Cleanup of verification examples (safe if rows were pre-existing)
delete from public.projects where tenant_id='TELCO' and stage_application in ('STG-S5-V-0001','STG-S5-V-0002');