-- Omnivia — Stage 5 Smoke Tests (Overall Project Status)
-- Purpose: Exercise deterministic status computation per PRD §8.3 with business-day rules.
-- Cases:
--   1) Late App but not overdue yet → expect 'In Progress'
--   2) PCC waiver (Late App + Issued present; PCC within 20 BD after Issue) → expect 'In Progress'
--   3) Missing Issued on Late App and PCC within disallowed window (<20 BD before EFSCD) → expect 'In Progress - Overdue'
--   4) Missing EFSCD → derived_status IS NULL
-- Usage:
--   node scripts/run-sql.js docs/sql/stage5-status-smoke-tests.sql
--   node scripts/run-sql.js docs/sql/stage5-status-smoke-tests.sql --remote

-- Results sink (temp)
create temporary table if not exists _results (
  label   text not null,
  pass    boolean not null,
  details text null
) on commit drop;

-- Fixed, far-future dates to avoid "today > EFSCD" interference
-- EFSCD anchor for tests
do $$
declare
  v_tenant text := 'TELCO';
  v_ids uuid[];
begin
  -- 1) Late App but not overdue yet → 'In Progress'
  --   - efscd: 2099-12-31
  --   - sac:   2099-11-01 (within <70 BD → Late App)
  --   - dda:   2099-09-01 (>=60 BD before efscd, avoids rule C)
  insert into public.projects (
    tenant_id, stage_application, stage_application_created,
    efscd, developer_design_accepted
  )
  values (
    v_tenant, 'STG-S5-T-0001', '2099-11-01'::timestamptz,
    '2099-12-31'::date, '2099-09-01'::date
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_accepted = excluded.developer_design_accepted;

  -- 2) PCC waiver (Late App + Issued present; PCC within 20 BD after Issue) → 'In Progress'
  --   - efscd: 2099-12-31
  --   - sac:   2099-11-15 (Late App)
  --   - issued_to_delivery_partner: 2099-11-20
  --   - pcc: within 20 BD after issue, e.g., 2099-12-05
  --   - dda: early enough to avoid rule C
  insert into public.projects (
    tenant_id, stage_application, stage_application_created,
    efscd, developer_design_accepted, issued_to_delivery_partner, practical_completion_certified
  )
  values (
    v_tenant, 'STG-S5-T-0002', '2099-11-15'::timestamptz,
    '2099-12-31'::date, '2099-09-01'::date, '2099-11-20'::date, '2099-12-05'::date
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified;

  -- 3) Missing Issued on Late App and PCC within disallowed window → 'In Progress - Overdue'
  --   - efscd: 2099-12-31
  --   - sac:   2099-11-15 (Late App)
  --   - issued_to_delivery_partner: NULL
  --   - pcc: 2099-12-20 (only ~9 BD before efscd) → standard rule applies (since Issued missing) and fails
  --   - dda: early enough to avoid rule C
  insert into public.projects (
    tenant_id, stage_application, stage_application_created,
    efscd, developer_design_accepted, issued_to_delivery_partner, practical_completion_certified
  )
  values (
    v_tenant, 'STG-S5-T-0003', '2099-11-15'::timestamptz,
    '2099-12-31'::date, '2099-09-01'::date, null, '2099-12-20'::date
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified;

  -- 4) Missing EFSCD → derived_status IS NULL
  insert into public.projects (
    tenant_id, stage_application, stage_application_created, efscd
  )
  values (
    v_tenant, 'STG-S5-T-0004', '2099-01-01'::timestamptz, null
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd;

  -- Recompute for these four
  select array_agg(id) into v_ids
  from public.projects
  where tenant_id = v_tenant
    and stage_application in ('STG-S5-T-0001','STG-S5-T-0002','STG-S5-T-0003','STG-S5-T-0004');

  perform public.fn_projects_derived_status_recompute_changed(v_ids);
end$$;

-- Assertions
insert into _results
select 'case 1: Late App, not overdue yet → In Progress',
       exists (
         select 1 from public.projects
         where tenant_id='TELCO' and stage_application='STG-S5-T-0001'
           and derived_status = 'In Progress'
       ),
       null;

insert into _results
select 'case 2: Late App PCC waiver → In Progress',
       exists (
         select 1 from public.projects
         where tenant_id='TELCO' and stage_application='STG-S5-T-0002'
           and derived_status = 'In Progress'
       ),
       null;

insert into _results
select 'case 3: Late App, Issued missing, PCC too late → In Progress - Overdue',
       exists (
         select 1 from public.projects
         where tenant_id='TELCO' and stage_application='STG-S5-T-0003'
           and derived_status = 'In Progress - Overdue'
       ),
       null;

insert into _results
select 'case 4: Missing EFSCD → derived_status is NULL',
       exists (
         select 1 from public.projects
         where tenant_id='TELCO' and stage_application='STG-S5-T-0004'
           and derived_status is null
       ),
       null;

-- Output
select label, case when pass then true else false end as pass, details
from _results
order by label;

-- Cleanup (optional for idempotency without side effects)
delete from public.projects
where tenant_id='TELCO'
  and stage_application in ('STG-S5-T-0001','STG-S5-T-0002','STG-S5-T-0003','STG-S5-T-0004');
-- ===== Stage 6 addendum (2025-08-20): PCN should not affect derived_status =====
-- Context: Assert that practical_completion_notified presence does not alter derived_status
-- per current compute logic [sql.fn_projects_derived_status_compute()](supabase/migrations/20250818062000_stage5_status_compute.sql:59).
-- Usage (examples):
--   node [scripts/run-sql.js](scripts/run-sql.js:1) [docs/sql/stage5-status-smoke-tests.sql](docs/sql/stage5-status-smoke-tests.sql:1)

-- Setup: create two identical rows except practical_completion_notified (PCN)
do $$
declare
  v_tenant text := 'TELCO';
  v_ids uuid[];
begin
  -- No PCN
  insert into public.projects (
    tenant_id, stage_application, stage_application_created,
    efscd, developer_design_accepted, practical_completion_notified
  ) values (
    v_tenant, 'STG-S6-PCN-A', '2099-01-01'::timestamptz,
    '2099-12-31'::date, '2099-09-01'::date, null
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_accepted = excluded.developer_design_accepted,
      practical_completion_notified = excluded.practical_completion_notified;

  -- With PCN
  insert into public.projects (
    tenant_id, stage_application, stage_application_created,
    efscd, developer_design_accepted, practical_completion_notified
  ) values (
    v_tenant, 'STG-S6-PCN-B', '2099-01-01'::timestamptz,
    '2099-12-31'::date, '2099-09-01'::date, '2099-12-01'::date
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_accepted = excluded.developer_design_accepted,
      practical_completion_notified = excluded.practical_completion_notified;

  -- Recompute derived status for both rows
  select array_agg(id) into v_ids
  from public.projects
  where tenant_id = v_tenant
    and stage_application in ('STG-S6-PCN-A','STG-S6-PCN-B');

  perform public.fn_projects_derived_status_recompute_changed(v_ids);
end$$;

-- Assertion: statuses equal between rows with/without PCN
with
a as (
  select derived_status as s from public.projects
  where tenant_id='TELCO' and stage_application='STG-S6-PCN-A'
),
b as (
  select derived_status as s from public.projects
  where tenant_id='TELCO' and stage_application='STG-S6-PCN-B'
)
select
  'Stage 6 addendum: PCN does not affect derived_status' as label,
  ((select s from a) = (select s from b)) as pass,
  case
    when ((select s from a) = (select s from b))
      then 'PCN does not affect derived_status: OK'
    else 'PCN affects derived_status: FAIL'
  end as details;

-- Cleanup (retain idempotency)
delete from public.projects
where tenant_id='TELCO'
  and stage_application in ('STG-S6-PCN-A','STG-S6-PCN-B');