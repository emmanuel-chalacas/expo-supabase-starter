-- Omnivia — Stage 6: Functions Alignment (Task 4)
-- Idempotent migration to align checksum helper and merge RPC with Task 3 importer changes.
-- Spec anchors: Section 8.D and Task 4 in docs/product/projects-data-field-inventory.md
-- Note: Supabase CLI wraps migrations in a transaction; do not add BEGIN/COMMIT.

-- ========== 1) Helper: deterministic rows checksum (mirror importer ordering) ==========
-- Task 4: Remove keys development_type, rm_preferred_username; Add suburb, state, practical_completion_notified
-- Key order must match importer (source of truth) in supabase/functions/import-projects/index.ts:
--   1) stage_application
--   2) address
--   3) suburb
--   4) state
--   5) eFscd
--   6) build_type
--   7) delivery_partner_label (payload key: "delivery_partner")
--   8) fod_id
--   9) premises_count
--   10) residential
--   11) commercial
--   12) essential
--   13) developer_class
--   14) latitude
--   15) longitude
--   16) relationship_manager
--   17) deployment_specialist
--   18) stage_application_created
--   19) developer_design_submitted
--   20) developer_design_accepted
--   21) issued_to_delivery_partner
--   22) practical_completion_notified
--   23) practical_completion_certified
--   24) delivery_partner_pc_sub
--   25) in_service
-- Implementation notes:
-- - Trim string representations; nulls map to '' to guarantee determinism
-- - Sort rows by stage_application; join with '\n'; hash with same digest as Stage 4 (sha256)

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
      coalesce(btrim(row->>'stage_application'),'') as stage_application,
      array_to_string(array[
        'stage_application='||coalesce(btrim(row->>'stage_application'),''),
        'address='||coalesce(btrim(row->>'address'),''),
        'suburb='||coalesce(btrim(row->>'suburb'),''),
        'state='||coalesce(btrim(row->>'state'),''),
        'eFscd='||coalesce(btrim(row->>'eFscd'),''),
        'build_type='||coalesce(btrim(row->>'build_type'),''),
        'delivery_partner='||coalesce(btrim(row->>'delivery_partner'),''),
        'fod_id='||coalesce(btrim(row->>'fod_id'),''),
        'premises_count='||coalesce(btrim(row->>'premises_count'),''),
        'residential='||coalesce(btrim(row->>'residential'),''),
        'commercial='||coalesce(btrim(row->>'commercial'),''),
        'essential='||coalesce(btrim(row->>'essential'),''),
        'developer_class='||coalesce(btrim(row->>'developer_class'),''),
        'latitude='||coalesce(btrim(row->>'latitude'),''),
        'longitude='||coalesce(btrim(row->>'longitude'),''),
        'relationship_manager='||coalesce(btrim(row->>'relationship_manager'),''),
        'deployment_specialist='||coalesce(btrim(row->>'deployment_specialist'),''),
        'stage_application_created='||coalesce(btrim(row->>'stage_application_created'),''),
        'developer_design_submitted='||coalesce(btrim(row->>'developer_design_submitted'),''),
        'developer_design_accepted='||coalesce(btrim(row->>'developer_design_accepted'),''),
        'issued_to_delivery_partner='||coalesce(btrim(row->>'issued_to_delivery_partner'),''),
        'practical_completion_notified='||coalesce(btrim(row->>'practical_completion_notified'),''),
        'practical_completion_certified='||coalesce(btrim(row->>'practical_completion_certified'),''),
        'delivery_partner_pc_sub='||coalesce(btrim(row->>'delivery_partner_pc_sub'),''),
        'in_service='||coalesce(btrim(row->>'in_service'),'')
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

-- ========== 2) Core merge RPC: align with new fields and dev_type derivation ==========
-- Signature unchanged; returns projects_import_merge_result
-- Volatility/security unchanged (plpgsql, invoker).
-- Behavior:
--  - Parse new fields (address/suburb/state/build_type/fod_id, counts, lat/long, practical_completion_notified)
--  - Stop reading rm_preferred_username (set to null; do not write)
--  - Derive development_type from residential/commercial per Section 8.D
--  - Insert and upsert with COALESCE-preserving semantics for nullable fields; counts (including zeros) overwrite
--  - Post-merge recompute unchanged
-- References:
--  - Section 8.D Merge and compute functions (SQL)
--  - Task 4 consolidated list

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
  v_rm_preferred_username text; -- deprecated; intentionally left for compatibility but not used
  v_ds_username text;
  v_partner_org_id uuid;
  v_ds_user_id uuid;
  v_rm_user_id uuid;
  v_project_id uuid;
  v_inserted boolean;
  v_sac timestamptz;
  v_batch_checksum text;

  -- Stage 5 dates (existing)
  v_efscd date;
  v_dds date;
  v_dda date;
  v_issued date;
  v_pcc date;
  v_dp_pc_sub date;
  v_in_service date;

  -- NEW: Stage 6 fields
  v_address text;
  v_suburb text;
  v_state text;
  v_build_type text;
  v_fod_id text;

  v_premises_count int;
  v_residential int;
  v_commercial int;
  v_essential int;

  v_latitude numeric;
  v_longitude numeric;
  v_practical_completion_notified date;

  -- Derived
  v_development_type text;

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

  -- Locate staging row by (tenant_id, batch_checksum) computed from rows (checksum helper updated in Task 4)
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
    v_rm_preferred_username := null; -- Task 4: cease reading; do not write or use for lookup
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

    -- Stage 5 date fields (normalize to date; tolerate datetime)
    v_efscd := null; v_dds := null; v_dda := null; v_issued := null; v_pcc := null; v_dp_pc_sub := null; v_in_service := null;
    begin if nullif(btrim(coalesce(v_row->>'eFscd','')), '') is not null then v_efscd := (v_row->>'eFscd')::timestamptz::date; end if; exception when others then v_efscd := null; end;
    begin if nullif(btrim(coalesce(v_row->>'developer_design_submitted','')), '') is not null then v_dds := (v_row->>'developer_design_submitted')::timestamptz::date; end if; exception when others then v_dds := null; end;
    begin if nullif(btrim(coalesce(v_row->>'developer_design_accepted','')), '') is not null then v_dda := (v_row->>'developer_design_accepted')::timestamptz::date; end if; exception when others then v_dda := null; end;
    begin if nullif(btrim(coalesce(v_row->>'issued_to_delivery_partner','')), '') is not null then v_issued := (v_row->>'issued_to_delivery_partner')::timestamptz::date; end if; exception when others then v_issued := null; end;
    begin if nullif(btrim(coalesce(v_row->>'practical_completion_certified','')), '') is not null then v_pcc := (v_row->>'practical_completion_certified')::timestamptz::date; end if; exception when others then v_pcc := null; end;
    begin if nullif(btrim(coalesce(v_row->>'delivery_partner_pc_sub','')), '') is not null then v_dp_pc_sub := (v_row->>'delivery_partner_pc_sub')::timestamptz::date; end if; exception when others then v_dp_pc_sub := null; end;
    begin if nullif(btrim(coalesce(v_row->>'in_service','')), '') is not null then v_in_service := (v_row->>'in_service')::timestamptz::date; end if; exception when others then v_in_service := null; end;

    -- NEW: Stage 6 parsing
    v_address := nullif(btrim(coalesce(v_row->>'address','')), '');
    v_suburb := nullif(btrim(coalesce(v_row->>'suburb','')), '');
    v_state := nullif(btrim(coalesce(v_row->>'state','')), '');
    v_build_type := nullif(btrim(coalesce(v_row->>'build_type','')), '');
    v_fod_id := nullif(btrim(coalesce(v_row->>'fod_id','')), '');

    -- Integers: coerce negatives to 0; blanks/invalid -> 0
    v_premises_count := 0;
    begin
      if nullif(btrim(coalesce(v_row->>'premises_count','')), '') is not null then
        v_premises_count := greatest(0, (v_row->>'premises_count')::int);
      end if;
    exception when others then
      v_premises_count := 0;
    end;

    v_residential := 0;
    begin
      if nullif(btrim(coalesce(v_row->>'residential','')), '') is not null then
        v_residential := greatest(0, (v_row->>'residential')::int);
      end if;
    exception when others then
      v_residential := 0;
    end;

    v_commercial := 0;
    begin
      if nullif(btrim(coalesce(v_row->>'commercial','')), '') is not null then
        v_commercial := greatest(0, (v_row->>'commercial')::int);
      end if;
    exception when others then
      v_commercial := 0;
    end;

    v_essential := 0;
    begin
      if nullif(btrim(coalesce(v_row->>'essential','')), '') is not null then
        v_essential := greatest(0, (v_row->>'essential')::int);
      end if;
    exception when others then
      v_essential := 0;
    end;

    -- Numerics: blanks/invalid -> null
    v_latitude := null;
    begin
      if nullif(btrim(coalesce(v_row->>'latitude','')), '') is not null then
        v_latitude := (v_row->>'latitude')::numeric;
      end if;
    exception when others then
      v_latitude := null;
    end;

    v_longitude := null;
    begin
      if nullif(btrim(coalesce(v_row->>'longitude','')), '') is not null then
        v_longitude := (v_row->>'longitude')::numeric;
      end if;
    exception when others then
      v_longitude := null;
    end;

    -- Date: practical_completion_notified (timezone discarded)
    v_practical_completion_notified := null;
    begin
      if nullif(btrim(coalesce(v_row->>'practical_completion_notified','')), '') is not null then
        v_practical_completion_notified := (v_row->>'practical_completion_notified')::timestamptz::date;
      end if;
    exception when others then
      v_practical_completion_notified := null;
    end;

    -- Derived development_type per Task 4
    v_development_type := case
      when coalesce(v_residential,0) > 0 and coalesce(v_commercial,0) > 0 then 'Mixed Use'
      when coalesce(v_residential,0) > 0 and coalesce(v_commercial,0) = 0 then 'Residential'
      when coalesce(v_commercial,0) > 0 and coalesce(v_residential,0) = 0 then 'Commercial'
      else null
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

    -- Task 4: RM lookup only by display_name (rm_preferred_username deprecated)
    v_rm_user_id := null;
    if coalesce(v_rm_name,'') <> '' then
      v_rm_user_id := public.fn_find_rm_user_id(v_rm_name, null);
      if v_rm_user_id is null then
        insert into public.import_anomalies(tenant_id, staging_id, batch_id, row_index, anomaly_type, field, input_value, reason, match_type, project_key, correlation_id)
        values (
          p_tenant_id, v_staging_id, p_batch_id, v_idx + 1,
          'UNKNOWN_RM',
          'relationship_manager',
          v_rm_name,
          'No active RM directory match',
          'display_name',
          v_stage_application, p_correlation_id
        );
        c_anomalies := c_anomalies + 1;
      end if;
    end if;

    -- Upsert project by (tenant_id, stage_application) including new fields
    with up as (
      insert into public.projects(
        tenant_id, stage_application, stage_application_created,
        efscd, developer_design_submitted, developer_design_accepted,
        issued_to_delivery_partner, practical_completion_notified, practical_completion_certified, delivery_partner_pc_sub, in_service,
        address, suburb, state, build_type, fod_id,
        premises_count, residential, commercial, essential,
        latitude, longitude,
        delivery_partner_label, partner_org_id, developer_class,
        deployment_specialist, relationship_manager,
        development_type
      )
      values (
        p_tenant_id, v_stage_application, v_sac,
        v_efscd, v_dds, v_dda,
        v_issued, v_practical_completion_notified, v_pcc, v_dp_pc_sub, v_in_service,
        v_address, v_suburb, v_state, v_build_type, v_fod_id,
        v_premises_count, v_residential, v_commercial, v_essential,
        v_latitude, v_longitude,
        nullif(v_dp_label,''), v_partner_org_id, v_dev_class,
        nullif(v_ds_username,''), nullif(v_rm_name,''),
        v_development_type
      )
      on conflict (tenant_id, stage_application) do update
      set
        -- Membership-affecting and identifiers: overwrite to reflect current payload
        delivery_partner_label = excluded.delivery_partner_label,
        partner_org_id = excluded.partner_org_id,
        developer_class = excluded.developer_class,
        deployment_specialist = excluded.deployment_specialist,
        relationship_manager = excluded.relationship_manager,

        -- Dates: COALESCE-preserving (avoid null overwrites)
        stage_application_created = coalesce(excluded.stage_application_created, public.projects.stage_application_created),
        efscd = coalesce(excluded.efscd, public.projects.efscd),
        developer_design_submitted = coalesce(excluded.developer_design_submitted, public.projects.developer_design_submitted),
        developer_design_accepted = coalesce(excluded.developer_design_accepted, public.projects.developer_design_accepted),
        issued_to_delivery_partner = coalesce(excluded.issued_to_delivery_partner, public.projects.issued_to_delivery_partner),
        practical_completion_notified = coalesce(excluded.practical_completion_notified, public.projects.practical_completion_notified),
        practical_completion_certified = coalesce(excluded.practical_completion_certified, public.projects.practical_completion_certified),
        delivery_partner_pc_sub = coalesce(excluded.delivery_partner_pc_sub, public.projects.delivery_partner_pc_sub),
        in_service = coalesce(excluded.in_service, public.projects.in_service),

        -- NEW strings: COALESCE-preserving
        address = coalesce(excluded.address, public.projects.address),
        suburb = coalesce(excluded.suburb, public.projects.suburb),
        state = coalesce(excluded.state, public.projects.state),
        build_type = coalesce(excluded.build_type, public.projects.build_type),
        fod_id = coalesce(excluded.fod_id, public.projects.fod_id),

        -- NEW counts: zeros overwrite as real values
        premises_count = excluded.premises_count,
        residential = excluded.residential,
        commercial = excluded.commercial,
        essential = excluded.essential,

        -- NEW numerics: COALESCE-preserving
        latitude = coalesce(excluded.latitude, public.projects.latitude),
        longitude = coalesce(excluded.longitude, public.projects.longitude),

        -- Derived: always overwrite to reflect current counts
        development_type = excluded.development_type
      returning id, (xmax = 0) as inserted
    )
    select id, inserted into v_project_id, v_inserted from up;

    if v_inserted then
      c_inserted := c_inserted + 1;
    else
      c_updated := c_updated + 1;
    end if;

    -- Reconcile memberships (unchanged)
    -- ORG membership
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

  -- Post-merge recompute of derived status for affected projects in this staging batch (unchanged)
  perform public.fn_projects_derived_status_recompute_by_staging(v_staging_id);

  return (c_inserted, c_updated, c_org_upserts, c_user_upserts, c_anomalies, v_staging_id);
end;
$fn$;