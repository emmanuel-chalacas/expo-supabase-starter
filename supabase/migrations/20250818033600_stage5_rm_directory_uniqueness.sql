-- Omnivia — Stage 5 Migration: RM Directory hygiene (normalized uniqueness + audit)
-- Note: Supabase CLI wraps migrations in a transaction. Do not add BEGIN/COMMIT here.
-- Target table: public.rm_directory
-- Adds normalized_display_name, audit timestamps, updated_at trigger, and partial unique index for active rows.
-- Verify script: [docs/sql/stage5-directories-verify.sql](docs/sql/stage5-directories-verify.sql:1)

-- 0) Ensure extension for UUIDs (already present in Stage 1; harmless if exists)
create extension if not exists "pgcrypto";

-- 1) Create table if it does not exist (canonical Stage 5 shape)
create table if not exists public.rm_directory (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  preferred_username text null,
  user_id uuid null references auth.users(id) on delete set null,
  active boolean not null default true,
  normalized_display_name text generated always as (lower(regexp_replace(btrim(display_name), '\s+', ' ', 'g'))) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) Add/ensure columns on existing table
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'rm_directory') then
    begin
      alter table public.rm_directory
        add column if not exists normalized_display_name text
        generated always as (lower(regexp_replace(btrim(display_name), '\s+', ' ', 'g'))) stored;
    exception when others then
      -- If normalized_display_name exists as a non-generated column, leave it as-is
      null;
    end;

    alter table public.rm_directory
      add column if not exists created_at timestamptz not null default now(),
      add column if not exists updated_at timestamptz not null default now();

    -- Backfill any NULLs defensively
    update public.rm_directory set created_at = now() where created_at is null;
    update public.rm_directory set updated_at = now() where updated_at is null;
  end if;
end
$$;

-- 3) Shared trigger function: set NEW.updated_at = now() on UPDATE
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

-- 4) Attach updated_at trigger to rm_directory
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'rm_directory' and column_name = 'updated_at'
  ) then
    drop trigger if exists set_updated_at on public.rm_directory;
    create trigger set_updated_at
    before update on public.rm_directory
    for each row execute function public.tg_set_updated_at();
  end if;
end
$$;

-- 5) Precheck: detect duplicate normalized names among active rows; fail early with conflicts list
do $$
declare
  v_pred text;
  v_conflicts text;
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'rm_directory' and column_name = 'status'
  ) then
    v_pred := 'status = ''active''';
  else
    v_pred := 'active is true';
  end if;

  execute '
    with d as (
      select normalized_display_name, id
      from public.rm_directory
      where ' || v_pred || '
    ),
    dups as (
      select normalized_display_name, array_agg(id order by id) as ids, count(*) as c
      from d
      group by normalized_display_name
      having count(*) > 1
    )
    select string_agg(normalized_display_name || '' ['' || array_to_string(ids, '','') || '']'', ''; '')
    from dups
  ' into v_conflicts;

  if v_conflicts is not null then
    raise exception 'Cannot enforce normalized uniqueness: duplicate active RM names after normalization. Conflicts: %', v_conflicts
      using hint = 'Deactivate or rename duplicates in public.rm_directory, then re-run migration.';
  end if;
end
$$;

-- 6) Create partial unique index enforcing normalized uniqueness among active rows
do $$
declare
  v_pred text;
  v_sql text;
begin
  -- Skip if index already exists
  perform 1 from pg_indexes where schemaname = 'public' and indexname = 'ux_rm_directory_active_normalized_name';
  if found then
    return;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'rm_directory' and column_name = 'status'
  ) then
    v_pred := 'status = ''active''';
  else
    v_pred := 'active is true';
  end if;

  v_sql := format(
    'create unique index ux_rm_directory_active_normalized_name on public.rm_directory (normalized_display_name) where %s',
    v_pred
  );
  execute v_sql;
end
$$;

-- Note: legacy index rm_directory_display_name_active_uniq remains. The new index tightens normalization (collapses internal whitespace).