-- Omnivia — Stage 2 Migration (Apply)
-- Derived from docs/sql/stage2-apply.sql
-- Note: Supabase CLI wraps migrations in a transaction. Do not add BEGIN/COMMIT here.

-- 1) Ensure private bucket 'attachments' exists
do $$
begin
  if not exists (select 1 from storage.buckets where name = 'attachments') then
    perform storage.create_bucket('attachments', false);
  end if;
end $$;

-- 2) Storage policies (re-apply duplicates-safe for bucket 'attachments')
-- attachments_read
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

-- attachments_insert
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

-- attachments_delete
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

-- 3) Seed canonical partner_org rows (UPSERT by normalized name)
with canonical(name) as (
  values
    ('Fulton Hogan'),
    ('Ventia'),
    ('UGL'),
    ('Enerven'),
    ('Servicestream')
)
insert into public.partner_org (name)
select c.name
from canonical c
where not exists (
  select 1 from public.partner_org p
  where lower(trim(p.name)) = lower(trim(c.name))
);

-- 4) Seed partner_normalization mappings to canonical partner_org rows (UPSERT by normalized source_label, intra-batch deduped)

-- Diagnostic: duplicates in mappings after normalization (should return zero rows)
with mappings(canonical_name, source_label) as (
  values
    ('Fulton Hogan','Fulton Hogan'),
    ('Fulton Hogan','FULTON HOGAN'),
    ('Fulton Hogan','FultonHogan'),
    ('Fulton Hogan','Fulton Hogan Pty Ltd'),
    ('Ventia','Ventia'),
    ('Ventia','VENTIA'),
    ('UGL','UGL'),
    ('UGL','UGL Limited'),
    ('Enerven','Enerven'),
    ('Enerven','ENERVEN'),
    ('Servicestream','Servicestream'),
    ('Servicestream','Service Stream'),
    ('Servicestream','SERVICE STREAM'),
    ('Servicestream','SERVICESTREAM')
)
select lower(trim(source_label)) as norm, count(*) as dup_count, array_agg(source_label order by source_label) as variants
from mappings
group by lower(trim(source_label))
having count(*) > 1;

-- Deduplicated insert by normalized label to satisfy unique index on lower(trim(source_label))
with
  canon as (
    select id as partner_org_id, name
    from public.partner_org
    where lower(trim(name)) in (
      'fulton hogan','ventia','ugl','enerven','servicestream'
    )
  ),
  mappings(canonical_name, source_label) as (
    values
      ('Fulton Hogan','Fulton Hogan'),
      ('Fulton Hogan','FULTON HOGAN'),
      ('Fulton Hogan','FultonHogan'),
      ('Fulton Hogan','Fulton Hogan Pty Ltd'),
      ('Ventia','Ventia'),
      ('Ventia','VENTIA'),
      ('UGL','UGL'),
      ('UGL','UGL Limited'),
      ('Enerven','Enerven'),
      ('Enerven','ENERVEN'),
      ('Servicestream','Servicestream'),
      ('Servicestream','Service Stream'),
      ('Servicestream','SERVICE STREAM'),
      ('Servicestream','SERVICESTREAM')
  ),
  m_norm as (
    select
      canonical_name,
      source_label,
      lower(trim(source_label)) as norm_label
    from mappings
  ),
  dedup as (
    select
      canonical_name,
      min(source_label) as source_label,
      norm_label
    from m_norm
    group by canonical_name, norm_label
  )
insert into public.partner_normalization (source_label, partner_org_id)
select d.source_label, c.partner_org_id
from dedup d
join canon c on lower(trim(c.name)) = lower(trim(d.canonical_name))
where not exists (
  select 1 from public.partner_normalization pn
  where lower(trim(pn.source_label)) = d.norm_label
);

-- 5) Seed tenant feature flags (UPSERT per tenant_id x feature_key)
with tenants as (
  select 'TELCO'::text as tenant_id
  union
  select distinct tenant_id from public.user_profiles where tenant_id is not null
),
flags(name, enabled) as (
  values
    ('ENABLE_PROJECTS', false),
    ('ENABLE_ATTACHMENTS_UPLOAD', false),
    ('ENABLE_OKTA_AUTH', false)
)
insert into public.features (tenant_id, name, enabled)
select t.tenant_id, f.name, f.enabled
from tenants t
cross join flags f
on conflict (tenant_id, name) do nothing;

-- 6) Validate/create indexes for common filters (no-ops if already exist)
create index if not exists projects_stage_idx on public.projects (stage_application, stage_application_created desc);
create index if not exists projects_partner_idx on public.projects (partner_org_id);
create index if not exists projects_status_idx on public.projects (derived_status);
create index if not exists projects_tenant_idx on public.projects (tenant_id);