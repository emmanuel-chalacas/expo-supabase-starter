-- Omnivia — Stage 5: Overall Project Status computation
-- Idempotent migration: adds date columns, CHECK constraint, helper functions, recompute RPCs, trigger,
-- and integrates post-merge recompute into Stage 4 merge function (CREATE OR REPLACE).
-- Do not wrap in BEGIN/COMMIT (Supabase CLI manages transaction).

-- ========== 1a) Schema updates on projects ==========

alter table public.projects add column if not exists efscd date;
alter table public.projects add column if not exists developer_design_submitted date;
alter table public.projects add column if not exists developer_design_accepted date;
alter table public.projects add column if not exists issued_to_delivery_partner date;
alter table public.projects add column if not exists practical_completion_certified date;
alter table public.projects add column if not exists delivery_partner_pc_sub date;
alter table public.projects add column if not exists in_service date;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'projects_derived_status_ck'
      and conrelid = 'public.projects'::regclass
  ) then
    alter table public.projects
      add constraint projects_derived_status_ck
      check (
        derived_status is null
        or derived_status in (
          'In Progress',
          'In Progress - Overdue',
          'Complete',
          'Complete Overdue',
          'Complete Overdue Late App'
        )
      );
  end if;
end$$;

-- ========== 1b) Business-day helper ==========

create or replace function public.fn_business_days_between(p_start date, p_end date)
returns integer
language sql
immutable
as $$
  select case
    when p_start is null or p_end is null then null::integer
    when p_end <= p_start then 0
    else (
      select count(*)::int
      from generate_series(p_start + 1, p_end, interval '1 day') g(d)
      where extract(isodow from d) between 1 and 5
    )
  end
$$;

-- ========== 1c) Single-project pure compute function ==========

create or replace function public.fn_projects_derived_status_compute(p_project_id uuid)
returns text
language plpgsql
stable
as $$
declare
  v_tz constant text := 'Australia/Adelaide';
  today_tenant date := (now() at time zone 'Australia/Adelaide')::date;

  v_sac_ts timestamptz;
  sac_local_date date;

  v_efscd date;
  v_dds date;
  v_dda date;
  v_issued date;
  v_pcc date;
  v_dp_pc_sub date;
  v_in_service date;

  late_app boolean := false;
  remaining_bd integer;
  elapsed_since_issued_bd integer;
  overdue boolean := false;
begin
  -- Load project dates
  select
    p.stage_application_created,
    p.efscd,
    p.developer_design_submitted,
    p.developer_design_accepted,
    p.issued_to_delivery_partner,
    p.practical_completion_certified,
    p.delivery_partner_pc_sub,
    p.in_service
  into
    v_sac_ts,
    v_efscd,
    v_dds,
    v_dda,
    v_issued,
    v_pcc,
    v_dp_pc_sub,
    v_in_service
  from public.projects p
  where p.id = p_project_id;

  -- If missing row, return null
  if not found then
    return null;
  end if;

  -- If EFSCD is missing, status is not computed (MVP)
  if v_efscd is null then
    return null;
  end if;

  sac_local_date := case when v_sac_ts is null then null else (v_sac_ts at time zone v_tz)::date end;

  -- Late App: sac within < 70 business days of EFSCD
  if sac_local_date is not null then
    late_app := coalesce(public.fn_business_days_between(sac_local_date, v_efscd) < 70, false);
  else
    late_app := false;
  end if;

  remaining_bd := public.fn_business_days_between(today_tenant, v_efscd);
  elapsed_since_issued_bd := public.fn_business_days_between(v_issued, today_tenant);

  -- Completion precedence
  if v_in_service is not null then
    if v_in_service <= v_efscd then
      return 'Complete';
    else
      if late_app then
        return 'Complete Overdue Late App';
      else
        return 'Complete Overdue';
      end if;
    end if;
  end if;

  -- In-progress overdue conditions
  -- A) Today > EFSCD
  if today_tenant > v_efscd then
    overdue := true;
  end if;

  -- B) Fewer than 60 BD until EFSCD and Developer Design Accepted is null
  if overdue = false and remaining_bd is not null and remaining_bd < 60 and v_dda is null then
    overdue := true;
  end if;

  -- C) DD Accepted occurred later than 60 BD before EFSCD
  if overdue = false and v_dda is not null and coalesce(public.fn_business_days_between(v_dda, v_efscd) < 60, false) then
    overdue := true;
  end if;

  -- D) Fewer than 20 BD remain and PCC is null, with Late App-specific waivers
  if overdue = false and remaining_bd is not null and remaining_bd < 20 and v_pcc is null then
    if not late_app then
      overdue := true;
    else
      -- Late App: allow additional time unless elapsed since issue > 20 BD or Issued is missing
      if (v_issued is null) then
        overdue := true;
      elsif coalesce(elapsed_since_issued_bd, 0) > 20 then
        overdue := true;
      end if;
    end if;
  end if;

  -- E) PCC achieved but outside allowed window
  if overdue = false and v_pcc is not null then
    if not late_app then
      -- Standard rule: must be at least 20 BD before EFSCD
      if coalesce(public.fn_business_days_between(v_pcc, v_efscd) < 20, false) then
        overdue := true;
      end if;
    else
      -- Late App waiver:
      -- If Issued present: PCC must be within 20 BD after Issued
      if v_issued is not null then
        if coalesce(public.fn_business_days_between(v_issued, v_pcc) > 20, false) then
          overdue := true;
        end if;
      else
        -- If Issued missing, apply standard 20 BD before EFSCD rule
        if coalesce(public.fn_business_days_between(v_pcc, v_efscd) < 20, false) then
          overdue := true;
        end if;
      end if;
    end if;
  end if;

  if overdue then
    return 'In Progress - Overdue';
  else
    return 'In Progress';
  end if;
end;
$$;

-- ========== 1d) Set-based recompute helpers ==========

create or replace function public.fn_projects_derived_status_recompute_changed(p_project_ids uuid[])
returns integer
language plpgsql
as $$
declare
  v_count int := 0;
begin
  with ids as (
    select distinct x as id
    from unnest(coalesce(p_project_ids, array[]::uuid[])) as t(x)
    where x is not null
  ),
  comp as (
    select i.id, public.fn_projects_derived_status_compute(i.id) as v
    from ids i
  ),
  upd as (
    update public.projects p
    set derived_status = c.v
    from comp c
    where p.id = c.id
      and (p.derived_status is distinct from c.v)
    returning 1
  )
  select coalesce(count(*), 0) into v_count from upd;
  return v_count;
end;
$$;

create or replace function public.fn_projects_derived_status_recompute_by_staging(p_staging_id uuid)
returns integer
language plpgsql
as $$
declare
  v_tenant text;
  v_raw jsonb;
  v_ids uuid[];
  v_count int := 0;
begin
  select s.tenant_id, s.raw
  into v_tenant, v_raw
  from public.staging_imports s
  where s.id = p_staging_id;

  if v_tenant is null or v_raw is null then
    return 0;
  end if;

  with sapps as (
    select btrim(coalesce(j->>>'stage_application','')) as stage_app
    from jsonb_array_elements(v_raw) as j
    where btrim(coalesce(j->>>'stage_application','')) <> ''
  ),
  ids as (
    select p.id
    from sapps sa
    join public.projects p
      on p.tenant_id = v_tenant
     and p.stage_application = sa.stage_app
  )
  select array_agg(id) into v_ids from ids;

  if v_ids is null or array_length(v_ids, 1) is null then
    return 0;
  end if;

  v_count := public.fn_projects_derived_status_recompute_changed(v_ids);
  return v_count;
end;
$$;

-- ========== 1e) Operator RPC (SECURITY DEFINER) ==========

create or replace function public.rpc_projects_status_recompute(
  p_tenant_id text default null,
  p_project_ids uuid[] default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce((current_setting('request.jwt.claims', true)::jsonb ->> 'role'), '');
  v_ids uuid[];
  v_count int := 0;
begin
  -- Allow only service role or internal database roles
  if not (v_role = 'service_role' or current_user in ('postgres','supabase_admin')) then
    raise exception 'permission denied for rpc_projects_status_recompute()';
  end if;

  if p_project_ids is not null then
    v_ids := p_project_ids;
  elsif p_tenant_id is not null then
    select array_agg(id) into v_ids
    from public.projects
    where tenant_id = p_tenant_id;
  else
    select array_agg(id) into v_ids
    from public.projects;
  end if;

  if v_ids is null or array_length(v_ids, 1) is null then
    return 0;
  end if;

  v_count := public.fn_projects_derived_status_recompute_changed(v_ids);
  return v_count;
end;
$$;

-- ========== 1f) Trigger on public.projects ==========

create or replace function public.trg_projects_status_after_write()
returns trigger
language plpgsql
as $$
begin
  perform public.fn_projects_derived_status_recompute_changed(ARRAY[NEW.id]);
  return NEW;
end;
$$;

drop trigger if exists tr_projects_derived_status_after_write on public.projects;

create trigger tr_projects_derived_status_after_write
after insert or update of
  efscd,
  stage_application_created,
  developer_design_submitted,
  developer_design_accepted,
  issued_to_delivery_partner,
  practical_completion_certified,
  delivery_partner_pc_sub,
  in_service
on public.projects
for each row
execute function public.trg_projects_status_after_write();

-- ========== 2) Integrate with Stage 4 merge (post-merge recompute) ==========
-- We extend fn_projects_import_merge(...) to (a) populate new date columns and
-- (b) invoke set-based status recomputation for the affected staging batch.
-- IMPORTANT: Merge semantics remain unchanged; updates of date columns are COALESCE-preserving.

create or replace function public.fn_projects_import_merge(
  p_tenant_id text,
  p_source text,
  p_batch_id text,
  p_rows jsonb,
  p_correlation_id uuid
) returns public.projects_import_merge_result
language plpgsql
as $fn$
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

  -- NEW: date fields parsed from payload (normalized to date)
  v_efscd date;
  v_dds date;
  v_dda date;
  v_issued date;
  v_pcc date;
  v_dp_pc_sub date;
  v_in_service date;

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
      continue;
    end if;

    v_dp_label := btrim(coalesce(v_row->>'delivery_partner',''));
    v_dev_class := public.fn_normalize_developer_class(v_row->>'developer_class');
    v_rm_name := btrim(coalesce(v_row->>'relationship_manager',''));
    v_rm_preferred_username := nullif(btrim(coalesce(v_row->>'rm_preferred_username','')), '');
    v_ds_username := btrim(coalesce(v_row->>'deployment_specialist',''));

    -- stage_application_created (optional)
    v_sac := null;
    begin
      if nullif(btrim(coalesce(v_row->>'stage_application_created','')), '') is not null then
        v_sac := (v_row->>'stage_application_created')::timestamptz;
      end if;
    exception when others then
      v_sac := null;
    end;

    -- NEW: parse date fields (normalize to date, tolerate datetime)
    v_efscd := null; v_dds := null; v_dda := null; v_issued := null; v_pcc := null; v_dp_pc_sub := null; v_in_service := null;
    begin if nullif(btrim(coalesce(v_row->>'eFscd','')), '') is not null then v_efscd := (v_row->>'eFscd')::timestamptz::date; end if; exception when others then v_efscd := null; end;
    begin if nullif(btrim(coalesce(v_row->>'developer_design_submitted','')), '') is not null then v_dds := (v_row->>'developer_design_submitted')::timestamptz::date; end if; exception when others then v_dds := null; end;
    begin if nullif(btrim(coalesce(v_row->>'developer_design_accepted','')), '') is not null then v_dda := (v_row->>'developer_design_accepted')::timestamptz::date; end if; exception when others then v_dda := null; end;
    begin if nullif(btrim(coalesce(v_row->>'issued_to_delivery_partner','')), '') is not null then v_issued := (v_row->>'issued_to_delivery_partner')::timestamptz::date; end if; exception when others then v_issued := null; end;
    begin if nullif(btrim(coalesce(v_row->>'practical_completion_certified','')), '') is not null then v_pcc := (v_row->>'practical_completion_certified')::timestamptz::date; end if; exception when others then v_pcc := null; end;
    begin if nullif(btrim(coalesce(v_row->>'delivery_partner_pc_sub','')), '') is not null then v_dp_pc_sub := (v_row->>'delivery_partner_pc_sub')::timestamptz::date; end if; exception when others then v_dp_pc_sub := null; end;
    begin if nullif(btrim(coalesce(v_row->>'in_service','')), '') is not null then v_in_service := (v_row->>'in_service')::timestamptz::date; end if; exception when others then v_in_service := null; end;

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

    -- Upsert project by (tenant_id, stage_application) including new date columns
    with up as (
      insert into public.projects(
        tenant_id, stage_application, stage_application_created,
        efscd, developer_design_submitted, developer_design_accepted,
        issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
        delivery_partner_label, partner_org_id, developer_class,
        deployment_specialist, relationship_manager, rm_preferred_username
      )
      values (
        p_tenant_id, v_stage_application, v_sac,
        v_efscd, v_dds, v_dda,
        v_issued, v_pcc, v_dp_pc_sub, v_in_service,
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
        stage_application_created = coalesce(excluded.stage_application_created, public.projects.stage_application_created),
        efscd = coalesce(excluded.efscd, public.projects.efscd),
        developer_design_submitted = coalesce(excluded.developer_design_submitted, public.projects.developer_design_submitted),
        developer_design_accepted = coalesce(excluded.developer_design_accepted, public.projects.developer_design_accepted),
        issued_to_delivery_partner = coalesce(excluded.issued_to_delivery_partner, public.projects.issued_to_delivery_partner),
        practical_completion_certified = coalesce(excluded.practical_completion_certified, public.projects.practical_completion_certified),
        delivery_partner_pc_sub = coalesce(excluded.delivery_partner_pc_sub, public.projects.delivery_partner_pc_sub),
        in_service = coalesce(excluded.in_service, public.projects.in_service)
      returning id, (xmax = 0) as inserted
    )
    select id, inserted into v_project_id, v_inserted from up;

    if v_inserted then
      c_inserted := c_inserted + 1;
    else
      c_updated := c_updated + 1;
    end if;

    -- Reconcile memberships (unchanged)
    if v_partner_org_id is not null then
      delete from public.project_membership
      where project_id = v_project_id
        and member_partner_org_id is not null
        and member_partner_org_id <> v_partner_org_id;

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
      delete from public.project_membership
      where project_id = v_project_id
        and member_partner_org_id is not null;
    end if;

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

  -- NEW: Post-merge recompute of derived status for affected projects in this staging batch
  perform public.fn_projects_derived_status_recompute_by_staging(v_staging_id);

  return (c_inserted, c_updated, c_org_upserts, c_user_upserts, c_anomalies, v_staging_id);
end;
$fn$;