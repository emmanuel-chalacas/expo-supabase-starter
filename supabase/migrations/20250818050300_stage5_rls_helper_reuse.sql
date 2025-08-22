-- Omnivia — Stage 5 Migration (C2): RLS helper reuse standardization
-- Ref: Medium Priority Issue 12 — docs/product/projects-okta-rbac-stage1-4-audit.md:191
-- Purpose: Ensure all relevant RLS policies consistently reuse public.using_rls_for_project(uuid)
-- Notes: Idempotent (DROP POLICY IF EXISTS...), no schema shape changes, only policy rewrites and RLS enablement.

-- 0) Ensure RLS enabled for target tables
alter table public.projects enable row level security;
alter table public.contacts enable row level security;
alter table public.engagements enable row level security;
alter table public.attachments_meta enable row level security;
-- storage.objects is managed by the Storage extension; enable RLS defensively
-- Only attempt if current_user owns the table; otherwise skip to avoid permission errors.
do $rls$
declare
  v_owner text;
begin
  select r.rolname
  into v_owner
  from pg_roles r
  join pg_class c on c.relowner = r.oid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'storage'
    and c.relname = 'objects';

  if v_owner is null then
    raise notice 'Skipping RLS enable on storage.objects; table not found';
  elsif v_owner = current_user then
    execute 'alter table storage.objects enable row level security';
  else
    raise notice 'Skipping RLS enable on storage.objects; owner is %, current_user is %', v_owner, current_user;
  end if;
end
$rls$;

-- 1) public.projects
-- Drop existing project-scoped policies and recreate using helper
drop policy if exists rls_projects_select on public.projects;
drop policy if exists projects_select_policy on public.projects;
create policy projects_select_policy
on public.projects
for select
to authenticated
using (public.using_rls_for_project(id));

drop policy if exists rls_projects_update on public.projects;
drop policy if exists projects_update_admin_only on public.projects;
create policy projects_update_admin_only
on public.projects
for update
to authenticated
using (
  public.using_rls_for_project(id)
  and exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid()
      and r.role in ('vendor_admin','telco_admin')
  )
)
with check (
  public.using_rls_for_project(id)
  and exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid()
      and r.role in ('vendor_admin','telco_admin')
  )
);

-- 2) public.contacts
drop policy if exists rls_contacts_select on public.contacts;
drop policy if exists contacts_select on public.contacts;
create policy contacts_select
on public.contacts
for select
to authenticated
using (public.using_rls_for_project(project_id));

drop policy if exists rls_contacts_insert on public.contacts;
drop policy if exists contacts_insert on public.contacts;
create policy contacts_insert
on public.contacts
for insert
to authenticated
with check (public.using_rls_for_project(project_id) and created_by = auth.uid());

drop policy if exists rls_contacts_update_own on public.contacts;
drop policy if exists contacts_update_own on public.contacts;
create policy contacts_update_own
on public.contacts
for update
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id))
with check (created_by = auth.uid() and public.using_rls_for_project(project_id));

drop policy if exists rls_contacts_delete_own on public.contacts;
drop policy if exists contacts_delete_own on public.contacts;
create policy contacts_delete_own
on public.contacts
for delete
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id));

-- 3) public.engagements
drop policy if exists rls_engagements_select on public.engagements;
drop policy if exists engagements_select on public.engagements;
create policy engagements_select
on public.engagements
for select
to authenticated
using (public.using_rls_for_project(project_id));

drop policy if exists rls_engagements_insert on public.engagements;
drop policy if exists engagements_insert on public.engagements;
create policy engagements_insert
on public.engagements
for insert
to authenticated
with check (public.using_rls_for_project(project_id) and created_by = auth.uid());

drop policy if exists rls_engagements_update_own on public.engagements;
drop policy if exists engagements_update_own on public.engagements;
create policy engagements_update_own
on public.engagements
for update
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id))
with check (created_by = auth.uid() and public.using_rls_for_project(project_id));

drop policy if exists rls_engagements_delete_own on public.engagements;
drop policy if exists engagements_delete_own on public.engagements;
create policy engagements_delete_own
on public.engagements
for delete
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id));

-- 4) public.attachments_meta
drop policy if exists rls_attachments_meta_select on public.attachments_meta;
drop policy if exists attachments_meta_select on public.attachments_meta;
create policy attachments_meta_select
on public.attachments_meta
for select
to authenticated
using (public.using_rls_for_project(project_id));

drop policy if exists rls_attachments_meta_insert on public.attachments_meta;
drop policy if exists attachments_meta_insert on public.attachments_meta;
create policy attachments_meta_insert
on public.attachments_meta
for insert
to authenticated
with check (public.using_rls_for_project(project_id) and created_by = auth.uid());

drop policy if exists rls_attachments_meta_update_own on public.attachments_meta;
drop policy if exists attachments_meta_update_own on public.attachments_meta;
create policy attachments_meta_update_own
on public.attachments_meta
for update
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id))
with check (created_by = auth.uid() and public.using_rls_for_project(project_id));

drop policy if exists rls_attachments_meta_delete_own on public.attachments_meta;
drop policy if exists attachments_meta_delete_own on public.attachments_meta;
create policy attachments_meta_delete_own
on public.attachments_meta
for delete
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id));

-- 5) storage.objects for attachments path
-- Keep policy names for compatibility with existing verification tests
drop policy if exists attachments_read on storage.objects;
create policy attachments_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'attachments'
  and exists (
    select 1
    from public.attachments_meta am
    where am.bucket = 'attachments'
      and am.object_name = storage.objects.name
      and public.using_rls_for_project(am.project_id)
  )
);

drop policy if exists attachments_insert on storage.objects;
create policy attachments_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'attachments'
  and exists (
    select 1
    from public.attachments_meta am
    where am.bucket = 'attachments'
      and am.object_name = storage.objects.name
      and am.created_by = auth.uid()
      and public.using_rls_for_project(am.project_id)
  )
);

drop policy if exists attachments_delete on storage.objects;
create policy attachments_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'attachments'
  and (
    exists (
      select 1
      from public.attachments_meta am
      where am.bucket = 'attachments'
        and am.object_name = storage.objects.name
        and am.created_by = auth.uid()
        and public.using_rls_for_project(am.project_id)
    )
    or exists (
      select 1 from public.user_roles r
      where r.user_id = auth.uid()
        and r.role in ('vendor_admin','telco_admin')
    )
  )
);