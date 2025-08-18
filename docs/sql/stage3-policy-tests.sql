-- Omnivia — Stage 3 Policy Tests (RLS + Storage metadata)
-- Purpose: CI-grade assertions for Stage 3 — membership-scoped visibility and UGC write scopes.
-- Strategy:
--   - Uses deterministic synthetic identities via request.jwt.claims (sub=uuid) and the "authenticated" role.
--   - Seeds minimal test data (partner orgs, projects, memberships, user mirrors/roles) and cleans up at the end.
--   - Validates:
--       * Projects visibility by role and membership (positive + negative)
--       * UGC write scopes: engagements and attachments_meta (positive + negative)
--       * Update/Delete permissions align with creator-bound policies
--       * Projects update admin-only stub enforcement
--       * Policies are enforced via public.using_rls_for_project()
-- Usage:
--   - Remote: node scripts/run-sql.js docs/sql/stage3-policy-tests.sql
--   - Requires: Supabase project with Stage 1/2 migrations applied and Storage schema available.
--   - Notes: Runs as "postgres" but switches session role to "authenticated" for policy enforcement.

-- Results sink (temp table lives only for this session)
create temporary table if not exists _results (
  label   text not null,
  pass    boolean not null,
  details text null
) on commit drop;

-- Deterministic UUIDs for synthetic identities (hex-only)
-- Telco
--   vendor_admin: 00000000-0000-0000-0000-0000000000a1
--   telco_admin : 00000000-0000-0000-0000-0000000000a2
--   telco_pm    : 00000000-0000-0000-0000-0000000000a3
--   telco_ds    : 00000000-0000-0000-0000-0000000000a4
--   telco_rm    : 00000000-0000-0000-0000-0000000000a5
-- Delivery Partner (FH = Fulton Hogan)
--   dp_admin    : 00000000-0000-0000-0000-0000000000b1
--   dp_pm       : 00000000-0000-0000-0000-0000000000b2
--   dp_cp       : 00000000-0000-0000-0000-0000000000b3

-- Canonical/org fixtures (ensure FH + sub org present; rely on Stage 2 seeds where possible)
-- Ensure Fulton Hogan exists
insert into public.partner_org (name)
select 'Fulton Hogan'
where not exists (select 1 from public.partner_org where lower(trim(name)) = 'fulton hogan');

-- Prepare FH id and SUB_ORG id
create temporary table _vars as
select
  (select id from public.partner_org where lower(trim(name)) = 'fulton hogan' limit 1) as fh_org_id,
  null::uuid as fh_sub_id;

-- Ensure a subcontractor under FH exists
insert into public.partner_org (name, parent_partner_org_id)
select 'FH Sub 1', v.fh_org_id from _vars v
where not exists (select 1 from public.partner_org where lower(trim(name)) = 'fh sub 1');

update _vars v
set fh_sub_id = (select id from public.partner_org where lower(trim(name)) = 'fh sub 1' limit 1);

-- Create two projects
-- p1: assigned to FH org (ORG membership) and FH Sub 1 (SUB_ORG membership) and DS/RM user membership
-- p2: assigned to FH org only (no SUB_ORG membership)
do $$
begin
  if not exists (select 1 from public.projects where id = '00000000-0000-0000-0000-00000000c001'::uuid) then
    insert into public.projects (id, tenant_id, stage_application, stage_application_created, partner_org_id, developer_class)
    select '00000000-0000-0000-0000-00000000c001'::uuid, 'TELCO', 'CI-STAGE3-1', now(), v.fh_org_id, 'Class 2'
    from _vars v;
  end if;

  if not exists (select 1 from public.projects where id = '00000000-0000-0000-0000-00000000c002'::uuid) then
    insert into public.projects (id, tenant_id, stage_application, stage_application_created, partner_org_id, developer_class)
    select '00000000-0000-0000-0000-00000000c002'::uuid, 'TELCO', 'CI-STAGE3-2', now(), v.fh_org_id, 'Class 3/4'
    from _vars v;
  end if;
end
$$;

-- Insert synthetic auth.users (minimal columns; defaults fill the rest)
insert into auth.users (id, email, aud, role, raw_user_meta_data, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-0000000000a1', 'ci+vendor_admin@example.com', 'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000a2', 'ci+telco_admin@example.com',  'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000a3', 'ci+telco_pm@example.com',     'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000a4', 'ci+telco_ds@example.com',     'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000a5', 'ci+telco_rm@example.com',     'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000b1', 'ci+dp_admin@example.com',     'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000b2', 'ci+dp_pm@example.com',        'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000b3', 'ci+dp_cp@example.com',        'authenticated', 'authenticated', '{}'::jsonb, '{}'::jsonb)
on conflict (id) do nothing;

-- Mirror profiles (tenant/org context)
insert into public.user_profiles (user_id, okta_sub, okta_user_id, tenant_id, partner_org_id, sub_partner_org_id)
select '00000000-0000-0000-0000-0000000000a1'::uuid, 'sub-va', 'va', 'TELCO', null, null
union all select '00000000-0000-0000-0000-0000000000a2'::uuid, 'sub-ta', 'ta', 'TELCO', null, null
union all select '00000000-0000-0000-0000-0000000000a3'::uuid, 'sub-tp', 'tp', 'TELCO', null, null
union all select '00000000-0000-0000-0000-0000000000a4'::uuid, 'sub-td', 'td', 'TELCO', null, null
union all select '00000000-0000-0000-0000-0000000000a5'::uuid, 'sub-tr', 'tr', 'TELCO', null, null
union all
select '00000000-0000-0000-0000-0000000000b1'::uuid, 'sub-da', 'da', 'DP_FH', v.fh_org_id, null from _vars v
union all
select '00000000-0000-0000-0000-0000000000b2'::uuid, 'sub-dp', 'dp', 'DP_FH', v.fh_org_id, null from _vars v
union all
select '00000000-0000-0000-0000-0000000000b3'::uuid, 'sub-dc', 'dc', 'DP_FH', v.fh_org_id, v.fh_sub_id from _vars v
on conflict (user_id) do nothing;

-- Roles
insert into public.user_roles (user_id, role)
values
  ('00000000-0000-0000-0000-0000000000a1', 'vendor_admin'),
  ('00000000-0000-0000-0000-0000000000a2', 'telco_admin'),
  ('00000000-0000-0000-0000-0000000000a3', 'telco_pm'),
  ('00000000-0000-0000-0000-0000000000a4', 'telco_ds'),
  ('00000000-0000-0000-0000-0000000000a5', 'telco_rm'),
  ('00000000-0000-0000-0000-0000000000b1', 'dp_admin'),
  ('00000000-0000-0000-0000-0000000000b2', 'dp_pm'),
  ('00000000-0000-0000-0000-0000000000b3', 'dp_cp')
on conflict (user_id, role) do nothing;

-- Membership materialization
-- p1: ORG (FH), SUB_ORG (FH Sub 1), DS, RM
-- p2: ORG (FH only)
insert into public.project_membership (project_id, member_partner_org_id)
select '00000000-0000-0000-0000-00000000c001'::uuid, v.fh_org_id from _vars v
on conflict do nothing;

insert into public.project_membership (project_id, member_sub_partner_org_id)
select '00000000-0000-0000-0000-00000000c001'::uuid, v.fh_sub_id from _vars v
on conflict do nothing;

insert into public.project_membership (project_id, member_partner_org_id)
select '00000000-0000-0000-0000-00000000c002'::uuid, v.fh_org_id from _vars v
on conflict do nothing;

-- DS and RM assignments for p1
insert into public.project_membership (project_id, member_user_id)
values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000a4'),
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000a5')
on conflict do nothing;

-- ========== Tests ==========
-- Note: Policies are "to authenticated", so ensure role=authenticated and set sub each time.

-- 1) Visibility — positive cases
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
insert into _results
select 'projects select: telco_admin sees TELCO tenant project p1' as label,
       (select exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c001')) as pass,
       null::text;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
insert into _results
select 'projects select: telco_pm sees TELCO tenant project p1',
       (select exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c001')),
       null;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
insert into _results
select 'projects select: telco_ds sees assigned project p1',
       (select exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c001')),
       null;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a5","role":"authenticated"}', true);
insert into _results
select 'projects select: telco_rm sees assigned project p1',
       (select exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c001')),
       null;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
insert into _results
select 'projects select: dp_admin sees project via ORG or SUB_ORG membership p1',
       (select exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c001')),
       null;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
insert into _results
select 'projects select: dp_pm sees project via ORG or SUB_ORG membership p1',
       (select exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c001')),
       null;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
insert into _results
select 'projects select: dp_cp sees project via SUB_ORG membership p1',
       (select exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c001')),
       null;

-- 2) Visibility — negative cases
-- dp_cp must NOT see p2 (ORG only, no SUB_ORG)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
insert into _results
select 'projects select (negative): dp_cp does NOT see p2 (no SUB_ORG)',
       not exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c002') as pass,
       null;

-- telco_ds must NOT see p2 (not assigned)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
insert into _results
select 'projects select (negative): telco_ds does NOT see p2 (not assigned)',
       not exists(select 1 from public.projects where id='00000000-0000-0000-0000-00000000c002') as pass,
       null;

-- 3) UGC — engagements insert allowed for dp_cp on p1 (SUB_ORG membership)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    insert into public.engagements (project_id, created_by, kind, body)
    values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000b3', 'note', 'CI-Stage3 ok dp_cp on p1');
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('engagements insert: dp_cp allowed on p1 (SUB_ORG)', true, null);
  else
    insert into _results(label, pass, details) values ('engagements insert: dp_cp allowed on p1 (SUB_ORG)', false, 'insert blocked unexpectedly');
  end if;
end $$;

-- 4) UGC — engagements insert denied for dp_cp on p2 (ORG only)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    insert into public.engagements (project_id, created_by, kind, body)
    values ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-0000000000b3', 'note', 'CI-Stage3 should fail dp_cp on p2');
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('engagements insert (negative): dp_cp denied on p2 (no SUB_ORG)', false, 'unexpected success');
  else
    insert into _results(label, pass, details) values ('engagements insert (negative): dp_cp denied on p2 (no SUB_ORG)', true, null);
  end if;
end $$;

-- 5) Attachments metadata — insert allowed for telco_ds on p1 (assigned USER)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    insert into public.attachments_meta (project_id, created_by, bucket, object_name, content_type, size_bytes)
    values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000a4', 'attachments', 'ci-stage3/ok-a4-1.pdf', 'application/pdf', 12345);
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('attachments_meta insert: telco_ds allowed on p1', true, null);
  else
    insert into _results(label, pass, details) values ('attachments_meta insert: telco_ds allowed on p1', false, 'insert blocked unexpectedly');
  end if;
end $$;

-- 6) Attachments metadata — insert denied for unrelated dp_cp on p2 (no SUB_ORG membership)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    insert into public.attachments_meta (project_id, created_by, bucket, object_name, content_type, size_bytes)
    values ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-0000000000b3', 'attachments', 'ci-stage3/deny-b3-1.png', 'image/png', 22222);
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('attachments_meta insert (negative): dp_cp denied on p2', false, 'unexpected success');
  else
    insert into _results(label, pass, details) values ('attachments_meta insert (negative): dp_cp denied on p2', true, null);
  end if;
end $$;

-- 7) Engagements update — own row allowed (dp_cp on p1)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
do $$
declare
  v_id uuid;
  ok boolean := true;
begin
  select id into v_id
  from public.engagements
  where created_by = '00000000-0000-0000-0000-0000000000b3'::uuid
    and body = 'CI-Stage3 ok dp_cp on p1'
  order by created_at desc
  limit 1;

  if v_id is null then
    ok := false;
  else
    begin
      update public.engagements
      set body = 'CI-Stage3 updated by dp_cp'
      where id = v_id;
    exception when others then
      ok := false;
    end;
  end if;

  if ok then
    insert into _results(label, pass, details) values ('engagements update: dp_cp can update own row on p1', true, null);
  else
    insert into _results(label, pass, details) values ('engagements update: dp_cp can update own row on p1', false, 'update blocked unexpectedly or row not found');
  end if;
end $$;

-- 8) Engagements update — denied when not owner (dp_cp tries to update telco_ds row)
-- First, create a DS-owned row
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
insert into public.engagements (project_id, created_by, kind, body)
values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000a4', 'note', 'CI-Stage3 ds-own for update');

-- Attempt update as dp_cp
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
do $$
declare
  v_id uuid;
  ok boolean := true;
begin
  select id into v_id
  from public.engagements
  where created_by = '00000000-0000-0000-0000-0000000000a4'::uuid
    and body = 'CI-Stage3 ds-own for update'
  order by created_at desc
  limit 1;

  begin
    update public.engagements
    set body = 'CI-Stage3 dp_cp should NOT update ds row'
    where id = v_id;
  exception when others then
    ok := false;
  end;

  if ok then
    -- If update succeeded, it's a failure for the test
    insert into _results(label, pass, details) values ('engagements update (negative): dp_cp cannot update ds-owned row', false, 'unexpected success');
  else
    insert into _results(label, pass, details) values ('engagements update (negative): dp_cp cannot update ds-owned row', true, null);
  end if;
end $$;

-- 9) Engagements delete — own row allowed (telco_ds)
-- Create a DS-owned row for delete
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
insert into public.engagements (project_id, created_by, kind, body)
values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000a4', 'note', 'CI-Stage3 ds-own for delete');

-- Delete it as telco_ds
do $$
declare
  v_id uuid;
  ok boolean := true;
begin
  select id into v_id
  from public.engagements
  where created_by = '00000000-0000-0000-0000-0000000000a4'::uuid
    and body = 'CI-Stage3 ds-own for delete'
  order by created_at desc
  limit 1;

  begin
    delete from public.engagements where id = v_id;
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('engagements delete: telco_ds can delete own row', true, null);
  else
    insert into _results(label, pass, details) values ('engagements delete: telco_ds can delete own row', false, 'delete blocked unexpectedly');
  end if;
end $$;

-- 10) Engagements delete — denied for dp_pm on ds-owned row
-- Create a DS-owned target
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
insert into public.engagements (project_id, created_by, kind, body)
values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000a4', 'note', 'CI-Stage3 del-target deny dp_pm');

-- Attempt delete as dp_pm
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$
declare
  v_id uuid;
  ok boolean := true;
begin
  select id into v_id
  from public.engagements
  where body = 'CI-Stage3 del-target deny dp_pm'
  order by created_at desc
  limit 1;

  begin
    delete from public.engagements where id = v_id;
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('engagements delete (negative): dp_pm cannot delete ds-owned row', false, 'unexpected success');
  else
    insert into _results(label, pass, details) values ('engagements delete (negative): dp_pm cannot delete ds-owned row', true, null);
  end if;
end $$;

-- 11) Attachments_meta update — own row allowed (telco_ds)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    update public.attachments_meta
    set size_bytes = 12346
    where bucket = 'attachments' and object_name = 'ci-stage3/ok-a4-1.pdf' and created_by = '00000000-0000-0000-0000-0000000000a4'::uuid;
    if not found then
      ok := false;
    end if;
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('attachments_meta update: telco_ds can update own row', true, null);
  else
    insert into _results(label, pass, details) values ('attachments_meta update: telco_ds can update own row', false, 'update blocked unexpectedly or row not found');
  end if;
end $$;

-- 12) Attachments_meta update — denied for dp_cp on ds-owned row
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    update public.attachments_meta
    set size_bytes = 77777
    where bucket = 'attachments' and object_name = 'ci-stage3/ok-a4-1.pdf';
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('attachments_meta update (negative): dp_cp cannot update ds-owned row', false, 'unexpected success');
  else
    insert into _results(label, pass, details) values ('attachments_meta update (negative): dp_cp cannot update ds-owned row', true, null);
  end if;
end $$;

-- 13) Attachments_meta delete — own row allowed (telco_ds)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    delete from public.attachments_meta
    where bucket = 'attachments' and object_name = 'ci-stage3/ok-a4-1.pdf' and created_by = '00000000-0000-0000-0000-0000000000a4'::uuid;
    if not found then
      ok := false;
    end if;
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('attachments_meta delete: telco_ds can delete own row', true, null);
  else
    insert into _results(label, pass, details) values ('attachments_meta delete: telco_ds can delete own row', false, 'delete blocked unexpectedly or row not found');
  end if;
end $$;

-- 14) Projects update — allowed for telco_admin (admin-only stub)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    update public.projects
    set developer_class = 'Class 2'
    where id = '00000000-0000-0000-0000-00000000c002'::uuid;
    if not found then ok := false; end if;
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('projects update: telco_admin allowed by admin-only stub', true, null);
  else
    insert into _results(label, pass, details) values ('projects update: telco_admin allowed by admin-only stub', false, 'update blocked unexpectedly or row not found');
  end if;
end $$;

-- 15) Projects update — denied for dp_cp
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
do $$
declare ok boolean := true;
begin
  begin
    update public.projects
    set developer_class = 'Class 1'
    where id = '00000000-0000-0000-0000-00000000c002'::uuid;
  exception when others then
    ok := false;
  end;

  if ok then
    insert into _results(label, pass, details) values ('projects update (negative): dp_cp denied', false, 'unexpected success');
  else
    insert into _results(label, pass, details) values ('projects update (negative): dp_cp denied', true, null);
  end if;
end $$;

-- 16) Contacts select — enforcement via using_rls_for_project()
-- Seed contacts on p1 and p2 as telco_admin (allowed by tenant visibility)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
do $$
begin
  if not exists (
    select 1 from public.contacts
    where project_id = '00000000-0000-0000-0000-00000000c001'::uuid
      and name = 'CI-Stage3 contact p1'
  ) then
    insert into public.contacts (project_id, created_by, name, phone, email)
    values ('00000000-0000-0000-0000-00000000c001'::uuid,
            '00000000-0000-0000-0000-0000000000a2'::uuid,
            'CI-Stage3 contact p1', '000', 'ci-stage3-p1@example.com');
  end if;

  if not exists (
    select 1 from public.contacts
    where project_id = '00000000-0000-0000-0000-00000000c002'::uuid
      and name = 'CI-Stage3 contact p2'
  ) then
    insert into public.contacts (project_id, created_by, name, phone, email)
    values ('00000000-0000-0000-0000-00000000c002'::uuid,
            '00000000-0000-0000-0000-0000000000a2'::uuid,
            'CI-Stage3 contact p2', '000', 'ci-stage3-p2@example.com');
  end if;
end
$$;

-- Read checks as dp_cp (SUB_ORG membership on p1 only)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
insert into _results
select 'contacts select: dp_cp sees contact on p1 via SUB_ORG' as label,
       (select exists(select 1 from public.contacts where name = 'CI-Stage3 contact p1')) as pass,
       null::text;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
insert into _results
select 'contacts select (negative): dp_cp does NOT see contact on p2 (no SUB_ORG)' as label,
       (select not exists(select 1 from public.contacts where name = 'CI-Stage3 contact p2')) as pass,
       null::text;

-- Local cleanup for contacts created above (as creator telco_admin)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
do $$
begin
  delete from public.contacts where name in ('CI-Stage3 contact p1','CI-Stage3 contact p2');
end
$$;
-- Cleanup test artifacts (keep partner_org 'Fulton Hogan'; remove SUB_ORG, projects, UGC, mirrors)
-- Remove UGC created by this test
delete from public.engagements
where body like 'CI-Stage3%';

delete from public.attachments_meta
where object_name like 'ci-stage3/%';

-- Remove memberships and projects
delete from public.project_membership where project_id in ('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-00000000c002');
delete from public.projects where id in ('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-00000000c002');

-- Remove SUB_ORG created by this test (safe if it exists and has no remaining FKs)
delete from public.partner_org
where lower(trim(name)) = 'fh sub 1';

-- Remove synthetic mirrors and users
delete from public.user_roles
where user_id in (
  '00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a2',
  '00000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-0000000000a4',
  '00000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-0000000000b1',
  '00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000b3'
);

delete from public.user_profiles
where user_id in (
  '00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a2',
  '00000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-0000000000a4',
  '00000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-0000000000b1',
  '00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000b3'
);

delete from auth.users
where id in (
  '00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a2',
  '00000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-0000000000a4',
  '00000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-0000000000b1',
  '00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000b3'
);

-- Output
select label, case when pass then true else false end as pass, details
from _results
order by label;