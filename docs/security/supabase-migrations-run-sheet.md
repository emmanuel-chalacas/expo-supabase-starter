# Supabase migrations run‑sheet (Omnivia)

This is a short, practical guide to run your new Supabase CLI–managed migrations without using the Supabase portal. It assumes the repo already contains:
- Initial migration from Stage 1: [supabase/migrations/20250817T061900_omni_bootstrap.sql](supabase/migrations/20250817T061900_omni_bootstrap.sql)
- Stage 2 migration: [supabase/migrations/20250817T062300_stage2_apply.sql](supabase/migrations/20250817T062300_stage2_apply.sql)
- Supabase CLI config: [supabase/config.toml](supabase/config.toml)
- Verification query: [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql)
- Yarn scripts added in [package.json](package.json)

Why this works even if you already ran Stage 1 + Stage 2 manually
- The migrations use IF NOT EXISTS / DROP IF EXISTS and other safety guards. Running them again is a no‑op on resources that already exist. This makes it safe to push to your remote project.

Prerequisites
- Supabase CLI installed and on PATH:
  - Windows: download from https://supabase.com/docs/guides/cli and ensure “supabase” is in PATH.
- Optional (for local “supabase start”): Docker Desktop running.
- Node + Yarn are already in this repo.

Env requirements
- Supply SUPABASE_DB_URL (preferred) or SUPABASE_DB_PASSWORD. If SUPABASE_DB_URL omits sslmode, the runner enforces sslmode=require.
- Repo must be linked so [supabase/config.toml](supabase/config.toml) contains project_id when falling back to SUPABASE_DB_PASSWORD.

One‑time: login and (optionally) init/link
- Login to Supabase CLI (prompts for a token in the browser):
  - yarn supa:login
- If you ever need to (re)init locally:
  - yarn supa:init
- Link the repo to your target project (you can also use “supabase projects list” to find your ref):
  - yarn supa:link
  - This sets project_id in [supabase/config.toml](supabase/config.toml). If not, pass “--project-ref ...” again or set %SUPABASE_PROJECT_REF% env var on Windows.

Local workflow (no portal)
- Start local Supabase stack (optional; requires Docker):
  - yarn db:local:up
- Reset local DB and apply ALL migrations:
  - yarn db:local:reset
- Run verification report against local DB:
  - yarn db:local:verify
  - You should see “pass” rows for:
    - storage bucket “attachments” present
    - storage policy predicates include “bucket_id = 'attachments'”
    - seed partner orgs present
    - features present and TELCO has 3 rows
    - index checks on projects table
- Run Stage 3 verification and policy tests:
  - yarn db:local:verify:stage3
  - yarn db:local:test:stage3

Remote workflow (no portal)
- Link once (if not already linked):
  - yarn supa:link
- Apply migrations to the linked remote database:
  - yarn db:push
- Verify against the linked remote:
  - yarn db:remote:verify
- Stage 3 verification and policy tests:
  - yarn db:remote:verify:stage3
  - yarn db:remote:test:stage3

Making new schema changes (standard process)
- Create a new migration:
  - yarn db:migration:new your_change_name
- Put your SQL changes into the newly created file under [supabase/migrations/](supabase/migrations/).
  - IMPORTANT: Do NOT include explicit “begin;”/“commit;” — the CLI wraps each migration in a transaction.
  - Prefer idempotent statements (CREATE IF NOT EXISTS, DROP IF EXISTS, CREATE OR REPLACE FUNCTION, etc.).
- Test locally:
  - yarn db:local:reset
  - yarn db:local:verify
- Push to remote when ready:
  - yarn db:push
  - yarn db:remote:verify

Cheat sheet (Windows-friendly commands via Yarn scripts)
- Login: yarn supa:login
- Start local stack: yarn db:local:up
- Fresh local DB with all migrations: yarn db:local:reset
- Verify local: yarn db:local:verify
- Verify Stage 3 local: yarn db:local:verify:stage3
- Policy tests Stage 3 local: yarn db:local:test:stage3
- Create new migration file: yarn db:migration:new add_feature_xyz
- Link to remote project: yarn supa:link
- Push migrations to remote: yarn db:push
- Verify remote: yarn db:remote:verify
- Verify Stage 3 remote: yarn db:remote:verify:stage3
- Policy tests Stage 3 remote: yarn db:remote:test:stage3

Notes and safety
- Stage 1 function and policies are included in the Stage 1 migration; Stage 2 re-applies storage policies and seeds canon data and features. Duplication is intentional and safe because of DROP/IF NOT EXISTS guards.
- If you see “transaction already in progress”, remove manual “begin; commit;” lines from your migration file.
- If you see “relation already exists”, add IF NOT EXISTS or guard the DDL in a DO $$ block as done in Stage 1.

Where to adjust project reference
- If “yarn supa:link” does not persist project_id automatically:
  - Set it in [supabase/config.toml](supabase/config.toml) under project_id = "your-project-ref".
  - Or re-run “yarn supa:link --project-ref YOUR_PROJECT_REF”.

That’s it — you can now manage schema and verification end‑to‑end with the CLI and Yarn scripts, without copy/pasting into the Supabase portal.