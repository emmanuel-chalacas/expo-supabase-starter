-- Omnivia — Stage 4 Migration (Import endpoint, merge, membership materialization)
-- Note: Supabase CLI wraps migrations in a transaction. Do not add BEGIN/COMMIT here.
-- Scope:
--  - Extend staging_imports lineage columns and indexes
--  - Add unique projects key per tenant
--  - Add columns on projects for DS/RM fields
--  - Create import_anomalies table
--  - Add normalization/lookup helpers
--  - Implement merge RPC and membership backfill

-- ========== DDL: staging_imports lineage and indexes ==========

-- lineage columns
alter table public.staging_imports
  add column if not exists source text not null default 'projects-import';

alter table public.staging_imports
  add column if not exists row_count integer not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'staging_imports_row_count_nonneg_ck'
      and conrelid = 'public.staging_imports'::regclass
  ) then
    alter table public.staging_imports
      add constraint staging_imports_row_count_nonneg_ck check (row_count >= 0);
  end if;
end$$;

alter table public.staging_imports
  add column if not exists correlation_id uuid not null default gen_random_uuid();

-- add batch_checksum (migrate existing checksum values if column becomes present)
alter table public.staging_imports
  add column if not exists batch_checksum text;

update public.staging_imports
set batch_checksum = coalesce(batch_checksum, checksum)
where batch_checksum is null;

do $$
begin
  -- enforce NOT NULL if column exists
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'staging_imports'
      and column_name = 'batch_checksum'
  ) then
    begin
      alter table public.staging_imports
        alter column batch_checksum set not null;
    exception when others then
      -- if existing NULLs prevent NOT NULL, leave as-is; migration remains re-runnable
      null;
    end;
  end if;
end$$;

-- indexes
create unique index if not exists staging_imports_tenant_checksum_uniq
  on public.staging_imports(tenant_id, batch_checksum);

create index if not exists staging_imports_imported_at_idx
  on public.staging_imports(imported_at desc);

-- ========== DDL: projects unique key + added columns ==========

-- unique key per tenant on stage_application
do $$
begin
  perform 1
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'projects_tenant_stage_application_uniq';
  if not found then
    -- This will fail if duplicates exist; intentional to guarantee idempotent merge semantics.
    execute 'create unique index projects_tenant_stage_application_uniq
             on public.projects(tenant_id, stage_application)';
  end if;
end$$;

-- additive columns
alter table public.projects add column if not exists deployment_specialist text;
alter table public.projects add column if not exists relationship_manager  text;
alter table public.projects add column if not exists rm_preferred_username text;

-- ========== DDL: import_anomalies table and indexes ==========

create table if not exists public.import_anomalies (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  staging_id uuid not null references public.staging_imports(id) on delete cascade,
  batch_id text not null,
  row_index integer not null,
  anomaly_type text not null,
  field text not null,
  input_value text null,
  reason text not null,
  match_type text null,
  project_key text null,
  correlation_id uuid not null,
  created_at timestamptz not null default now()
);

create index if not exists import_anomalies_tenant_batch_idx on public.import_anomalies(tenant_id, batch_id);
create index if not exists import_anomalies_staging_idx on public.import_anomalies(staging_id);
create index if not exists import_anomalies_created_idx on public.import_anomalies(created_at desc);
create index if not exists import_anomalies_type_idx on public.import_anomalies(anomaly_type);

-- ========== Types ==========

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'projects_import_merge_result'
  ) then
    create type public.projects_import_merge_result as (
      inserted_projects int,
      updated_projects int,
      org_memberships_upserted int,
      user_memberships_upserted int,
      anomalies_count int,
      staging_id uuid
    );
  end if;
end$$;

-- ========== Helper functions ==========

-- Normalize name-like text: trim, collapse internal whitespace, lower-case
create or replace function public.fn_normalize_name(p text)
returns text
language sql
immutable
as $$
  select case
    when p is null then null
    else lower(regexp_replace(btrim(p), '\s+', ' ', 'g'))
  end
$$;

-- Map Developer Class codes to canonical labels
-- Class 1 -> Key Strategic
-- Class 2 -> Managed
-- Class 3/4 -> Inbound
create or replace function public.fn_normalize_developer_class(p text)
returns text
language sql
immutable
as $$
  with n as (
    select public.fn_normalize_name(p) as v
  )
  select case
    when v is null or v = '' then null
    when v like 'class 1%' then 'Key Strategic'
    when v like 'class 2%' then 'Managed'
    when v like 'class 3%' then 'Inbound'
    when v like 'class 4%' then 'Inbound'
    else null
  end
  from n
$$;

-- Resolve partner_org.id from partner_normalization by normalized label; null if blank/Unassigned
create or replace function public.fn_partner_org_from_label(p_label text)
returns uuid
language sql
stable
as $$
  with norm as (
    select public.fn_normalize_name(p_label) as v
  )
  select case
    when v is null or v = '' or v = 'unassigned' then null
    else (
      select pn.partner_org_id
      from public.partner_normalization pn
      where lower(trim(pn.source_label)) = v
      limit 1
    )
  end
  from norm
$$;

-- Find DS auth user id by exact normalized preferred_username; status must be 'active'
create or replace function public.fn_find_ds_user_id(p_preferred_username text)
returns uuid
language sql
stable
as $$
  select d.user_id
  from public.ds_directory d
  where d.status = 'active'
    and d.preferred_username is not null
    and lower(trim(d.preferred_username)) = lower(trim(coalesce(p_preferred_username, '')))
  limit 1
$$;

-- Find RM auth user id:
--  - Prefer preferred_username override if provided (exact normalized match to rm_directory.preferred_username where active)
--  - Else exact normalized match on rm_directory.display_name where active
create or replace function public.fn_find_rm_user_id(p_display_name text, p_preferred_username text)
returns uuid
language sql
stable
as $$
  with params as (
    select
      public.fn_normalize_name(p_display_name) as dn,
      lower(trim(coalesce(p_preferred_username,''))) as pu
  )
  select coalesce(
    (
      select r.user_id
      from public.rm_directory r, params p
      where r.status = 'active'
        and r.preferred_username is not null
        and p.pu <> ''
        and lower(trim(r.preferred_username)) = p.pu
      limit 1
    ),
    (
      select r.user_id
      from public.rm_directory r, params p
      where r.status = 'active'
        and p.pu = '' -- only when no preferred_username provided
        and public.fn_normalize_name(r.display_name) = p.dn
      limit 1
    )
  )
$$;

-- Helper: compute deterministic checksum matching Edge Function logic
create or replace function public.fn_rows_checksum(p_rows jsonb)
returns text
language sql
stable
as $$
  with elems as (
    select jsonb_array_elements(p_rows) as row
  ),
  norm as (
    select
      coalesce(row->>'stage_application','') as stage_application,
      array_to_string(array[
        'stage_application='||coalesce(row->>'stage_application',''),
        'address='||coalesce(row->>'address',''),
        'eFscd='||coalesce(row->>'eFscd',''),
        'development_type='||coalesce(row->>'development_type',''),
        'build_type='||coalesce(row->>'build_type',''),
        'delivery_partner='||coalesce(row->>'delivery_partner',''),
        'fod_id='||coalesce(row->>'fod_id',''),
        'premises_count='||coalesce(row->>'premises_count',''),
        'residential='||coalesce(row->>'residential',''),
        'commercial='||coalesce(row->>'commercial',''),
        'essential='||coalesce(row->>'essential',''),
        'developer_class='||coalesce(row->>'developer_class',''),
        'latitude='||coalesce(row->>'latitude',''),
        'longitude='||coalesce(row->>'longitude',''),
        'relationship_manager='||coalesce(row->>'relationship_manager',''),
        'deployment_specialist='||coalesce(row->>'deployment_specialist',''),
        'rm_preferred_username='||coalesce(row->>'rm_preferred_username',''),
        'stage_application_created='||coalesce(row->>'stage_application_created',''),
        'developer_design_submitted='||coalesce(row->>'developer_design_submitted',''),
        'developer_design_accepted='||coalesce(row->>'developer_design_accepted',''),
        'issued_to_delivery_partner='||coalesce(row->>'issued_to_delivery_partner',''),
        'practical_completion_certified='||coalesce(row->>'practical_completion_certified',''),
        'delivery_partner_pc_sub='||coalesce(row->>'delivery_partner_pc_sub',''),
        'in_service='||coalesce(row->>'in_service','')
      ], '|') as line
    from elems
  ),
  ordered as (
    select line from norm order by stage_application
  ),
  concatenated as (
    select string_agg(line, E'\n') as s from ordered
  )
  select encode(digest(coalesce(s, ''), 'sha256'), 'hex')
  from concatenated
$$;

-- ========== Core merge RPC ==========

-- Merge imported rows into canonical projects and materialize memberships.
-- Short-circuits and returns memoized metrics if staging_imports.validation->'metrics' already present.
create or replace function public.fn_projects_import_merge(
  p_tenant_id text,
  p_source text,
  p_batch_id text,
  p_rows jsonb,
  p_correlation_id uuid
) returns public.projects_import_merge_result
language plpgsql
as $$
declare
  v_staging_id uuid;
  v_validation jsonb;
  v_rows_total int;
  v_idx int;
  v_row jsonb;

  v_stage_application text;
  v_dp_label text;
  v_dev_class text;
  v_rm_name text;
  v_rm_preferred_username text;
  v_ds_username text;
  v_partner_org_id uuid;
  v_ds_user_id uuid;
  v_rm_user_id uuid;
  v_project_id uuid;
  v_inserted boolean;
  v_sac timestamptz;
  v_batch_checksum text;

  -- counters
  c_inserted int := 0;
  c_updated int := 0;
  c_org_upserts int := 0;
  c_user_upserts int := 0;
  c_anomalies int := 0;

  v_metrics jsonb;
begin
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'rows must be a JSON array';
  end if;

  v_rows_total := jsonb_array_length(p_rows);

  -- Locate staging row by (tenant_id, batch_checksum) computed from rows
  v_batch_checksum := public.fn_rows_checksum(p_rows);

  select s.id, s.validation
  into v_staging_id, v_validation
  from public.staging_imports s
  where s.tenant_id = p_tenant_id
    and s.batch_checksum = v_batch_checksum
  order by s.imported_at desc
  limit 1;

  if v_staging_id is null then
    raise exception 'staging_imports row not found for tenant=%, checksum=%', p_tenant_id, v_batch_checksum;
  end if;

  -- Short-circuit if memoized metrics present
  if v_validation ? 'metrics' then
    v_metrics := v_validation - 'metrics' || jsonb_build_object('metrics', v_validation->'metrics');
    if (v_validation->'metrics') ? 'inserted_projects'
       and (v_validation->'metrics') ? 'updated_projects'
       and (v_validation->'metrics') ? 'org_memberships_upserted'
       and (v_validation->'metrics') ? 'user_memberships_upserted'
       and (v_validation->'metrics') ? 'anomalies_count'
    then
      return (
        ((v_validation->'metrics')->>'inserted_projects')::int,
        ((v_validation->'metrics')->>'updated_projects')::int,
        ((v_validation->'metrics')->>'org_memberships_upserted')::int,
        ((v_validation->'metrics')->>'user_memberships_upserted')::int,
        ((v_validation->'metrics')->>'anomalies_count')::int,
        v_staging_id
      )::public.projects_import_merge_result;
    end if;
  end if;

  -- Iterate rows (1-based row_index in anomalies)
  for v_idx in 0..(v_rows_total - 1) loop
    v_row := p_rows -> v_idx;

    v_stage_application := btrim(coalesce(v_row->>'stage_application',''));
    if v_stage_application is null or v_stage_application = '' then
      -- skip malformed row; could be extended to log a validation anomaly
      continue;
    end if;

    v_dp_label := btrim(coalesce(v_row->>'delivery_partner',''));
    v_dev_class := public.fn_normalize_developer_class(v_row->>'developer_class');
    v_rm_name := btrim(coalesce(v_row->>'relationship_manager',''));
    v_rm_preferred_username := nullif(btrim(coalesce(v_row->>'rm_preferred_username','')), '');
    v_ds_username := btrim(coalesce(v_row->>'deployment_specialist',''));

    -- optional: stage_application_created
    v_sac := null;
    begin
      if nullif(btrim(coalesce(v_row->>'stage_application_created','')), '') is not null then
        v_sac := (v_row->>'stage_application_created')::timestamptz;
      end if;
    exception when others then
      v_sac := null;
    end;

    -- Resolve mappings
    v_partner_org_id := public.fn_partner_org_from_label(v_dp_label);

    if v_partner_org_id is null and v_dp_label is not null and v_dp_label <> '' and public.fn_normalize_name(v_dp_label) <> 'unassigned' then
      insert into public.import_anomalies(tenant_id, staging_id, batch_id, row_index, anomaly_type, field, input_value, reason, match_type, project_key, correlation_id)
      values (p_tenant_id, v_staging_id, p_batch_id, v_idx + 1, 'UNKNOWN_DELIVERY_PARTNER', 'delivery_partner', v_dp_label, 'Delivery Partner label did not map to a partner_org', null, v_stage_application, p_correlation_id);
      c_anomalies := c_anomalies + 1;
    end if;

    v_ds_user_id := null;
    if coalesce(v_ds_username,'') <> '' then
      v_ds_user_id := public.fn_find_ds_user_id(v_ds_username);
      if v_ds_user_id is null then
        insert into public.import_anomalies(tenant_id, staging_id, batch_id, row_index, anomaly_type, field, input_value, reason, match_type, project_key, correlation_id)
        values (p_tenant_id, v_staging_id, p_batch_id, v_idx + 1, 'UNKNOWN_DS', 'deployment_specialist', v_ds_username, 'No active DS directory match', 'preferred_username', v_stage_application, p_correlation_id);
        c_anomalies := c_anomalies + 1;
      end if;
    end if;

    v_rm_user_id := null;
    if coalesce(v_rm_preferred_username,'') <> '' or coalesce(v_rm_name,'') <> '' then
      v_rm_user_id := public.fn_find_rm_user_id(v_rm_name, v_rm_preferred_username);
      if v_rm_user_id is null then
        insert into public.import_anomalies(tenant_id, staging_id, batch_id, row_index, anomaly_type, field, input_value, reason, match_type, project_key, correlation_id)
        values (
          p_tenant_id, v_staging_id, p_batch_id, v_idx + 1,
          'UNKNOWN_RM',
          case when coalesce(v_rm_preferred_username,'') <> '' then 'rm_preferred_username' else 'relationship_manager' end,
          case when coalesce(v_rm_preferred_username,'') <> '' then v_rm_preferred_username else v_rm_name end,
          'No active RM directory match',
          case when coalesce(v_rm_preferred_username,'') <> '' then 'preferred_username' else 'display_name' end,
          v_stage_application, p_correlation_id
        );
        c_anomalies := c_anomalies + 1;
      end if;
    end if;

    -- Upsert project by (tenant_id, stage_application)
    with up as (
      insert into public.projects(
        tenant_id, stage_application, stage_application_created,
        delivery_partner_label, partner_org_id, developer_class,
        deployment_specialist, relationship_manager, rm_preferred_username
      )
      values (
        p_tenant_id, v_stage_application, v_sac,
        nullif(v_dp_label,''), v_partner_org_id, v_dev_class,
        nullif(v_ds_username,''), nullif(v_rm_name,''), nullif(v_rm_preferred_username,'')
      )
      on conflict (tenant_id, stage_application) do update
      set
        delivery_partner_label = excluded.delivery_partner_label,
        partner_org_id = excluded.partner_org_id,
        developer_class = excluded.developer_class,
        deployment_specialist = excluded.deployment_specialist,
        relationship_manager = excluded.relationship_manager,
        rm_preferred_username = excluded.rm_preferred_username,
        stage_application_created = coalesce(excluded.stage_application_created, public.projects.stage_application_created)
      returning id, (xmax = 0) as inserted
    )
    select id, inserted into v_project_id, v_inserted from up;

    if v_inserted then
      c_inserted := c_inserted + 1;
    else
      c_updated := c_updated + 1;
    end if;

    -- Reconcile memberships

    -- ORG membership
    if v_partner_org_id is not null then
      -- delete any other ORG rows
      delete from public.project_membership
      where project_id = v_project_id
        and member_partner_org_id is not null
        and member_partner_org_id <> v_partner_org_id;

      -- ensure desired ORG row exists
      perform 1
      from public.project_membership
      where project_id = v_project_id
        and member_partner_org_id = v_partner_org_id;
      if not found then
        insert into public.project_membership(project_id, member_partner_org_id)
        values (v_project_id, v_partner_org_id);
        c_org_upserts := c_org_upserts + 1;
      end if;
    else
      -- no ORG membership when Unassigned
      delete from public.project_membership
      where project_id = v_project_id
        and member_partner_org_id is not null;
    end if;

    -- USER memberships (DS and RM): ensure presence for desired, delete any others
    delete from public.project_membership
    where project_id = v_project_id
      and member_user_id is not null
      and member_user_id not in (
        coalesce(v_ds_user_id, '00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(v_rm_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
      );

    if v_ds_user_id is not null then
      perform 1
      from public.project_membership
      where project_id = v_project_id
        and member_user_id = v_ds_user_id;
      if not found then
        insert into public.project_membership(project_id, member_user_id)
        values (v_project_id, v_ds_user_id);
        c_user_upserts := c_user_upserts + 1;
      end if;
    end if;

    if v_rm_user_id is not null then
      perform 1
      from public.project_membership
      where project_id = v_project_id
        and member_user_id = v_rm_user_id;
      if not found then
        insert into public.project_membership(project_id, member_user_id)
        values (v_project_id, v_rm_user_id);
        c_user_upserts := c_user_upserts + 1;
      end if;
    end if;

  end loop;

  -- Persist memoized metrics and row_count on staging record
  update public.staging_imports s
  set
    row_count = v_rows_total,
    validation = coalesce(s.validation, '{}'::jsonb) || jsonb_build_object(
      'metrics', jsonb_build_object(
        'inserted_projects', c_inserted,
        'updated_projects', c_updated,
        'org_memberships_upserted', c_org_upserts,
        'user_memberships_upserted', c_user_upserts,
        'anomalies_count', c_anomalies
      )
    )
  where s.id = v_staging_id;

  return (c_inserted, c_updated, c_org_upserts, c_user_upserts, c_anomalies, v_staging_id);
end;
$$;

-- ========== One-off membership backfill ==========

-- Enforce desired ORG/USER memberships for all projects based on current project fields and directories.
create or replace function public.fn_projects_membership_backfill()
returns integer
language plpgsql
as $$
declare
  r record;
  v_ds_user_id uuid;
  v_rm_user_id uuid;
  v_upserts int := 0;
begin
  for r in
    select p.id as project_id, p.partner_org_id, p.deployment_specialist, p.relationship_manager, p.rm_preferred_username
    from public.projects p
  loop
    -- ORG reconciliation
    if r.partner_org_id is not null then
      delete from public.project_membership
      where project_id = r.project_id
        and member_partner_org_id is not null
        and member_partner_org_id <> r.partner_org_id;

      perform 1 from public.project_membership
      where project_id = r.project_id
        and member_partner_org_id = r.partner_org_id;
      if not found then
        insert into public.project_membership(project_id, member_partner_org_id)
        values (r.project_id, r.partner_org_id);
        v_upserts := v_upserts + 1;
      end if;
    else
      delete from public.project_membership
      where project_id = r.project_id
        and member_partner_org_id is not null;
    end if;

    -- USER reconciliation (DS + RM)
    v_ds_user_id := public.fn_find_ds_user_id(r.deployment_specialist);
    v_rm_user_id := public.fn_find_rm_user_id(r.relationship_manager, r.rm_preferred_username);

    delete from public.project_membership
    where project_id = r.project_id
      and member_user_id is not null
      and member_user_id not in (
        coalesce(v_ds_user_id, '00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(v_rm_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
      );

    if v_ds_user_id is not null then
      perform 1 from public.project_membership
      where project_id = r.project_id and member_user_id = v_ds_user_id;
      if not found then
        insert into public.project_membership(project_id, member_user_id)
        values (r.project_id, v_ds_user_id);
        v_upserts := v_upserts + 1;
      end if;
    end if;

    if v_rm_user_id is not null then
      perform 1 from public.project_membership
      where project_id = r.project_id and member_user_id = v_rm_user_id;
      if not found then
        insert into public.project_membership(project_id, member_user_id)
        values (r.project_id, v_rm_user_id);
        v_upserts := v_upserts + 1;
      end if;
    end if;

  end loop;

  return v_upserts;
end;
$$;