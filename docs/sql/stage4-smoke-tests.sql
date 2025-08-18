-- Omnivia — Stage 4 Smoke Tests (Import merge + membership materialization)
-- Purpose: Exercise merge path, anomaly recording, idempotency, and membership reconciliation.
-- Usage: node scripts/run-sql.js docs/sql/stage4-smoke-tests.sql

-- Results sink (temp)
create temporary table if not exists _results (
  label   text not null,
  pass    boolean not null,
  details text null
) on commit drop;

-- Deterministic UUIDs for synthetic identities
--   DS user: 00000000-0000-0000-0000-00000000d001
--   RM user: 00000000-0000-0000-0000-00000000r001
-- Test correlation ids:
--   corr_1: 11111111-1111-1111-1111-111111111111
--   corr_2: 22222222-2222-2222-2222-222222222222
-- Stage Applications:
--   STG-TEST-0001 (valid mapping)
--   STG-TEST-0002 (blank DP + unknown DS/RM first run; updated on second run)

-- === Fixtures: canonical org, normalization, directory users ===

-- Ensure partner org exists
insert into public.partner_org (name)
select 'Test DP'
where not exists (select 1 from public.partner_org where lower(trim(name)) = 'test dp');

-- Resolve org id
create temporary table _vars as
select
  (select id from public.partner_org where lower(trim(name)) = 'test dp' limit 1) as test_org_id;

-- Ensure normalization mapping exists for label 'Test DP Label'
insert into public.partner_normalization (source_label, partner_org_id)
select 'Test DP Label', v.test_org_id
from _vars v
where not exists (
  select 1 from public.partner_normalization pn
  where lower(trim(pn.source_label)) = 'test dp label'
);

-- Insert synthetic auth.users for DS and RM
insert into auth.users (id, email, aud, role, raw_user_meta_data, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-00000000d001', 'ci+ds_import_a@example.com', 'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000r001', 'ci+rm_import_a@example.com', 'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb)
on conflict (id) do nothing;

-- DS directory: preferred_username exact match
insert into public.ds_directory (display_name, preferred_username, user_id, status)
values ('DS Import A', 'DS_IMPORT_A', '00000000-0000-0000-0000-00000000d001', 'active')
on conflict do nothing;

-- RM directory: display_name exact normalized match (also provide preferred_username)
insert into public.rm_directory (display_name, preferred_username, user_id, status)
values ('RM Import A', 'RM_A', '00000000-0000-0000-0000-00000000r001', 'active')
on conflict do nothing;

-- === Build rows JSONB ===
-- Row 1: fully valid (mapped DP, known DS preferred_username, known RM display_name)
-- Row 2: DP blank (Unassigned), unknown DS/RM (should log anomalies), numbers blank coerced to 0

with rows as (
  select jsonb_agg(x) as j
  from (
    values
      (jsonb_build_object(
         'stage_application','STG-TEST-0001',
         'address','1 Main St',
         'eFscd','2025-10-01',
         'development_type','Residential',
         'build_type','SDU',
         'delivery_partner','Test DP Label',
         'premises_count','10',
         'residential','10',
         'commercial','',
         'essential','',
         'developer_class','Class 2',
         'latitude','-34.9',
         'longitude','138.6',
         'relationship_manager','RM Import A',
         'deployment_specialist','DS_IMPORT_A',
         'stage_application_created','2025-04-01'
       )),
      (jsonb_build_object(
         'stage_application','STG-TEST-0002',
         'address','2 Park Ave',
         'eFscd','2025-11-15',
         'development_type','Commercial',
         'build_type','MDU',
         'delivery_partner','',                -- blank = Unassigned
         'premises_count','100',
         'residential','',
         'commercial','100',
         'essential','',
         'developer_class','Class 3',
         'latitude','',
         'longitude','',
         'relationship_manager','Unknown RM',
         'deployment_specialist','UNKNOWN_DS_1',
         'stage_application_created','2025-05-01'
       ))
  ) t(x)
)
select 1;

-- Materialize rows JSONB into a temp var
do $$
declare v_rows jsonb;
begin
  select j into v_rows from (with rows as (
    select jsonb_agg(x) as j
    from (
      values
        (jsonb_build_object(
           'stage_application','STG-TEST-0001',
           'address','1 Main St',
           'eFscd','2025-10-01',
           'development_type','Residential',
           'build_type','SDU',
           'delivery_partner','Test DP Label',
           'premises_count','10',
           'residential','10',
           'commercial','',
           'essential','',
           'developer_class','Class 2',
           'latitude','-34.9',
           'longitude','138.6',
           'relationship_manager','RM Import A',
           'deployment_specialist','DS_IMPORT_A',
           'stage_application_created','2025-04-01'
         )),
        (jsonb_build_object(
           'stage_application','STG-TEST-0002',
           'address','2 Park Ave',
           'eFscd','2025-11-15',
           'development_type','Commercial',
           'build_type','MDU',
           'delivery_partner','',
           'premises_count','100',
           'residential','',
           'commercial','100',
           'essential','',
           'developer_class','Class 3',
           'latitude','',
           'longitude','',
           'relationship_manager','Unknown RM',
           'deployment_specialist','UNKNOWN_DS_1',
           'stage_application_created','2025-05-01'
         ))
    ) t(x)
  ) select j) q;

  -- Insert staging_imports with matching correlation id; provide checksum/batch_checksum placeholders
  insert into public.staging_imports(batch_id, tenant_id, raw, checksum, batch_checksum, validation, correlation_id)
  values (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1',
    'TELCO',
    v_rows,
    public.fn_rows_checksum(v_rows),
    public.fn_rows_checksum(v_rows),
    jsonb_build_object('note','stage4-smoke'),
    '11111111-1111-1111-1111-111111111111'
  )
  on conflict do nothing;
end$$;

-- === Run merge (first pass) ===
with m as (
  select *
  from public.fn_projects_import_merge(
    'TELCO',
    'projects-import',
    'BATCH-TEST-1',
    (select v_rows from (select jsonb_agg(x) as v_rows from (values
      (jsonb_build_object(
         'stage_application','STG-TEST-0001',
         'address','1 Main St',
         'eFscd','2025-10-01',
         'development_type','Residential',
         'build_type','SDU',
         'delivery_partner','Test DP Label',
         'premises_count','10',
         'residential','10',
         'commercial','',
         'essential','',
         'developer_class','Class 2',
         'latitude','-34.9',
         'longitude','138.6',
         'relationship_manager','RM Import A',
         'deployment_specialist','DS_IMPORT_A',
         'stage_application_created','2025-04-01'
       )),
      (jsonb_build_object(
         'stage_application','STG-TEST-0002',
         'address','2 Park Ave',
         'eFscd','2025-11-15',
         'development_type','Commercial',
         'build_type','MDU',
         'delivery_partner','',
         'premises_count','100',
         'residential','',
         'commercial','100',
         'essential','',
         'developer_class','Class 3',
         'latitude','',
         'longitude','',
         'relationship_manager','Unknown RM',
         'deployment_specialist','UNKNOWN_DS_1',
         'stage_application_created','2025-05-01'
       ))
    ) t(x)) q),
    '11111111-1111-1111-1111-111111111111'
  )
)
select 1;

-- Capture metrics into temp for comparisons
create temporary table _m1 as
select *
from public.fn_projects_import_merge(
  'TELCO','projects-import','BATCH-TEST-1',
  (select v_rows from (select jsonb_agg(x) as v_rows from (values
    (jsonb_build_object(
       'stage_application','STG-TEST-0001',
       'address','1 Main St',
       'eFscd','2025-10-01',
       'development_type','Residential',
       'build_type','SDU',
       'delivery_partner','Test DP Label',
       'premises_count','10',
       'residential','10',
       'commercial','',
       'essential','',
       'developer_class','Class 2',
       'latitude','-34.9',
       'longitude','138.6',
       'relationship_manager','RM Import A',
       'deployment_specialist','DS_IMPORT_A',
       'stage_application_created','2025-04-01'
     )),
    (jsonb_build_object(
       'stage_application','STG-TEST-0002',
       'address','2 Park Ave',
       'eFscd','2025-11-15',
       'development_type','Commercial',
       'build_type','MDU',
       'delivery_partner','',
       'premises_count','100',
       'residential','',
       'commercial','100',
       'essential','',
       'developer_class','Class 3',
       'latitude','',
       'longitude','',
       'relationship_manager','Unknown RM',
       'deployment_specialist','UNKNOWN_DS_1',
       'stage_application_created','2025-05-01'
     ))
  ) t(x)) q),
  '11111111-1111-1111-1111-111111111111'
);

insert into _results
select 'metrics (first run): inserted=2 updated=0 org=1 user=2 anomalies=2',
       (inserted_projects = 2 and updated_projects = 0 and org_memberships_upserted >= 1 and user_memberships_upserted >= 2 and anomalies_count >= 2),
       (('ins='||inserted_projects)||',upd='||updated_projects||',org='||org_memberships_upserted||',user='||user_memberships_upserted||',anom='||anomalies_count)
from _m1;

-- Verify memberships and anomalies for first project (STG-TEST-0001)
with
pid as (
  select id from public.projects where tenant_id='TELCO' and stage_application='STG-TEST-0001' limit 1
),
org_ok as (
  select exists (
    select 1
    from public.project_membership m
    join pid on true
    join _vars v on true
    where m.project_id = pid.id
      and m.member_partner_org_id = v.test_org_id
  ) as ok
),
user_ds_ok as (
  select exists (
    select 1
    from public.project_membership m
    join pid on true
    where m.project_id = pid.id
      and m.member_user_id = '00000000-0000-0000-0000-00000000d001'::uuid
  ) as ok
),
user_rm_ok as (
  select exists (
    select 1
    from public.project_membership m
    join pid on true
    where m.project_id = pid.id
      and m.member_user_id = '00000000-0000-0000-0000-00000000r001'::uuid
  ) as ok
)
insert into _results
select 'memberships: p1 has ORG + DS + RM',
       (select ok from org_ok) and (select ok from user_ds_ok) and (select ok from user_rm_ok),
       null;

-- Anomalies present for second row (UNKNOWN_DS, UNKNOWN_RM); DP blank should not raise anomaly
insert into _results
select 'anomalies: unknown DS and RM recorded for row 2',
       (
         select count(*) filter (where anomaly_type in ('UNKNOWN_DS','UNKNOWN_RM'))
         from public.import_anomalies
         where batch_id = 'BATCH-TEST-1'
           and project_key in ('STG-TEST-0002')
       ) >= 2,
       null;

-- === Idempotency: re-run with same correlation_id short-circuits to memoized metrics ===
create temporary table _m1b as
select *
from public.fn_projects_import_merge(
  'TELCO','projects-import','BATCH-TEST-1',
  (select v_rows from _m1 limit 1) -- dummy source; function ignores and returns memoized metrics
  ,'11111111-1111-1111-1111-111111111111'
);

insert into _results
select 'idempotency: same correlation returns same metrics',
       (a.inserted_projects = b.inserted_projects and a.updated_projects = b.updated_projects
        and a.org_memberships_upserted = b.org_memberships_upserted
        and a.user_memberships_upserted = b.user_memberships_upserted
        and a.anomalies_count = b.anomalies_count),
       null
from _m1 a cross join _m1b b;

-- === Change case: fix second row mappings and assert reconciliation ===

-- Insert new staging row with changed 2nd record and new correlation id
do $$
declare v_rows2 jsonb;
begin
  v_rows2 := jsonb_build_array(
    jsonb_build_object(
       'stage_application','STG-TEST-0001',
       'address','1 Main St',
       'eFscd','2025-10-01',
       'development_type','Residential',
       'build_type','SDU',
       'delivery_partner','Test DP Label',
       'premises_count','10',
       'residential','10',
       'commercial','',
       'essential','',
       'developer_class','Class 2',
       'latitude','-34.9',
       'longitude','138.6',
       'relationship_manager','RM Import A',
       'deployment_specialist','DS_IMPORT_A',
       'stage_application_created','2025-04-01'
    ),
    jsonb_build_object(
       'stage_application','STG-TEST-0002',
       'address','2 Park Ave',
       'eFscd','2025-11-15',
       'development_type','Commercial',
       'build_type','MDU',
       'delivery_partner','Test DP Label',             -- now mapped
       'premises_count','100',
       'residential','0',
       'commercial','100',
       'essential','0',
       'developer_class','Class 3',
       'latitude','',
       'longitude','',
       'relationship_manager','RM Import A',           -- now known
       'deployment_specialist','DS_IMPORT_A',          -- now known
       'stage_application_created','2025-05-01'
    )
  );

  insert into public.staging_imports(batch_id, tenant_id, raw, checksum, batch_checksum, validation, correlation_id)
  values (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2',
    'TELCO',
    v_rows2,
    'smoke-checksum-2',
    'smoke-checksum-2',
    jsonb_build_object('note','stage4-smoke-2'),
    '22222222-2222-2222-2222-222222222222'
  )
  on conflict do nothing;
end$$;

create temporary table _m2 as
select *
from public.fn_projects_import_merge(
  'TELCO','projects-import','BATCH-TEST-2',
  (select raw from public.staging_imports where correlation_id = '22222222-2222-2222-2222-222222222222' order by imported_at desc limit 1),
  '22222222-2222-2222-2222-222222222222'
);

insert into _results
select 'metrics (second run): updated>=1 org>=1 user>=2 anomalies>=0',
       (updated_projects >= 1 and org_memberships_upserted >= 1 and user_memberships_upserted >= 2 and anomalies_count >= 0),
       (('upd='||updated_projects)||',org='||org_memberships_upserted||',user='||user_memberships_upserted||',anom='||anomalies_count)
from _m2;

-- Verify second project now has ORG + DS + RM memberships
with
pid2 as (
  select id from public.projects where tenant_id='TELCO' and stage_application='STG-TEST-0002' limit 1
),
org2_ok as (
  select exists (
    select 1
    from public.project_membership m
    join pid2 on true
    join _vars v on true
    where m.project_id = pid2.id
      and m.member_partner_org_id = v.test_org_id
  ) as ok
),
user2_count as (
  select count(*) as c
  from public.project_membership m
  join pid2 on true
  where m.project_id = pid2.id
    and m.member_user_id in ('00000000-0000-0000-0000-00000000d001'::uuid,'00000000-0000-0000-0000-00000000r001'::uuid)
)
insert into _results
select 'memberships: p2 has ORG + DS + RM after reconciliation',
       (select ok from org2_ok) and (select c from user2_count) = 2,
       null;

-- === Cleanup test artifacts ===
-- Remove anomalies for our batches
delete from public.import_anomalies where batch_id in ('BATCH-TEST-1','BATCH-TEST-2');

-- Remove memberships and projects for our test stage_applications
delete from public.project_membership
where project_id in (select id from public.projects where stage_application in ('STG-TEST-0001','STG-TEST-0002'));

delete from public.projects where stage_application in ('STG-TEST-0001','STG-TEST-0002');

-- Remove staging rows
delete from public.staging_imports where correlation_id in ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');

-- Remove directory entries
delete from public.ds_directory where preferred_username = 'DS_IMPORT_A';
delete from public.rm_directory where display_name = 'RM Import A';

-- Remove synthetic users
delete from auth.users where id in ('00000000-0000-0000-0000-00000000d001','00000000-0000-0000-0000-00000000r001');

-- Optionally clean up normalization and org (safe when no FKs remain)
delete from public.partner_normalization where lower(trim(source_label)) = 'test dp label';
delete from public.partner_org where lower(trim(name)) = 'test dp';

-- === Output ===
select label, case when pass then true else false end as pass, details
from _results
order by label;