-- Omnivia — Stage 5: Staging retention and cleanup (pg_cron + aggregate preservation)
-- Ref: High priority item 9 — [docs/product/projects-okta-rbac-stage1-4-audit.md](docs/product/projects-okta-rbac-stage1-4-audit.md:140)
-- Objects: [public.import_retention_stats](supabase/migrations/20250818043000_stage5_imports_retention.sql:1), [sql.fn_cleanup_import_data()](supabase/migrations/20250818043000_stage5_imports_retention.sql:1)
-- Notes:
--  - Supabase CLI wraps migrations in a transaction; no explicit BEGIN/COMMIT needed here.
--  - Function sets search_path=public and is SECURITY DEFINER; idempotent upserts preserve aggregates.
--  - Cron job name: 'imports-anomalies-retention' (03:10 UTC daily) running SELECT public.fn_cleanup_import_data();

-- Ensure pg_cron is available
create extension if not exists pg_cron;

-- Historical aggregate preservation table
create table if not exists public.import_retention_stats (
  stat_date date primary key,
  staging_imports_count bigint not null default 0,
  import_anomalies_count bigint not null default 0,
  last_updated_at timestamptz not null default now()
);

-- Cleanup routine: aggregate-then-delete old data
-- Signature: [sql.fn_cleanup_import_data(p_imports_days int, p_anomalies_days int)](supabase/migrations/20250818043000_stage5_imports_retention.sql:1)
create or replace function public.fn_cleanup_import_data(
  p_imports_days int default 60,
  p_anomalies_days int default 90
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_imports boolean;
  v_has_anomalies boolean;
  v_has_imports_created boolean;
  v_has_imports_imported boolean;
  v_imports_ts_col text;
begin
  -- Detect table presence (defensive no-op if missing)
  select exists (
    select 1 from information_schema.tables where table_schema='public' and table_name='staging_imports'
  ) into v_has_imports;

  select exists (
    select 1 from information_schema.tables where table_schema='public' and table_name='import_anomalies'
  ) into v_has_anomalies;

  -- Timestamp column on staging_imports: prefer imported_at, else created_at
  if v_has_imports then
    select exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='staging_imports' and column_name='imported_at'
    ) into v_has_imports_imported;

    select exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='staging_imports' and column_name='created_at'
    ) into v_has_imports_created;

    if v_has_imports_imported then
      v_imports_ts_col := 'imported_at';
    elsif v_has_imports_created then
      v_imports_ts_col := 'created_at';
    else
      v_imports_ts_col := null;
    end if;
  end if;

  -- 1) Anomalies first: aggregate via DELETE...RETURNING to avoid cascade loss when staging rows are deleted
  if v_has_anomalies then
    if v_has_imports and v_imports_ts_col is not null then
      execute format($f$
        with d as (
          delete from public.import_anomalies a
          using public.staging_imports s
          where a.staging_id = s.id
            and (
              a.created_at < now() - (interval '1 day' * greatest(%1$s, 0))
              or s.%2$I     < now() - (interval '1 day' * greatest(%3$s, 0))
            )
          returning a.created_at
        )
        insert into public.import_retention_stats(stat_date, import_anomalies_count)
        select date(created_at) as stat_date, count(*)::bigint
        from d
        group by 1
        on conflict (stat_date) do update
          set import_anomalies_count = public.import_retention_stats.import_anomalies_count + excluded.import_anomalies_count,
              last_updated_at = now()
      $f$, p_anomalies_days, v_imports_ts_col, p_imports_days);
    else
      execute format($f$
        with d as (
          delete from public.import_anomalies a
          where a.created_at < now() - (interval '1 day' * greatest(%1$s, 0))
          returning a.created_at
        )
        insert into public.import_retention_stats(stat_date, import_anomalies_count)
        select date(created_at) as stat_date, count(*)::bigint
        from d
        group by 1
        on conflict (stat_date) do update
          set import_anomalies_count = public.import_retention_stats.import_anomalies_count + excluded.import_anomalies_count,
              last_updated_at = now()
      $f$, p_anomalies_days);
    end if;
  end if;

  -- 2) Staging imports: aggregate via DELETE...RETURNING; uses imported_at if present, otherwise created_at
  if v_has_imports and v_imports_ts_col is not null then
    execute format($f$
      with d as (
        delete from public.staging_imports s
        where s.%1$I < now() - (interval '1 day' * greatest(%2$s, 0))
        returning s.%1$I as ts_col
      )
      insert into public.import_retention_stats(stat_date, staging_imports_count)
      select date(ts_col) as stat_date, count(*)::bigint
      from d
      group by 1
      on conflict (stat_date) do update
        set staging_imports_count = public.import_retention_stats.staging_imports_count + excluded.staging_imports_count,
            last_updated_at = now()
    $f$, v_imports_ts_col, p_imports_days);
  end if;
end;
$$;

-- Schedule daily cleanup at 03:10 UTC (idempotent: unschedule then (re)schedule)
do $cron$
begin
  if exists (select 1 from pg_extension where extname='pg_cron') then
    -- Unschedule any prior job with the same name
    perform cron.unschedule(j.jobid)
    from cron.job j
    where j.jobname = 'imports-anomalies-retention';

    -- (Re)schedule daily at 03:10 UTC
   perform cron.schedule(
      'imports-anomalies-retention',
      '10 3 * * *',
      'select public.fn_cleanup_import_data();'
    );
  end if;
end;
$cron$;