-- Omnivia — Supabase Bootstrap Migration (Stage 1)
-- Derived from docs/sql/omni-bootstrap.sql
-- Note: This migration is executed by Supabase CLI which wraps statements in a transaction.
-- Do not add explicit BEGIN/COMMIT here.

-- Extensions
create extension if not exists "pgcrypto"; -- provides gen_random_uuid()

-- =========================
-- Core reference tables
-- =========================

-- Partner organizations (and optional subcontractor hierarchy)
create table if not exists public.partner_org (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  parent_partner_org_id uuid null references public.partner_org(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Normalization mapping for delivery partner labels from imports
create table if not exists public.partner_normalization (
  id uuid primary key default gen_random_uuid(),
  source_label text not null,
  partner_org_id uuid not null references public.partner_org(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Unique normalized source_label across rows (use expression index)
do $$
begin
  perform 1
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'partner_normalization_source_label_normalized_uniq';
  if not found then
    execute '
      create unique index partner_normalization_source_label_normalized_uniq
      on public.partner_normalization (lower(trim(source_label)))';
  end if;
end$$;

-- Directories for Deployment Specialists and Relationship Managers
create table if not exists public.ds_directory (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,                          -- human name for matching
  preferred_username text null,                         -- stable identifier if used
  user_id uuid null references auth.users(id) on delete set null,
  status text not null default 'active',                -- 'active' | 'inactive'
  created_at timestamptz not null default now()
);

create table if not exists public.rm_directory (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  preferred_username text null,
  user_id uuid null references auth.users(id) on delete set null,
  status text not null default 'active',
  created_at timestamptz not null default now()
);

-- Uniqueness on active display_name (normalized) to reduce ambiguity
do $$
begin
  perform 1
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'ds_directory_display_name_active_uniq';
  if not found then
    execute '
      create unique index ds_directory_display_name_active_uniq
      on public.ds_directory (lower(trim(display_name)))
      where status = ''active'' ';
  end if;
end$$;

do $$
begin
  perform 1
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'rm_directory_display_name_active_uniq';
  if not found then
    execute '
      create unique index rm_directory_display_name_active_uniq
      on public.rm_directory (lower(trim(display_name)))
      where status = ''active'' ';
  end if;
end$$;

-- =========================
-- Identity mirrors and feature flags
-- =========================

-- Profile mirror of Okta identifiers and tenant context
create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  okta_sub text not null,
  okta_user_id text not null,         -- preferred_username or custom id
  tenant_id text null,                -- e.g., 'TELCO' or 'DP_...' (string/UUID acceptable)
  partner_org_id uuid null references public.partner_org(id) on delete set null,
  sub_partner_org_id uuid null references public.partner_org(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Roles mirror (normalized)
create table if not exists public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,                 -- e.g., 'vendor_admin','telco_admin','telco_pm','telco_ds','telco_rm','dp_admin','dp_pm','dp_cp'
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

-- Per-tenant feature flags
create table if not exists public.features (
  tenant_id text not null,
  name text not null,
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, name)
);

-- Helpful indexes
create index if not exists user_profiles_tenant_idx on public.user_profiles (tenant_id);
create index if not exists user_profiles_partner_idx on public.user_profiles (partner_org_id, sub_partner_org_id);

-- =========================
-- Projects domain and UGC
-- =========================

-- Canonical projects (minimal seed aligned with PRD sections)
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null default 'TELCO',
  stage_application text not null,
  stage_application_created timestamptz not null default now(),
  delivery_partner_label text null,              -- raw label from import
  partner_org_id uuid null references public.partner_org(id) on delete set null,
  developer_class text null,                     -- normalized Developer Class
  derived_status text null,                      -- computed (Stage 5)
  created_at timestamptz not null default now()
);

create index if not exists projects_stage_idx on public.projects (stage_application, stage_application_created desc);
create index if not exists projects_partner_idx on public.projects (partner_org_id);
create index if not exists projects_status_idx on public.projects (derived_status);
create index if not exists projects_tenant_idx on public.projects (tenant_id);

-- Membership materialization for visibility and scoping
create table if not exists public.project_membership (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  member_user_id uuid null references auth.users(id) on delete cascade,
  member_partner_org_id uuid null references public.partner_org(id) on delete cascade,
  member_sub_partner_org_id uuid null references public.partner_org(id) on delete cascade,
  created_at timestamptz not null default now(),
  -- exactly one discriminator must be set
  constraint project_membership_one_member_ck check (
    (member_user_id is not null)::int +
    (member_partner_org_id is not null)::int +
    (member_sub_partner_org_id is not null)::int = 1
  )
);

create index if not exists pm_project_idx on public.project_membership (project_id);
create index if not exists pm_user_idx on public.project_membership (member_user_id);
create index if not exists pm_partner_idx on public.project_membership (member_partner_org_id);
create index if not exists pm_sub_partner_idx on public.project_membership (member_sub_partner_org_id);

-- UGC: Contacts and Engagements
create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  name text not null,
  phone text null,
  email text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists contacts_project_idx on public.contacts (project_id);

create table if not exists public.engagements (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'note',           -- e.g., 'note','call','site_visit'
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists engagements_project_idx on public.engagements (project_id);

-- Attachments metadata table; object lives in Storage bucket 'attachments'
create table if not exists public.attachments_meta (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  bucket text not null default 'attachments',
  object_name text not null,                   -- path/name within bucket
  content_type text null,
  size_bytes bigint null,
  created_at timestamptz not null default now(),
  unique (bucket, object_name)
);

create index if not exists attachments_project_idx on public.attachments_meta (project_id);

-- Staging imports (raw payloads and lineage)
create table if not exists public.staging_imports (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null,
  tenant_id text not null default 'TELCO',
  raw jsonb not null,
  checksum text not null,
  validation jsonb null,
  imported_at timestamptz not null default now()
);

create index if not exists staging_batch_idx on public.staging_imports (batch_id);
create index if not exists staging_tenant_idx on public.staging_imports (tenant_id);

-- =========================
-- Row Level Security
-- =========================

-- Enable RLS
alter table public.user_profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.projects enable row level security;
alter table public.contacts enable row level security;
alter table public.engagements enable row level security;
alter table public.attachments_meta enable row level security;
alter table public.features enable row level security;

-- Simple self-read policies for mirrors
drop policy if exists user_can_read_own_profile on public.user_profiles;
create policy user_can_read_own_profile
on public.user_profiles
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists user_can_read_own_roles on public.user_roles;
create policy user_can_read_own_roles
on public.user_roles
for select
to authenticated
using (auth.uid() = user_id);

-- Helper: using_rls_for_project(project_id)
-- Decides whether current user may view a given project by id.
create or replace function public.using_rls_for_project(p_project_id uuid)
returns boolean
language sql
stable
as $$
  with me as (
    select
      u.user_id,
      coalesce(up.tenant_id, 'TELCO') as tenant_id,
      up.partner_org_id,
      up.sub_partner_org_id
    from (select auth.uid() as user_id) u
    left join public.user_profiles up on up.user_id = u.user_id
  )
  select
    -- Vendor Admin: global
    exists (
      select 1 from public.user_roles r
      join me on me.user_id = r.user_id
      where r.role = 'vendor_admin'
    )
    or
    -- Telco Admin/PM: same-tenant visibility
    exists (
      select 1
      from public.user_roles r
      join me on me.user_id = r.user_id
      join public.projects p on p.id = p_project_id
      where r.role in ('telco_admin','telco_pm')
        and p.tenant_id = me.tenant_id
    )
    or
    -- Telco DS/RM: assigned projects via USER membership
    exists (
      select 1
      from public.user_roles r
      join me on me.user_id = r.user_id
      where r.role in ('telco_ds','telco_rm')
        and exists (
          select 1 from public.project_membership m
          where m.project_id = p_project_id
            and m.member_user_id = me.user_id
        )
    )
    or
    -- Delivery Partner roles: ORG or SUB_ORG membership
    exists (
      select 1
      from public.user_roles r
      join me on me.user_id = r.user_id
      where r.role in ('dp_admin','dp_pm','dp_cp')
        and (
          exists (
            select 1 from public.project_membership m1
            where m1.project_id = p_project_id
              and m1.member_partner_org_id = me.partner_org_id
          )
          or exists (
            select 1 from public.project_membership m2
            where m2.project_id = p_project_id
              and m2.member_sub_partner_org_id = me.sub_partner_org_id
          )
        )
    )
  ;
$$;

-- Projects select: gated by helper
drop policy if exists projects_select_policy on public.projects;
create policy projects_select_policy
on public.projects
for select
to authenticated
using (public.using_rls_for_project(id));

-- Projects update: admin only (example stub)
drop policy if exists projects_update_admin_only on public.projects;
create policy projects_update_admin_only
on public.projects
for update
to authenticated
using (
  exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid()
      and r.role in ('vendor_admin','telco_admin')
  )
);

-- Contacts policies
drop policy if exists contacts_select on public.contacts;
create policy contacts_select
on public.contacts
for select
to authenticated
using (public.using_rls_for_project(project_id));

drop policy if exists contacts_insert on public.contacts;
create policy contacts_insert
on public.contacts
for insert
to authenticated
with check (public.using_rls_for_project(project_id) and created_by = auth.uid());

drop policy if exists contacts_update_own on public.contacts;
create policy contacts_update_own
on public.contacts
for update
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id))
with check (created_by = auth.uid() and public.using_rls_for_project(project_id));

drop policy if exists contacts_delete_own on public.contacts;
create policy contacts_delete_own
on public.contacts
for delete
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id));

-- Engagements policies
drop policy if exists engagements_select on public.engagements;
create policy engagements_select
on public.engagements
for select
to authenticated
using (public.using_rls_for_project(project_id));

drop policy if exists engagements_insert on public.engagements;
create policy engagements_insert
on public.engagements
for insert
to authenticated
with check (public.using_rls_for_project(project_id) and created_by = auth.uid());

drop policy if exists engagements_update_own on public.engagements;
create policy engagements_update_own
on public.engagements
for update
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id))
with check (created_by = auth.uid() and public.using_rls_for_project(project_id));

drop policy if exists engagements_delete_own on public.engagements;
create policy engagements_delete_own
on public.engagements
for delete
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id));

-- Attachments metadata policies
drop policy if exists attachments_meta_select on public.attachments_meta;
create policy attachments_meta_select
on public.attachments_meta
for select
to authenticated
using (public.using_rls_for_project(project_id));

drop policy if exists attachments_meta_insert on public.attachments_meta;
create policy attachments_meta_insert
on public.attachments_meta
for insert
to authenticated
with check (public.using_rls_for_project(project_id) and created_by = auth.uid());

drop policy if exists attachments_meta_update_own on public.attachments_meta;
create policy attachments_meta_update_own
on public.attachments_meta
for update
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id))
with check (created_by = auth.uid() and public.using_rls_for_project(project_id));

drop policy if exists attachments_meta_delete_own on public.attachments_meta;
create policy attachments_meta_delete_own
on public.attachments_meta
for delete
to authenticated
using (created_by = auth.uid() and public.using_rls_for_project(project_id));

-- Features: tenant-scoped reads (example: everyone can read own-tenant flags)
drop policy if exists features_select_same_tenant on public.features;
create policy features_select_same_tenant
on public.features
for select
to authenticated
using (
  exists (
    select 1 from public.user_profiles up
    where up.user_id = auth.uid()
      and up.tenant_id = features.tenant_id
  )
);

-- =========================
-- Storage policies (bucket: attachments)
-- =========================
-- Re-run this section after creating the bucket if it didn't exist before.

-- Allow read when metadata + RLS allow access
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

-- Allow upload only if there's a metadata row prepared by the same user
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

-- Allow delete by creator or admin roles
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
      select 1
      from public.user_roles r
      where r.user_id = auth.uid()
        and r.role in ('vendor_admin','telco_admin')
    )
  )
);

-- End of Stage 1 migration