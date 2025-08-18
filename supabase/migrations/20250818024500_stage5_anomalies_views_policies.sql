-- Omnivia — Stage 5: Anomalies views and secure RPCs
-- Ref: Critical item 5 — docs/product/projects-okta-rbac-stage1-4-audit.md
-- Notes:
--  - Read-only views for recent anomalies and 24h stats
--  - SECURITY DEFINER RPCs gated by operator/admin in public.user_roles
--  - No raw payloads exposed; only a 500-char excerpt of the specific row

-- View: recent anomalies (last 14 days), include payload_excerpt and source
create or replace view public.vw_import_anomalies_recent as
select
  a.id,
  a.created_at,
  a.tenant_id,
  a.staging_id,
  a.batch_id,
  a.row_index,
  a.anomaly_type,
  a.field,
  a.input_value,
  a.reason,
  a.match_type,
  a.project_key,
  a.correlation_id,
  s.source,
  left(coalesce(((s.raw -> greatest(a.row_index - 1,0))::text), ''), 500) as payload_excerpt,
  case a.anomaly_type
    when 'UNKNOWN_DS' then 'error'
    when 'UNKNOWN_RM' then 'error'
    when 'UNKNOWN_DELIVERY_PARTNER' then 'warning'
    else 'info'
  end as severity
from public.import_anomalies a
join public.staging_imports s on s.id = a.staging_id
where a.created_at >= now() - interval '14 days';

-- Stats view: last 24h aggregated by tenant, category, severity
create or replace view public.vw_import_anomalies_stats_24h as
with base as (
  select
    a.tenant_id,
    a.anomaly_type as category,
    case a.anomaly_type
      when 'UNKNOWN_DS' then 'error'
      when 'UNKNOWN_RM' then 'error'
      when 'UNKNOWN_DELIVERY_PARTNER' then 'warning'
      else 'info'
    end as severity,
    a.created_at
  from public.import_anomalies a
  where a.created_at >= now() - interval '24 hours'
)
select
  tenant_id,
  category,
  severity,
  count(*)::int as count,
  max(created_at) as most_recent
from base
group by tenant_id, category, severity
order by count desc;

-- Secure RPC: rows for operator
create or replace function public.fn_anomalies_for_operator(
  p_window_hours int default 24,
  p_tenant text default null,
  p_severity text[] default null
)
returns table (
  id uuid,
  created_at timestamptz,
  tenant_id text,
  staging_id uuid,
  batch_id text,
  row_index integer,
  anomaly_type text,
  field text,
  input_value text,
  reason text,
  match_type text,
  project_key text,
  correlation_id uuid,
  source text,
  payload_excerpt text,
  severity text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_ok boolean;
begin
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role in ('admin','operator')
  ) into v_role_ok;

  if not v_role_ok then
    raise insufficient_privilege using message 'operator/admin role required';
  end if;

  return query
  select
    a.id,
    a.created_at,
    a.tenant_id,
    a.staging_id,
    a.batch_id,
    a.row_index,
    a.anomaly_type,
    a.field,
    a.input_value,
    a.reason,
    a.match_type,
    a.project_key,
    a.correlation_id,
    s.source as source,
    left(coalesce(((s.raw -> greatest(a.row_index - 1,0))::text), ''), 500) as payload_excerpt,
    case a.anomaly_type
      when 'UNKNOWN_DS' then 'error'
      when 'UNKNOWN_RM' then 'error'
      when 'UNKNOWN_DELIVERY_PARTNER' then 'warning'
      else 'info'
    end as severity
  from public.import_anomalies a
  join public.staging_imports s on s.id = a.staging_id
  where a.created_at >= now() - (interval '1 hour' * greatest(p_window_hours, 0))
    and (p_tenant is null or a.tenant_id = p_tenant)
    and (
      p_severity is null
      or array_length(p_severity,1) is null
      or (case a.anomaly_type
            when 'UNKNOWN_DS' then 'error'
            when 'UNKNOWN_RM' then 'error'
            when 'UNKNOWN_DELIVERY_PARTNER' then 'warning'
            else 'info'
          end) = any(p_severity)
    )
  order by a.created_at desc;
end;
$$;

-- Secure RPC: stats for operator
create or replace function public.fn_anomalies_stats(
  p_window_hours int default 24
)
returns table (
  tenant_id text,
  category text,
  severity text,
  count integer,
  most_recent timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_ok boolean;
begin
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role in ('admin','operator')
  ) into v_role_ok;

  if not v_role_ok then
    raise insufficient_privilege using message 'operator/admin role required';
  end if;

  return query
  with base as (
    select
      a.tenant_id,
      a.anomaly_type as category,
      case a.anomaly_type
        when 'UNKNOWN_DS' then 'error'
        when 'UNKNOWN_RM' then 'error'
        when 'UNKNOWN_DELIVERY_PARTNER' then 'warning'
        else 'info'
      end as severity,
      a.created_at
    from public.import_anomalies a
    where a.created_at >= now() - (interval '1 hour' * greatest(p_window_hours, 0))
  )
  select
    tenant_id,
    category,
    severity,
    count(*)::int as count,
    max(created_at) as most_recent
  from base
  group by tenant_id, category, severity
  order by count desc;
end;
$$;

-- Grants (authenticated only; not anon)
revoke all on function public.fn_anomalies_for_operator(int, text, text[]) from public;
revoke all on function public.fn_anomalies_stats(int) from public;
grant execute on function public.fn_anomalies_for_operator(int, text, text[]) to authenticated;
grant execute on function public.fn_anomalies_stats(int) to authenticated;

-- Verification (manual), Critical item 5
-- 1) As operator/admin:
--    select count(*) from public.vw_import_anomalies_recent;
--    select * from public.fn_anomalies_for_operator(24, null, null) limit 5;
--    select * from public.fn_anomalies_stats(24);
-- 2) As non-operator:
--    select * from public.fn_anomalies_for_operator(24, null, null);
--    -- expect: ERROR: 42501 insufficient_privilege
-- 3) Windowing and stats:
--    select * from public.fn_anomalies_for_operator(1, null, null);
--    select * from public.fn_anomalies_stats(1);