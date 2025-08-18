-- Omnivia — Stage 5: Retention & cleanup verification SQL
-- Related migration: [supabase/migrations/20250818043000_stage5_imports_retention.sql](../../supabase/migrations/20250818043000_stage5_imports_retention.sql:1)
-- Function: [sql.fn_cleanup_import_data()](../../supabase/migrations/20250818043000_stage5_imports_retention.sql:1)

-- 1) Confirm pg_cron is installed
select extname
from pg_extension
where extname = 'pg_cron';

-- 2) Confirm the scheduled job exists and its schedule/command
select jobid, schedule, command
from cron.job
where jobname = 'imports-anomalies-retention';

-- 3) Preview candidates older than defaults (non-destructive)
-- Note: If staging_imports.created_at is not present, you may adapt to use imported_at.
select count(*) as old_imports
from public.staging_imports
where created_at < now() - interval '60 days';

select count(*) as old_anomalies
from public.import_anomalies
where created_at < now() - interval '90 days';

-- 4) Show recent stats rows (aggregated preservation)
select *
from public.import_retention_stats
order by stat_date desc
limit 10;

-- 5) Manual run example (DANGER: use only in ephemeral/test DBs)
-- Example: select public.fn_cleanup_import_data(0, 0); -- DANGER: deletes all rows; only for ephemeral test DBs