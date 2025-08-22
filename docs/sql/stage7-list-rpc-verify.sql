-- Omnivia — Stage 7 Verification SQL (rpc_projects_list)
-- Purpose:
--   Deterministically verify ordering, fallback logic, keyset cursor exclusivity, filters, and search
--   against [public.rpc_projects_list](supabase/migrations/20250820220000_stage7_projects_list_rpc.sql:1).
-- Style:
--   - Follows Stage 5/6 verify scripts style: single-run, deterministic assertions, emits label + pass + details.
--   - All DML wrapped in a transaction and rolled back at the end (database remains unchanged).
-- Usage:
--   supabase db execute --file docs/sql/stage7-list-rpc-verify.sql

begin;

-- Ensure a recognizable partner org exists for LEFT JOIN coverage in the RPC (rolled back at end)
do $$
begin
  if not exists (
    select 1 from public.partner_org where lower(trim(name)) = 'verify dp'
  ) then
    insert into public.partner_org(name) values ('Verify DP');
  end if;
end$$;

-- Seed an isolated, deterministic set of 8 projects under a dedicated tenant_id
-- Notes:
-- - Two rows share identical sort_ts via stage_application_created to validate id DESC tie‑break.
-- - One row has all key dates NULL to validate nulls last.
-- - Each fallback participant date appears at least once across the dataset; efscd is explicitly asserted.
-- - Addresses/suburbs/states include unique markers to exercise search across address fields.
with upsert as (
  select
    (select id from public.partner_org where lower(trim(name))='verify dp' limit 1) as dp_id
),
ins as (
  -- A) SAC present (topmost)
  insert into public.projects (
    id, tenant_id, stage_application, stage_application_created,
    efscd, developer_design_submitted, developer_design_accepted,
    issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
    partner_org_id, address, suburb, state, development_type, build_type
  ) values (
    '00000000-0000-0000-0000-00000000a008', 'S7V', 'S7V-SAC-A', '2099-12-31 09:00:00+10:30',
    null, null, null,
    null, null, null, null,
    (select dp_id from upsert), 'S7V-ADDR-A-UNIQ 1 Alpha Street', 'AlphaVille', 'SA', 'Greenfields', 'FTTP'
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_submitted = excluded.developer_design_submitted,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified,
      delivery_partner_pc_sub = excluded.delivery_partner_pc_sub,
      in_service = excluded.in_service,
      partner_org_id = excluded.partner_org_id,
      address = excluded.address,
      suburb = excluded.suburb,
      state = excluded.state,
      development_type = excluded.development_type,
      build_type = excluded.build_type
  returning 1
), ins_b as (
  -- B) efscd present (fallback participant we assert explicitly)
  insert into public.projects (
    id, tenant_id, stage_application, stage_application_created,
    efscd, developer_design_submitted, developer_design_accepted,
    issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
    partner_org_id, address, suburb, state, development_type, build_type
  ) values (
    '00000000-0000-0000-0000-00000000a007', 'S7V', 'S7V-EFSCD', null,
    '2099-12-31', null, null,
    null, null, null, null,
    (select dp_id from upsert), '2 Beta Road', 'Betatown', 'VIC', 'Greenfields', 'FTTP'
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_submitted = excluded.developer_design_submitted,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified,
      delivery_partner_pc_sub = excluded.delivery_partner_pc_sub,
      in_service = excluded.in_service,
      partner_org_id = excluded.partner_org_id,
      address = excluded.address,
      suburb = excluded.suburb,
      state = excluded.state,
      development_type = excluded.development_type,
      build_type = excluded.build_type
  returning 1
), ins_c as (
  -- C) developer_design_submitted present
  insert into public.projects (
    id, tenant_id, stage_application, stage_application_created,
    efscd, developer_design_submitted, developer_design_accepted,
    issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
    partner_org_id, address, suburb, state, development_type, build_type
  ) values (
    '00000000-0000-0000-0000-00000000a006', 'S7V', 'S7V-DDS', null,
    null, '2099-12-30', null,
    null, null, null, null,
    (select dp_id from upsert), 'S7V-ADDR-B-UNIQ 99 Verify Road', 'Betatown', 'VIC', 'Brownfields', 'HFC'
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_submitted = excluded.developer_design_submitted,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified,
      delivery_partner_pc_sub = excluded.delivery_partner_pc_sub,
      in_service = excluded.in_service,
      partner_org_id = excluded.partner_org_id,
      address = excluded.address,
      suburb = excluded.suburb,
      state = excluded.state,
      development_type = excluded.development_type,
      build_type = excluded.build_type
  returning 1
), ins_d as (
  -- D) TIE #1: same SAC as E) to validate id DESC tie-break; also has delivery_partner_pc_sub present
  insert into public.projects (
    id, tenant_id, stage_application, stage_application_created,
    efscd, developer_design_submitted, developer_design_accepted,
    issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
    partner_org_id, address, suburb, state, development_type, build_type
  ) values (
    '00000000-0000-0000-0000-00000000a001', 'S7V', 'S7V-TIE1', '2099-12-29 10:15:00+10:30',
    null, null, null,
    null, null, '2099-12-28', null,
    (select dp_id from upsert), '3 Gamma Ave', 'Gammaville', 'NSW', 'Greenfields', 'FTTN'
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_submitted = excluded.developer_design_submitted,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified,
      delivery_partner_pc_sub = excluded.delivery_partner_pc_sub,
      in_service = excluded.in_service,
      partner_org_id = excluded.partner_org_id,
      address = excluded.address,
      suburb = excluded.suburb,
      state = excluded.state,
      development_type = excluded.development_type,
      build_type = excluded.build_type
  returning 1
), ins_e as (
  -- E) TIE #2: same SAC as D) to validate id DESC tie-break; also has practical_completion_certified present
  insert into public.projects (
    id, tenant_id, stage_application, stage_application_created,
    efscd, developer_design_submitted, developer_design_accepted,
    issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
    partner_org_id, address, suburb, state, development_type, build_type
  ) values (
    '00000000-0000-0000-0000-00000000a002', 'S7V', 'S7V-TIE2', '2099-12-29 10:15:00+10:30',
    null, null, null,
    null, '2099-12-27', null, null,
    (select dp_id from upsert), '4 Delta Blvd', 'Deltatown', 'QLD', 'Mixed', 'FTTP'
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_submitted = excluded.developer_design_submitted,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified,
      delivery_partner_pc_sub = excluded.delivery_partner_pc_sub,
      in_service = excluded.in_service,
      partner_org_id = excluded.partner_org_id,
      address = excluded.address,
      suburb = excluded.suburb,
      state = excluded.state,
      development_type = excluded.development_type,
      build_type = excluded.build_type
  returning 1
), ins_f as (
  -- F) issued_to_delivery_partner present (and in_service present to include this key for completeness)
  insert into public.projects (
    id, tenant_id, stage_application, stage_application_created,
    efscd, developer_design_submitted, developer_design_accepted,
    issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
    partner_org_id, address, suburb, state, development_type, build_type
  ) values (
    '00000000-0000-0000-0000-00000000a005', 'S7V', 'S7V-ISS', null,
    null, null, null,
    '2099-12-28', null, null, '2099-12-28',
    (select dp_id from upsert), '5 Epsilon Way', 'Epsilon', 'WA', 'Greenfields', 'HFC'
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_submitted = excluded.developer_design_submitted,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified,
      delivery_partner_pc_sub = excluded.delivery_partner_pc_sub,
      in_service = excluded.in_service,
      partner_org_id = excluded.partner_org_id,
      address = excluded.address,
      suburb = excluded.suburb,
      state = excluded.state,
      development_type = excluded.development_type,
      build_type = excluded.build_type
  returning 1
), ins_g as (
  -- G) All key dates null (verifies NULL sort_ts appears last via nulls last)
  insert into public.projects (
    id, tenant_id, stage_application, stage_application_created,
    efscd, developer_design_submitted, developer_design_accepted,
    issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
    partner_org_id, address, suburb, state, development_type, build_type
  ) values (
    '00000000-0000-0000-0000-00000000a004', 'S7V', 'S7V-NULLS', null,
    null, null, null,
    null, null, null, null,
    (select dp_id from upsert), '6 Zeta Close', 'Zetaville', 'SA', 'Brownfields', 'HFC'
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_submitted = excluded.developer_design_submitted,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified,
      delivery_partner_pc_sub = excluded.delivery_partner_pc_sub,
      in_service = excluded.in_service,
      partner_org_id = excluded.partner_org_id,
      address = excluded.address,
      suburb = excluded.suburb,
      state = excluded.state,
      development_type = excluded.development_type,
      build_type = excluded.build_type
  returning 1
), ins_h as (
  -- H) developer_design_accepted present
  insert into public.projects (
    id, tenant_id, stage_application, stage_application_created,
    efscd, developer_design_submitted, developer_design_accepted,
    issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service,
    partner_org_id, address, suburb, state, development_type, build_type
  ) values (
    '00000000-0000-0000-0000-00000000a003', 'S7V', 'S7V-DDA', null,
    null, null, '2099-12-27',
    null, null, null, null,
    (select dp_id from upsert), '7 Theta Rd', 'Thetatown', 'NT', 'Mixed', 'FTTB'
  )
  on conflict (tenant_id, stage_application) do update
  set stage_application_created = excluded.stage_application_created,
      efscd = excluded.efscd,
      developer_design_submitted = excluded.developer_design_submitted,
      developer_design_accepted = excluded.developer_design_accepted,
      issued_to_delivery_partner = excluded.issued_to_delivery_partner,
      practical_completion_certified = excluded.practical_completion_certified,
      delivery_partner_pc_sub = excluded.delivery_partner_pc_sub,
      in_service = excluded.in_service,
      partner_org_id = excluded.partner_org_id,
      address = excluded.address,
      suburb = excluded.suburb,
      state = excluded.state,
      development_type = excluded.development_type,
      build_type = excluded.build_type
  returning 1
)
select 1;

-- Deterministic statuses for filter assertions (bypass trigger by only updating derived_status)
update public.projects
set derived_status = 'Complete'
where tenant_id='S7V' and stage_application in ('S7V-EFSCD','S7V-TIE2');

update public.projects
set derived_status = 'In Progress'
where tenant_id='S7V' and stage_application in ('S7V-SAC-A','S7V-DDS','S7V-TIE1','S7V-ISS','S7V-DDA');

-- Assertions
with
params as (
  select 'S7V'::text as q, 3::int as n, 100::int as big_n
),
expected_base as (
  select
    p.id,
    p.stage_application,
    coalesce(
      p.stage_application_created,
      greatest(
        p.efscd::timestamptz,
        p.developer_design_submitted::timestamptz,
        p.developer_design_accepted::timestamptz,
        p.issued_to_delivery_partner::timestamptz,
        p.practical_completion_certified::timestamptz,
        p.delivery_partner_pc_sub::timestamptz,
        p.in_service::timestamptz
      )
    ) as sort_ts
  from public.projects p
  where p.stage_application like 'S7V-%'
),
expected_order as (
  select id, stage_application, sort_ts
  from expected_base
  order by sort_ts desc nulls last, id desc
),
expected_top3 as (
  select array_agg(id) as ids
  from (select id from expected_order limit 3) s
),
expected_top6 as (
  select array_agg(id) as ids
  from (select id from expected_order limit 6) s
),
rpc_page1 as (
  select *
  from public.rpc_projects_list(
    (select q from params),
    null, null, null,
    null, null,
    (select n from params)
  )
),
rpc_page1_ord as (
  select id, stage_application, sort_ts
  from rpc_page1
  order by sort_ts desc nulls last, id desc
),
rpc_page1_ids as (
  select array_agg(id) as ids from rpc_page1_ord
),
boundary as (
  select id as last_id, sort_ts as last_sort_ts
  from rpc_page1_ord
  order by sort_ts desc nulls last, id desc
  offset 2 limit 1
),
rpc_page2 as (
  select *
  from public.rpc_projects_list(
    (select q from params),
    null, null, null,
    (select last_sort_ts from boundary),
    (select last_id from boundary),
    (select n from params)
  )
),
rpc_page2_ord as (
  select id, stage_application, sort_ts
  from rpc_page2
  order by sort_ts desc nulls last, id desc
),
rpc_page2_ids as (
  select array_agg(id) as ids from rpc_page2_ord
),
rpc_union_6 as (
  select
    (select ids from rpc_page1_ids) || (select ids from rpc_page2_ids) as ids
),
rpc_all as (
  select *
  from public.rpc_projects_list(
    (select q from params),
    null, null, null,
    null, null,
    (select big_n from params)
  )
),
rpc_all_ord as (
  select id, stage_application, sort_ts
  from rpc_all
  order by sort_ts desc nulls last, id desc
),
rpc_all_ids as (
  select array_agg(id) as ids from rpc_all_ord
),
rpc_all_last_id as (
  select (ids)[array_length(ids,1)] as id
  from rpc_all_ids
),
assert_default_order_top3 as (
  select
    'default ordering: page 1 (limit 3) matches expected id order'::text as label,
    ((select ids from rpc_page1_ids) = (select ids from expected_top3)) as pass,
    concat('got=', (select ids from rpc_page1_ids), ' expected=', (select ids from expected_top3)) as details
),
assert_nulls_last as (
  select
    'default ordering: null sort_ts rows ordered last (includes S7V-NULLS)'::text as label,
    exists (
      select 1
      from rpc_all_ord a
      join rpc_all_last_id l on l.id = a.id
      where a.stage_application = 'S7V-NULLS'
    ) as pass,
    concat('last_id=', (select id from rpc_all_last_id)) as details
),
assert_cursor_exclusive as (
  select
    'cursor exclusivity: page 2 excludes page 1 boundary item'::text as label,
    not exists (
      select 1 from rpc_page2_ord
      where id = (select last_id from boundary)
    ) as pass,
    concat('boundary_id=', (select last_id from boundary)) as details
),
assert_union_equals_top6 as (
  select
    'cursor paging: page1 ∪ page2 equals top 2N of unbounded ordered call'::text as label,
    ((select ids from rpc_union_6) = (select ids from expected_top6)) as pass,
    concat('union=', (select ids from rpc_union_6), ' expected=', (select ids from expected_top6)) as details
),
-- Filters
expected_complete as (
  select count(*)::int as cnt
  from public.projects
  where stage_application like 'S7V-%' and derived_status = 'Complete'
),
rpc_complete as (
  select count(*)::int as cnt
  from public.rpc_projects_list(
    (select q from params),
    array['Complete']::text[], null, null,
    null, null, (select big_n from params)
  )
),
assert_filter_status as (
  select
    'filters: derived_status=Complete returns only seeded rows with that status'::text as label,
    (
      (select cnt from rpc_complete) = (select cnt from expected_complete)
      and not exists (
        select 1
        from public.rpc_projects_list(
          (select q from params),
          array['Complete']::text[], null, null,
          null, null, (select big_n from params)
        ) r
        where not (r.stage_application like 'S7V-%' and r.derived_status = 'Complete')
      )
    ) as pass,
    concat('rpc_count=', (select cnt from rpc_complete), ' expected_count=', (select cnt from expected_complete)) as details
),
expected_devtype as (
  select count(*)::int as cnt
  from public.projects
  where stage_application like 'S7V-%' and development_type = 'Brownfields'
),
rpc_devtype as (
  select count(*)::int as cnt
  from public.rpc_projects_list(
    (select q from params),
    null, array['Brownfields']::text[], null,
    null, null, (select big_n from params)
  )
),
assert_filter_devtype as (
  select
    'filters: development_type=Brownfields returns only matching seeded rows'::text as label,
    (
      (select cnt from rpc_devtype) = (select cnt from expected_devtype)
      and not exists (
        select 1
        from public.rpc_projects_list(
          (select q from params),
          null, array['Brownfields']::text[], null,
          null, null, (select big_n from params)
        ) r
        where not (r.stage_application like 'S7V-%' and r.development_type = 'Brownfields')
      )
    ) as pass,
    concat('rpc_count=', (select cnt from rpc_devtype), ' expected_count=', (select cnt from expected_devtype)) as details
),
expected_buildtype as (
  select count(*)::int as cnt
  from public.projects
  where stage_application like 'S7V-%' and build_type = 'HFC'
),
rpc_buildtype as (
  select count(*)::int as cnt
  from public.rpc_projects_list(
    (select q from params),
    null, null, array['HFC']::text[],
    null, null, (select big_n from params)
  )
),
assert_filter_buildtype as (
  select
    'filters: build_type=HFC returns only matching seeded rows'::text as label,
    (
      (select cnt from rpc_buildtype) = (select cnt from expected_buildtype)
      and not exists (
        select 1
        from public.rpc_projects_list(
          (select q from params),
          null, null, array['HFC']::text[],
          null, null, (select big_n from params)
        ) r
        where not (r.stage_application like 'S7V-%' and r.build_type = 'HFC')
      )
    ) as pass,
    concat('rpc_count=', (select cnt from rpc_buildtype), ' expected_count=', (select cnt from expected_buildtype)) as details
),
-- Search
rpc_search_stageapp as (
  select array_agg(stage_application) as sapps
  from public.rpc_projects_list(
    'SAC-A', -- substring of stage_application
    null, null, null,
    null, null, (select big_n from params)
  )
  where stage_application like 'S7V-%'
),
assert_search_stageapp as (
  select
    'search: substring of stage_application returns matching seeded rows'::text as label,
    (
      (select coalesce(array_length(sapps,1),0) from rpc_search_stageapp) >= 1
      and not exists (
        select 1
        from public.rpc_projects_list(
          'SAC-A', null, null, null, null, null, (select big_n from params)
        ) r
        where r.stage_application like 'S7V-%' and r.stage_application not ilike '%SAC-A%'
      )
    ) as pass,
    concat('matches=', coalesce((select array_length(sapps,1) from rpc_search_stageapp),0)) as details
),
rpc_search_address as (
  select array_agg(stage_application) as sapps
  from public.rpc_projects_list(
    'ADDR-B-UNIQ', -- substring only present in address of S7V-DDS
    null, null, null,
    null, null, (select big_n from params)
  )
  where stage_application like 'S7V-%'
),
assert_search_address as (
  select
    'search: substring of address/suburb/state returns matching seeded rows'::text as label,
    (
      (select coalesce(array_length(sapps,1),0) from rpc_search_address) >= 1
      and exists (
        select 1
        from public.rpc_projects_list(
          'ADDR-B-UNIQ', null, null, null, null, null, (select big_n from params)
        ) r
        where r.stage_application = 'S7V-DDS'
      )
    ) as pass,
    concat('matches=', coalesce((select array_length(sapps,1) from rpc_search_address),0)) as details
),
-- Fallback: confirm efscd participates in greatest() when SAC is null
efscd_row as (
  select p.id, p.efscd::timestamptz as expected_ts
  from public.projects p
  where p.tenant_id='S7V' and p.stage_application='S7V-EFSCD'
),
rpc_efscd as (
  select r.id, r.sort_ts
  from public.rpc_projects_list(
    'S7V', null, null, null, null, null, (select big_n from params)
  ) r
  where r.stage_application='S7V-EFSCD'
),
assert_fallback_efscd as (
  select
    'fallback: efscd participates in sort_ts greatest() when SAC is null'::text as label,
    (select expected_ts from efscd_row) = (select sort_ts from rpc_efscd) as pass,
    concat('expected=', (select expected_ts from efscd_row), ' got=', (select sort_ts from rpc_efscd)) as details
),
-- Security note: INVOKER (RLS applies) informational PASS
sec_invoker as (
  select
    'note: rpc_projects_list is SECURITY INVOKER (RLS applies)'::text as label,
    exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'rpc_projects_list'
        and p.prosecdef = false
    ) as pass,
    null::text as details
),
summary as (
  select * from assert_default_order_top3
  union all select * from assert_nulls_last
  union all select * from assert_cursor_exclusive
  union all select * from assert_union_equals_top6
  union all select * from assert_filter_status
  union all select * from assert_filter_devtype
  union all select * from assert_filter_buildtype
  union all select * from assert_search_stageapp
  union all select * from assert_search_address
  union all select * from assert_fallback_efscd
  union all select * from sec_invoker
)
select label, case when pass then true else false end as pass, details
from summary
order by label;

rollback;