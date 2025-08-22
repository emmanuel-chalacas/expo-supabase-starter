-- Omnivia — Stage 6: Projects Field Alignment
-- Idempotent migration to align public.projects fields and extend public.contacts.
-- Note: Supabase CLI wraps migrations in a transaction; do not add BEGIN/COMMIT.

-- ========== 1) Additive columns on public.projects ==========
alter table public.projects add column if not exists address text;
alter table public.projects add column if not exists suburb text;
alter table public.projects add column if not exists state text;
alter table public.projects add column if not exists build_type text;
alter table public.projects add column if not exists fod_id text;
alter table public.projects add column if not exists premises_count integer;
alter table public.projects add column if not exists residential integer default 0;
alter table public.projects add column if not exists commercial integer default 0;
alter table public.projects add column if not exists essential integer default 0;
alter table public.projects add column if not exists latitude numeric(9,6);
alter table public.projects add column if not exists longitude numeric(9,6);
alter table public.projects add column if not exists development_type text;
alter table public.projects add column if not exists practical_completion_notified date;

-- Ensure defaults for count columns when they pre-exist without defaults
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public' and table_name = 'projects' and column_name = 'residential'
      and column_default is null
  ) then
    alter table public.projects alter column residential set default 0;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public' and table_name = 'projects' and column_name = 'commercial'
      and column_default is null
  ) then
    alter table public.projects alter column commercial set default 0;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public' and table_name = 'projects' and column_name = 'essential'
      and column_default is null
  ) then
    alter table public.projects alter column essential set default 0;
  end if;
end
$$;

-- ========== 2) Named CHECK constraints (create only if missing) ==========
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'projects_premises_count_nonneg_chk'
      and conrelid = 'public.projects'::regclass
  ) then
    alter table public.projects
      add constraint projects_premises_count_nonneg_chk
      check (premises_count >= 0);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'projects_residential_nonneg_chk'
      and conrelid = 'public.projects'::regclass
  ) then
    alter table public.projects
      add constraint projects_residential_nonneg_chk
      check (residential >= 0);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'projects_commercial_nonneg_chk'
      and conrelid = 'public.projects'::regclass
  ) then
    alter table public.projects
      add constraint projects_commercial_nonneg_chk
      check (commercial >= 0);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'projects_essential_nonneg_chk'
      and conrelid = 'public.projects'::regclass
  ) then
    alter table public.projects
      add constraint projects_essential_nonneg_chk
      check (essential >= 0);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'projects_development_type_enum_chk'
      and conrelid = 'public.projects'::regclass
  ) then
    alter table public.projects
      add constraint projects_development_type_enum_chk
      check (
        development_type is null
        or development_type in ('Residential','Commercial','Mixed Use')
      );
  end if;
end
$$;

-- ========== 3) Indexes (duplicates-safe) ==========
create index if not exists projects_devtype_idx on public.projects (development_type);
create index if not exists projects_build_type_idx on public.projects (build_type);

-- ========== 4) Extend public.contacts ==========
alter table public.contacts add column if not exists company text;
alter table public.contacts add column if not exists role text;