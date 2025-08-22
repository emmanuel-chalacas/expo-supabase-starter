-- Stage 7: Projects list RPC for PRD-compliant sorting with keyset pagination and search
create or replace function public.rpc_projects_list(
  p_search text default null,
  p_status text[] default null,
  p_dev_types text[] default null,
  p_build_types text[] default null,
  p_cursor_sort_ts timestamptz default null,
  p_cursor_id uuid default null,
  p_limit int default 25
)
returns table (
  id uuid,
  stage_application text,
  stage_application_created timestamptz,
  derived_status text,
  developer_class text,
  partner_org_name text,
  address text,
  suburb text,
  state text,
  development_type text,
  build_type text,
  sort_ts timestamptz
)
language sql
security invoker
as $$
  with base as (
    select
      p.id,
      p.stage_application,
      p.stage_application_created,
      p.derived_status,
      p.developer_class,
      po.name as partner_org_name,
      p.address, p.suburb, p.state,
      p.development_type, p.build_type,
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
    left join public.partner_org po on po.id = p.partner_org_id
  ),
  filtered as (
    select * from base
    where
      (p_status is null or array_length(p_status,1) is null or derived_status = any(p_status))
      and (p_dev_types is null or array_length(p_dev_types,1) is null or development_type = any(p_dev_types))
      and (p_build_types is null or array_length(p_build_types,1) is null or build_type = any(p_build_types))
      and (
        p_search is null
        or length(btrim(p_search)) = 0
        or (
          stage_application ilike ('%' || p_search || '%')
          or address ilike ('%' || p_search || '%')
          or suburb ilike ('%' || p_search || '%')
          or state ilike ('%' || p_search || '%')
        )
      )
  ),
  paged as (
    select * from filtered
    where
      (p_cursor_sort_ts is null and p_cursor_id is null)
      or (
        sort_ts < p_cursor_sort_ts
        or (sort_ts = p_cursor_sort_ts and id < p_cursor_id)
        or (p_cursor_sort_ts is not null and sort_ts is null) -- allow paging into NULL sort_ts after non-NULL pages
      )
    order by sort_ts desc nulls last, id desc
    limit greatest(1, p_limit)
  )
  select
    id, stage_application, stage_application_created, derived_status, developer_class, partner_org_name,
    address, suburb, state, development_type, build_type, sort_ts
  from paged
$$;

comment on function public.rpc_projects_list(text, text[], text[], text[], timestamptz, uuid, int)
is 'Projects list with PRD-compliant default sort (stage_application_created DESC, fallback to latest key date), filters, search across stage_application/address/suburb/state, and keyset pagination. Security INVOKER so RLS on public.projects applies.';

grant execute on function public.rpc_projects_list(text, text[], text[], text[], timestamptz, uuid, int) to authenticated;