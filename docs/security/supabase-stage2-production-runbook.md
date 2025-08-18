# Stage 2 — Production Execution Runbook (Option C)

Scope: This runbook executes Stage 2 schema, directories, feature flags, Storage bucket, and verification in the Production Supabase project using Supabase Studio (SQL Editor).

References:
- Bootstrap migration: [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1)
- Stage 2 apply: [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1)
- Stage 2 verify: [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1)
- Tracker: [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md:278)

## Change control and preflight checklist
- Change window approved and on-call present.
- Confirm you are in the Production Supabase project (Studio → Project name).
- Role has permission to use SQL Editor, Storage, and Policies.
- PITR/backup plan verified.
- No flags will be enabled by these scripts; seeds use [sql.INSERT](docs/sql/stage2-apply.sql:1) with ON CONFLICT DO NOTHING.
- Acknowledge scripts are idempotent; they use [sql.CREATE INDEX](docs/sql/stage2-apply.sql:149) IF NOT EXISTS and duplicate-safe policy handling with [sql.DROP POLICY](docs/sql/omni-bootstrap.sql:457) + [sql.CREATE POLICY](docs/sql/omni-bootstrap.sql:458).

## Execution steps (Production)

### Step A — Apply bootstrap migration
- Open Supabase Studio → SQL Editor.
- Paste the contents of [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1) and execute.
- This creates core tables, RLS, helper [sql.using_rls_for_project()](docs/sql/omni-bootstrap.sql:258), and base indexes like:
  - projects: stage, partner_org_id, derived_status, tenant_id via [sql.CREATE INDEX](docs/sql/omni-bootstrap.sql:147)–[sql.CREATE INDEX](docs/sql/omni-bootstrap.sql:150)
- Safe to re-run; it uses IF NOT EXISTS where supported.

### Step B — Ensure bucket, policies, seeds, and fill any missing indexes
- In SQL Editor, paste and execute [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1).
- What this does:
  - Ensures private Storage bucket “attachments” via [sql.storage.create_bucket()](docs/sql/stage2-apply.sql:10) if missing.
  - Re-applies Storage policies for storage.objects with drop-if-exists then [sql.CREATE POLICY](docs/sql/omni-bootstrap.sql:458), [sql.CREATE POLICY](docs/sql/omni-bootstrap.sql:475), [sql.CREATE POLICY](docs/sql/omni-bootstrap.sql:493); they reference attachments_meta and [sql.using_rls_for_project()](docs/sql/omni-bootstrap.sql:258).
  - Seeds partner_org and partner_normalization using idempotent UPSERT patterns ([sql.INSERT ... ON CONFLICT](docs/sql/stage2-apply.sql:1)).
  - Seeds tenant-scoped features (ENABLE_PROJECTS, ENABLE_ATTACHMENTS_UPLOAD, ENABLE_OKTA_AUTH) as disabled using [sql.INSERT](docs/sql/stage2-apply.sql:1) ON CONFLICT DO NOTHING.
  - Creates any missing indexes using [sql.CREATE INDEX](docs/sql/stage2-apply.sql:149) IF NOT EXISTS to match Stage 2 filter columns.

### Step C — Run verification report
- Execute [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1) in SQL Editor.
- It checks:
  - Table existence via [sql.to_regclass](docs/sql/stage2-verify.sql:1)
  - Index presence via pg_indexes (stage_application, partner_org_id, derived_status, tenant_id)
  - Bucket exists in storage.buckets = 'attachments'
  - Storage policies exist in pg_policies referencing bucket_id='attachments'
  - Seeds present in partner_org, partner_normalization, features

## Verification capture — paste this block back to the tracker callouts
- After Step C, copy the query results into a text block and include:
  - Tables existence booleans
  - Index presence booleans per column
  - Bucket_ok boolean
  - Storage policies found (names or count)
  - partner_org count and sample labels
  - partner_normalization count referencing partner_org
  - features rows present for names ENABLE_PROJECTS, ENABLE_ATTACHMENTS_UPLOAD, ENABLE_OKTA_AUTH (per-tenant)
- Example template (replace with your actual results):
  - tables_ok: projects=true, project_membership=true, contacts=true, engagements=true, attachments_meta=true, partner_org=true, partner_normalization=true, ds_directory=true, rm_directory=true, user_profiles=true, user_roles=true, features=true, staging_imports=true
  - indexes_ok: stage_application=true, partner_org_id=true, derived_status=true, tenant_id=true
  - bucket_ok: true
  - storage_policies_ok: 3 (attachments_read, attachments_insert, attachments_delete)
  - partner_org_count: 7; samples: ["Vendor X","DP Alpha","CP Bravo"]
  - partner_normalization_count: 12
  - features_present: ENABLE_PROJECTS=true, ENABLE_ATTACHMENTS_UPLOAD=true, ENABLE_OKTA_AUTH=true for tenant_id='TELCO'
- We will then mark Stage 2 checklist items complete in [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md:286).

## Post-run checks (no feature enablement)
- Do not enable flags yet; enablement is handled in a later stage. You can confirm rows exist with a safe read query (already included in [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1)).
- Storage → Buckets should show “attachments” as Private.
- Policies should list three “attachments_*” policies on storage.objects.

## Rollback and remediation (if needed)
- Seeds: remove with targeted [sql.DELETE FROM](docs/sql/stage2-apply.sql:1) using keys (e.g., features by tenant_id and name).
- Policies: remove with [sql.DROP POLICY](docs/sql/omni-bootstrap.sql:457) policy_name ON storage.objects, then re-run [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1) to restore.
- Bucket: if created by mistake, ensure it’s empty, then delete in Storage UI or via SQL. Re-run [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1) later to re-create.
- Indexes: [sql.DROP INDEX](docs/sql/stage2-apply.sql:1) by name if a conflicting index must be replaced, then re-run [sql.CREATE INDEX](docs/sql/stage2-apply.sql:149) IF NOT EXISTS.

## FAQ and notes
- Idempotency: Scripts are safe to re-run; they use IF NOT EXISTS, ON CONFLICT DO NOTHING, and drop-and-create for policies.
- Tenant scoping: features are keyed by (tenant_id, name). These scripts insert but do not flip flags on.
- Dependencies: Using helper [sql.using_rls_for_project()](docs/sql/omni-bootstrap.sql:258) centralizes membership checks across policies to avoid duplication.

## Completion note (for operator)
- After you complete Steps A–C, paste the verification summary into the issue/PR or send it back so we can update [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md:286) and mark Stage 2 tasks complete.

## Constraints
- Do not alter any checkboxes in the tracker as part of this file creation.
- Ensure all language constructs and filenames appear as clickable references per repository rules.