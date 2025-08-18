-- Omnivia — Stage 5 Verification: RM Directory hygiene and uniqueness
-- Related migration: [supabase/migrations/20250818033600_stage5_rm_directory_uniqueness.sql](supabase/migrations/20250818033600_stage5_rm_directory_uniqueness.sql:1)

-- 1) Potential duplicate clusters among active rows after normalization
--    - Lists id, display_name, active (bool), created_at for clusters with count > 1
with meta as (
  select
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'rm_directory' and column_name = 'active'
    ) as has_active,
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'rm_directory' and column_name = 'status'
    ) as has_status
),
src as (
  select
    r.id,
    r.display_name,
    r.created_at,
    case
      when m.has_active then r.active
      when m.has_status then (r.status = 'active')
      else null
    end as active,
    coalesce(r.normalized_display_name, lower(regexp_replace(btrim(r.display_name), '\s+', ' ', 'g'))) as normalized_name
  from public.rm_directory r
  cross join meta m
),
dups as (
  select normalized_name, count(*) as c
  from src
  where active is true
  group by normalized_name
  having count(*) > 1
)
select
  s.normalized_name,
  s.id,
  s.display_name,
  s.active,
  s.created_at
from src s
join dups d on d.normalized_name = s.normalized_name
order by s.normalized_name, s.display_name, s.id;

-- 2) Unique index existence
select
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'ux_rm_directory_active_normalized_name'
  ) as has_ux_rm_directory_active_normalized_name;

-- 3) NOT EXISTS violations (true means no duplicate active normalized names)
with meta as (
  select
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'rm_directory' and column_name = 'active'
    ) as has_active,
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'rm_directory' and column_name = 'status'
    ) as has_status
),
src as (
  select
    case
      when m.has_active then r.active
      when m.has_status then (r.status = 'active')
      else null
    end as active,
    coalesce(r.normalized_display_name, lower(regexp_replace(btrim(r.display_name), '\s+', ' ', 'g'))) as normalized_name
  from public.rm_directory r
  cross join meta m
),
dups as (
  select normalized_name, count(*) as c
  from src
  where active is true
  group by normalized_name
  having count(*) > 1
)
select not exists (select 1 from dups) as no_active_dupe_violations;