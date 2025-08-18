# Supabase CLI migrations setup for Omnivia

This guide shows how to manage your database using the Supabase CLI and versioned SQL migrations stored in your repo. The goal is to stop copy/pasting SQL in the Supabase portal and run everything from code and commands.

Key repo files referenced:
- [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql)
- [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql)
- [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql)
- [package.json](package.json)

Do I still need migrations if Stage 1 and Stage 2 were already applied manually?
Yes. Converting them to migrations ensures you can:
- Rebuild local databases quickly.
- Provision new environments consistently (staging, CI).
- Review and version-control schema changes in Git.
- Push changes to your remote Supabase project without using the portal.

Because you already applied these changes, we will adopt migrations safely using one of two strategies:
- Option A — Idempotent migrations (recommended): Keep CREATE IF NOT EXISTS / DROP IF EXISTS guards so re-applying on the remote is a no‑op. Your Stage 2 file is already written this way.
- Option B — Baseline then build forward: Generate a “baseline” migration that reflects the current schema so the remote is considered up‑to‑date, then add new migrations from there. Use this if making Stage 1 idempotent is hard.

Prerequisites
- Supabase CLI installed: https://supabase.com/docs/guides/cli
- Node + Yarn installed (already present in this repo).
- Docker Desktop (only if you want local supabase start; not required for remote-only).

One-time project scaffolding
1) Initialize Supabase CLI in the repo (creates [supabase/config.toml](supabase/config.toml) and folders):

    supabase init

2) Add helpful Yarn scripts in [package.json](package.json). Example:

    "scripts": {
      "supa:login": "supabase login",
      "supa:init": "supabase init",
      "supa:link": "supabase link --project-ref %SUPABASE_PROJECT_REF%",
      "db:local:up": "supabase start",
      "db:local:reset": "supabase db reset",
      "db:local:verify": "node scripts/run-sql.js docs/sql/stage2-verify.sql",
      "db:migration:new": "supabase migration new",
      "db:push": "supabase db push",
      "db:remote:verify": "node scripts/run-sql.js docs/sql/stage2-verify.sql"
    }

3) Login once:

    yarn supa:login

4) Optional: Start local stack if you want a local database and auth:

    yarn db:local:up

Creating migrations for Stage 1 and Stage 2
We will create two timestamped migration files under [supabase/migrations/](supabase/migrations/). The CLI names files like 20250817T060000_stage2_apply.sql.

Important note about transactions:
- The Supabase CLI wraps each migration in a transaction. If your SQL file contains explicit begin; and commit;, remove those lines to avoid “transaction already in progress” errors.

A) Stage 1 (bootstrap)
1) Create a new migration:

    yarn db:migration:new omni_bootstrap

2) Open the generated file in [supabase/migrations/](supabase/migrations/) and paste the contents of [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql).

3) Make it idempotent if possible:
- Use CREATE TABLE IF NOT EXISTS for tables.
- Use CREATE INDEX IF NOT EXISTS for indexes.
- For policies, use DROP POLICY IF EXISTS then CREATE POLICY.
- For functions, prefer CREATE OR REPLACE FUNCTION.
- Remove outer begin; and commit; lines.

If making Stage 1 idempotent is complex, see the “Baseline adoption” section below.

B) Stage 2 (apply)
1) Create a new migration:

    yarn db:migration:new stage2_apply

2) Copy the SQL from [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql) into the new migration file.

3) Remove outer begin; and commit; lines (the CLI wraps migrations in a transaction).

4) Keep all IF NOT EXISTS and DROP IF EXISTS guards as-is. This migration is already idempotent and safe to run on a database where Stage 2 has been applied manually.

Local verification workflow
1) Reset and apply all migrations to a fresh local database:

    yarn db:local:reset

2) Run the verification query and check the report:

    yarn db:local:verify

Note: You can also run verification against a local database by setting SUPABASE_DB_URL to your local Postgres URL and running:

    yarn db:remote:verify

Alternatively, run the verification SQL directly in the local Studio SQL editor.

The query in [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql) will output a single grid with pass/fail lines and counts.

Linking and pushing to your remote Supabase project
1) Link the repo to your project once:

    yarn supa:link

Provide the project ref when prompted. You can find it in the dashboard URL or via:

    supabase projects list

2) Push migrations to remote:

    yarn db:push

This runs your migrations on the linked remote database. Idempotent guards make it safe even if parts were already created.

3) Verify on remote:

    yarn db:remote:verify

The runner resolves the connection in this order:
- SUPABASE_DB_URL (sslmode=require enforced if missing)
- SUPABASE_DB_PASSWORD + project_id from supabase/config.toml (constructs a secure direct URL)

You will see the same pass/fail report printed in your terminal.

Baseline adoption (alternative to idempotent Stage 1)
If Stage 1 is hard to make idempotent, you can baseline the current schema:

- Create an empty migration named baseline_applied that contains only a comment.
- Commit it so the repo has a starting point.
- For the remote database, do not run the baseline migration; only run future migrations with changes.

This approach is advanced and tooling support evolves. The recommended path remains idempotent migrations so both local and remote can run the same files safely.

Optional: CI automation (GitHub Actions)
Add a workflow that applies migrations and runs verification on pushes to main. Store SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF as repo secrets.

Add [ .github/workflows/supabase-migrations.yml](.github/workflows/supabase-migrations.yml) with the following content:

    name: Supabase Migrations
    on:
      push:
        branches: [main]
    jobs:
      migrate:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-node@v4
            with:
              node-version: 20
              cache: yarn
          - uses: supabase/setup-cli@v1
          - name: Install dependencies
            run: yarn install --frozen-lockfile
          - name: Login and link
            env:
              SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
              SUPABASE_PROJECT_REF: ${{ secrets.SUPABASE_PROJECT_REF }}
            run: |
              supabase login --token "${SUPABASE_ACCESS_TOKEN}"
              supabase link --project-ref "${SUPABASE_PROJECT_REF}"
          - name: Push migrations
            run: supabase db push
          - name: Remote verify via runner
            env:
              SUPABASE_DB_URL: ${{ secrets.SUPABASE_DB_URL }}
              SUPABASE_DB_PASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}
            run: yarn db:remote:verify

Troubleshooting tips
- ERROR: relation already exists: add IF NOT EXISTS or wrap with guards.
- ERROR: transaction is already in progress: remove explicit begin; commit; from the migration file.
- Storage bucket/policies: ensure the bucket exists before policies, or keep your Stage 2 order which already handles this.
- Functions that reference auth.uid(): ensure auth schema exists (it does in Supabase by default).
- Extensions: if you use extensions (uuid-ossp, pgcrypto), add CREATE EXTENSION IF NOT EXISTS statements early in Stage 1.

Summary
- Even though Stage 1 and Stage 2 were applied manually, putting them into migrations gives you repeatability, CI, and no-portal workflows.
- Stage 2 can be converted as-is (after removing begin/commit).
- For Stage 1, prefer adding guards to make it idempotent; if not feasible, use the baseline approach.
- From now on, every schema change should be a new migration under [supabase/migrations/](supabase/migrations/), tested locally, then pushed to remote.