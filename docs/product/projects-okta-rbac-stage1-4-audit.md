# Okta + Projects RBAC Implementation Review (Stages 1–4)

Scope: comprehensive review of work completed through Stages 1–4 in [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md:1), with recommended changes for Stage 5+ and production readiness.

Executive summary
- Overall status: strong progress with identity, schema, RLS, import, and CI scaffolding in place. No blocking architectural flaws found.
- Critical fixes required before Stage 5: environment template completeness, post-login role/profile sync, logout return-path robustness, import rate limiting/backpressure, anomalies/runbook surface, and directory uniqueness hygiene.
- Stage 5+ impacts: incorporate status recompute triggers from merge path, enforce keyset pagination, expand observability gates, and finalize production cutover steps for Okta custom domain.

Evidence reviewed (code and migrations)
- Stage 1 identity and session: [auth/okta.ts](auth/okta.ts:1), [typescript.getRedirectUri()](auth/okta.ts:20), [typescript.getOktaDiscovery()](auth/okta.ts:24), [typescript.oktaAuthorize()](auth/okta.ts:36), [context/supabase-provider.tsx](context/supabase-provider.tsx:1), [typescript.oktaSignIn()](context/supabase-provider.tsx:20), [typescript.oktaSignOut()](context/supabase-provider.tsx:32), [auth/secure-storage.ts](auth/secure-storage.ts:1), [config/supabase.ts](config/supabase.ts:1), [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1), [app.json](app.json:1).
- Stage 3 RLS helper and tests: [sql.using_rls_for_project()](supabase/migrations/20250817084500_stage3_policies.sql:9), [docs/sql/stage3-verify.sql](docs/sql/stage3-verify.sql:1), [docs/sql/stage3-policy-tests.sql](docs/sql/stage3-policy-tests.sql:1).
- Stage 4 import pipeline: [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:1), [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250817231500_stage4_import.sql:295), [sql.fn_projects_membership_backfill()](supabase/migrations/20250817231500_stage4_import.sql:553), [docs/sql/stage4-verify.sql](docs/sql/stage4-verify.sql:1), [docs/sql/stage4-smoke-tests.sql](docs/sql/stage4-smoke-tests.sql:1), [package.json](package.json:1).
- Environment variables: .env (single source of truth); function secrets configured in Supabase (no repo placeholders).

Findings by priority

Critical (must fix before Stage 5)
1) Environment variables source of truth
   - Observed: [.env](.env:1) already defines EXPO_PUBLIC_SUPABASE_URL, EXPO_PUBLIC_SUPABASE_ANON_KEY, EXPO_PUBLIC_ENABLE_OKTA_AUTH, EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER, EXPO_PUBLIC_OKTA_ISSUER, EXPO_PUBLIC_OKTA_CLIENT_ID, EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT; and [.gitignore](.gitignore:13) correctly ignores .env.
   - Change: Removed .env.example from the repo to avoid drift and duplication.
   - Action: Use [.env](.env:1) for local/dev only. CI/workflows must continue using repository secrets (no committed values). Document that PROJECTS_IMPORT_BEARER and SUPABASE_SERVICE_ROLE_KEY are configured as Supabase Function Secrets (never in .env or repo), consistent with [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:55).
   - Deployment notes
     - Status: Not fixed (confirmation complete)
     - Evidence: [.env.example](.env.example:1) exists; [.gitignore](.gitignore:13) ignores .env as expected.
     - Next action (A1): Remove .env.example; update docs to reference [.env](.env:1) only for local/dev; confirm CI/repo workflows use repository secrets exclusively; ensure PROJECTS_IMPORT_BEARER and SUPABASE_SERVICE_ROLE_KEY remain only in Supabase Function Secrets per [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:1).
     - Verification: “git ls-files -- .env.example” returns nothing; CI pipelines read secrets; Supabase Functions show the required secrets configured.
2) Post-login profile/role mirror not invoked
   - Issue: After [typescript.oktaSignIn()](context/supabase-provider.tsx:20), there is no RPC to idempotently mirror Okta app_roles and identifiers into [user_profiles](docs/security/okta-oidc-supabase.md:197) and [user_roles](docs/security/okta-oidc-supabase.md:204).
   - Action: Add a post-login sync RPC and invoke it after Supabase sign-in and on refresh; see tracker Actions 509–513.
   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Migration: [supabase/migrations/20250818021000_stage5_post_login_sync.sql](supabase/migrations/20250818021000_stage5_post_login_sync.sql:1) with [sql.fn_sync_profile_and_roles(jsonb,text[])](supabase/migrations/20250818021000_stage5_post_login_sync.sql:9) (SECURITY DEFINER).
       - Client: [typescript.oktaAuthorize()](auth/okta.ts:36) scopes include “groups”; [typescript.fetchOktaUserInfo()](auth/okta.ts:147) added; provider invokes RPC after sign-in and on 'TOKEN_REFRESHED' in [context/supabase-provider.tsx](context/supabase-provider.tsx:1).
     - Deploy steps:
       - Apply migration.
       - Ship client update (ensuring scopes “openid profile email groups”).
     - Verification:
       - SQL: select public.fn_sync_profile_and_roles('{"sub":"oktasub-123","email":"u@example.com"}', ARRAY['admin','viewer']);
       - App: sign-in triggers one RPC call; token refresh triggers debounced sync; DB user_profiles/user_roles reconciled.

3) Logout return-path robustness and end-session handling
   - Issue: [typescript.oktaSignOut()](context/supabase-provider.tsx:32) invokes end_session_endpoint with id_token_hint then ignores result; no retry/timeout UX; return URL default may point to oauthredirect rather than a dedicated signout route.
   - Action: Harden logout flow with explicit timeout/retry and ensure EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT is set to omnivia://signout; add QA checks across iOS/Android.
   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Helpers: [typescript.buildEndSessionUrl()](auth/okta.ts:203), [typescript.callEndSessionWithTimeout()](auth/okta.ts:252).
       - Provider: hardened [typescript.oktaSignOut()](context/supabase-provider.tsx:66), dedicated route [app/(public)/signout.tsx](app/(public)/signout.tsx:1) registered in [app/(public)/_layout.tsx](app/(public)/_layout.tsx:1).
     - Env:
       - EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT recommended; default fallback omnivia://signout. Confirm deep-link scheme in [app.json](app.json:1).
     - Verification:
       - Sign-out clears local session and navigates to /signout immediately.
       - End-session call uses id_token_hint with 6s timeout and one retry; offline path non-blocking.
       - iOS/Android deep-link to omnivia://signout lands on the signout route.

4) Import rate limiting and backpressure
   - Issue: Edge handler [typescript.handlePost()](supabase/functions/import-projects/index.ts:144) validates input but does not enforce per-tenant or global throttle; bursts from Power Automate can pressure DB.
   - Action: Implement lightweight rate limiting and return 429 on overload; document client backoff.
   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Limiter in [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:1) via [typescript.consumeTokenOrDelay()](supabase/functions/import-projects/index.ts:89), [typescript.rateLimitResponse()](supabase/functions/import-projects/index.ts:123), enforced early in [typescript.handlePost()](supabase/functions/import-projects/index.ts:227).
       - Client contract docs updated: [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:1) (429 + Retry-After guidance).
     - Defaults:
       - Per-tenant 1 RPS, burst 5; per-tenant concurrency 2; global concurrency 6; env overrides IMPORT_RATE_LIMIT_RPS, IMPORT_RATE_LIMIT_BURST, IMPORT_GLOBAL_CONCURRENCY, IMPORT_TENANT_CONCURRENCY, IMPORT_WINDOW_MS.
     - Verification:
       - Burst >5 in ~1s → 429 with Retry-After header.
       - >2 concurrent same-tenant or >6 global concurrent → 429.
       - Requests succeed after Retry-After duration.

5) Anomalies surfacing and stewardship runbook
   - Issue: Anomalies are recorded in [public.import_anomalies](supabase/migrations/20250817231500_stage4_import.sql:94) but there is no dashboard/alerting hook yet.
   - Action: Create anomalies dashboard, email/alert routes, and an operator playbook; link from the tracker.
   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Migration: [supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql](supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql:1) (views vw_import_anomalies_recent, vw_import_anomalies_stats_24h; RPCs [sql.fn_anomalies_for_operator(int,text,text[])](supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql:1), [sql.fn_anomalies_stats(int)](supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql:1)).
       - Edge Function: [supabase/functions/anomalies/index.ts](supabase/functions/anomalies/index.ts:1) routes GET /functions/v1/anomalies, POST /functions/v1/anomalies/alerts.
       - UI: [app/(protected)/anomalies.tsx](app/(protected)/anomalies.tsx:1); Runbook: [docs/security/supabase-imports-runbook.md](docs/security/supabase-imports-runbook.md:1); Tracker: [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md:1).
     - Config:
       - Function Secrets: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (server-side alert only), ANOMALIES_ALERT_WEBHOOK (optional), ANOMALIES_ALERT_WINDOW_HOURS, ANOMALIES_ALERT_MIN_COUNT.
     - Verification:
       - DB: operator can select from RPCs; non-operator receives insufficient_privilege.
       - Edge Function: authorized GET returns rows/stats; POST /alerts returns 204 without webhook or 202 and POSTs JSON when configured.
       - UI: operator/admin sees stats and recent anomalies (100 max), payload_excerpt only.

High priority
6) Directory hygiene and uniqueness for rm_directory
   - Issue: RM matching depends on exact normalized display_name; duplicates or whitespace variants can cause ambiguous matches.
   - Action: Add a unique index on normalized display_name for active rows and audit fields; see tracker items 543–546.

    - Deployment notes
      - Status: Fixed
      - Artifacts:
        - Migration: [supabase/migrations/20250818033600_stage5_rm_directory_uniqueness.sql](supabase/migrations/20250818033600_stage5_rm_directory_uniqueness.sql:1)
        - Verify: [docs/sql/stage5-directories-verify.sql](docs/sql/stage5-directories-verify.sql:1)
      - Deploy steps:
        - Apply migration.
        - Run verify SQL to detect any duplicate active names; resolve by deactivating or renaming duplicates, then re-run migration if it failed on precheck.
      - Verification:
        - Unique index present: ux_rm_directory_active_normalized_name.
        - Verify SQL returns zero duplicate clusters for active rows.
        - Insert/update with only whitespace/case changes is prevented from creating ambiguous active duplicates.
7) Provider smoke tests and environment parity
   - Issue: No explicit smoke test to validate provider=oidc vs provider=okta in each environment.
   - Action: Add a provider smoke-test in CI and as a health check.
   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Script: [scripts/provider-smoke.js](scripts/provider-smoke.js:1)
       - CI: [.github/workflows/provider-smoke.yml](.github/workflows/provider-smoke.yml:1)
       - Edge Function (optional): [supabase/functions/auth-health/index.ts](supabase/functions/auth-health/index.ts:1)
     - Deploy steps:
       - Configure repository Variables and Secrets for each environment:
         - Vars: EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER, EXPO_PUBLIC_ENABLE_OKTA_AUTH, EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT, EXPECTED_PROVIDER.
         - Secrets: EXPO_PUBLIC_OKTA_ISSUER.
       - Run the workflow “Provider Smoke” or open GET /functions/v1/auth-health to validate from a running environment (set Function Secrets: OKTA_ISSUER, SUPABASE_OIDC_PROVIDER, EXPECTED_PROVIDER, OKTA_END_SESSION_REDIRECT).
     - Verification:
       - CI job succeeds with “ok:true” summary or “SKIP” when secrets are intentionally absent.
       - auth-health returns 200 with ok:true JSON and lists 'authorization_endpoint' detected.
       - Changing EXPECTED_PROVIDER to the wrong value causes CI to fail, proving parity enforcement.

8) Clock skew tolerance and local ID token verification
   - Issue: No local verification step; skew handling not documented.
   - Action: Document skew tolerance and optionally add a local verifier to complement Supabase checks; add negative tests.
- Deployment notes
       - Status: Fixed
       - Artifacts:
         - Client: [typescript.verifyIdTokenClaims()](auth/okta.ts:306), call sites in [context/supabase-provider.tsx](context/supabase-provider.tsx:1)
         - Docs: [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:316), [docs/security/identity-negative-tests.md](docs/security/identity-negative-tests.md:1)
       - Env:
         - EXPO_PUBLIC_ENABLE_LOCAL_ID_VERIFY=true to enable local claims checks; default false.
         - Skew: 300 seconds (configurable via code opts if needed).
       - Verification:
         - With flag enabled, sign-in and refresh run claims checks with 5-minute skew and throttle/debounce to avoid excess verification.
         - Performing the negative tests produces local verifier errors with the documented codes, while Supabase still governs final session validity.

9) Staging retention and cleanup
    - Issue: Retention period for staging_imports and import_anomalies is not specified.
    - Action: Add a scheduled cleanup job, e.g., 30–90 days retention with metrics preserved.

    - Deployment notes
      - Status: Fixed
      - Artifacts:
        - Migration: [supabase/migrations/20250818043000_stage5_imports_retention.sql](supabase/migrations/20250818043000_stage5_imports_retention.sql:1)
        - Verify: [docs/sql/stage5-retention-verify.sql](docs/sql/stage5-retention-verify.sql:1)
        - Runbook: [docs/security/supabase-imports-runbook.md](docs/security/supabase-imports-runbook.md:1) (Retention & cleanup section)
      - Defaults:
        - staging_imports: 60 days; import_anomalies: 90 days; schedule: daily at 03:10 UTC via pg_cron (job: imports-anomalies-retention).
      - Deploy steps:
        - Apply migration.
        - Verify pg_cron job exists and review counts via the verify SQL.
        - Optionally adjust schedule or retention by updating the cron.job entry and/or calling [sql.fn_cleanup_import_data()](supabase/migrations/20250818043000_stage5_imports_retention.sql:1) with desired parameters.
      - Verification:
        - cron.job shows imports-anomalies-retention with a valid next_run.
        - Old rows beyond retention are reduced after the first scheduled run.
        - public.import_retention_stats records aggregated counts for deleted rows by stat_date.

10) Storage preview content-type enforcement
   - Issue: Client-side previews may be spoofed; server-side detection not yet asserted.
   - Action: Detect content-type from header bytes on the server path and restrict preview to image/* and application/pdf.
   - Client usage: Previews must call GET /functions/v1/storage-preview with the user's Authorization: Bearer <user_jwt> header and provide bucket/path so the function validates content-type before serving the object.

   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Edge Function: [supabase/functions/storage-preview/index.ts](supabase/functions/storage-preview/index.ts:1)
     - Env:
       - SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (Function Secrets)
       - ALLOW_SVG (optional, default false)
     - Behavior:
       - Only image/png, image/jpeg, image/gif, image/webp, application/pdf permitted by default; optional image/svg+xml if ALLOW_SVG=true.
       - Authorization enforced via a user-scoped Range fetch before signing.
       - Returns 302 Location to a 60s signed URL by default; JSON mode available with redirect=false.
     - Deploy steps:
       - Deploy Edge Function and set Function Secrets.
       - Update client preview code to call /functions/v1/storage-preview with Authorization header and bucket/path.
     - Verification:
       - A non-image/PDF upload returns 415 from storage-preview and is not rendered.
       - Allowed files return a short-lived signed URL.
       - Removing Authorization or lacking bucket/path yields 401/400 respectively.
       - With ALLOW_SVG=false, .svg files are rejected; setting ALLOW_SVG=true allows them if root element is <svg>.

Medium priority
11) Edge function upsert options anomaly
   - Observation: [typescript.upsert()](supabase/functions/import-projects/index.ts:240) is called with two options objects; extra parameter is ignored but is misleading.
   - Action: Collapse to a single options object for clarity.
   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Consolidated duplicate options into a single object at [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:350), affecting [typescript.upsert()](supabase/functions/import-projects/index.ts:352) on lines 350–352 (before/after verified in PR).
     - Deploy steps:
       - Rebuild and deploy the “import-projects” Edge Function. No schema changes required.
     - Verification:
       - Static: Search in [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:1) for calls passing multiple options objects to upsert; expect zero matches.
       - Runtime: Execute a nominal POST to /functions/v1/import-projects and verify success (200/202) with no options-shape warnings and no P0001 error surface.

12) Ensure all policies reuse using_rls_for_project
   - Observation: Helper [sql.using_rls_for_project()](supabase/migrations/20250817084500_stage3_policies.sql:9) is defined; verify all relevant policies reference it (projects, contacts, engagements, attachments_meta, storage).
   - Action: Confirm via [docs/sql/stage3-verify.sql](docs/sql/stage3-verify.sql:1) and extend checks as needed.
   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Migration: [supabase/migrations/20250818050300_stage5_rls_helper_reuse.sql](supabase/migrations/20250818050300_stage5_rls_helper_reuse.sql:1) — enables RLS where needed and redefines select/insert/update/delete policies on public.projects, public.contacts, public.engagements, public.attachments_meta, and storage.objects to include [sql.using_rls_for_project()](supabase/migrations/20250817084500_stage3_policies.sql:9).
       - Verify SQL updates: [docs/sql/stage3-verify.sql](docs/sql/stage3-verify.sql:1) — appended checks to flag any target-table policies missing 'using_rls_for_project(' and a per-table ok summary.
       - Optional tests: [docs/sql/stage3-policy-tests.sql](docs/sql/stage3-policy-tests.sql:1) — added targeted contacts tests proving enforcement, with local cleanup.
     - Deploy steps:
       - Apply the migration [supabase/migrations/20250818050300_stage5_rls_helper_reuse.sql](supabase/migrations/20250818050300_stage5_rls_helper_reuse.sql:1).
       - Run [docs/sql/stage3-verify.sql](docs/sql/stage3-verify.sql:1) and confirm zero rows are listed as missing the helper; per-table summary shows ok=true for all target tables.
       - Optionally run the appended tests in [docs/sql/stage3-policy-tests.sql](docs/sql/stage3-policy-tests.sql:1) and confirm pass markers in the _results harness (if present).
     - Verification:
       - pg_policies shows all USING/WITH CHECK predicates on the target tables include [sql.using_rls_for_project()](supabase/migrations/20250817084500_stage3_policies.sql:9).
       - Optional contacts tests show permitted rows are visible while non-permitted rows are denied.

13) Keyset pagination and covering indexes
   - Observation: Index on projects(stage_application, stage_application_created desc) exists per Stage 2 notes.
   - Action: Mandate keyset pagination in the Stage 6 list view and verify index coverage during perf tests.
   - Deployment notes
     - Status: Fixed
     - Artifacts:
       - Migration: [supabase/migrations/20250818051703_stage5_projects_keyset_indexes.sql](supabase/migrations/20250818051703_stage5_projects_keyset_indexes.sql:1)
         - DDL: CREATE INDEX IF NOT EXISTS ix_projects_tenant_stageapp_created_id_desc ON public.projects (tenant_id, stage_application, stage_application_created DESC, id DESC);
       - Verify SQL: [docs/sql/stage6-keyset-verify.sql](docs/sql/stage6-keyset-verify.sql:1) — checks both index presence and plan usage with EXPLAIN (FORMAT JSON).
       - Client helper scaffolding: [lib/keyset-pagination.ts](lib/keyset-pagination.ts:1) exporting [typescript.encodeProjectsCursor()](lib/keyset-pagination.ts:43), [typescript.decodeProjectsCursor()](lib/keyset-pagination.ts:47), [typescript.buildProjectsOrFilter()](lib/keyset-pagination.ts:86), and [typescript.applyProjectsKeyset()](lib/keyset-pagination.ts:104).
     - Deploy steps:
       - Apply the migration [supabase/migrations/20250818051703_stage5_projects_keyset_indexes.sql](supabase/migrations/20250818051703_stage5_projects_keyset_indexes.sql:1).
       - Run [docs/sql/stage6-keyset-verify.sql](docs/sql/stage6-keyset-verify.sql:1) and confirm index_exists=true, plan_uses_index=true, ok=true.
       - Stage 6 integration: wire keyset in the list view using [typescript.applyProjectsKeyset()](lib/keyset-pagination.ts:104), or prefer a server RPC that encapsulates the predicate.
     - Verification:
       - Presence/plan checks pass in [docs/sql/stage6-keyset-verify.sql](docs/sql/stage6-keyset-verify.sql:1).
       - Example next-page query shape uses Supabase’s .or() with [typescript.buildProjectsOrFilter()](lib/keyset-pagination.ts:86) and chained orders.

Low priority
14) Access token handling post-authorization
   - Observation: [typescript.oktaAuthorize()](auth/okta.ts:36) returns accessToken but it is unused. This is acceptable for ID token exchange but should be intentional.
   - Action: Document rationale or remove unused variable to reduce confusion.

15) Logging consistency
   - Observation: Some logging persists in [context/supabase-provider.tsx](context/supabase-provider.tsx:1); ensure no secrets or PII and restrict to development builds.
   - Action: Align with privacy logging standards.

Stage-by-stage conformance check

Stage 1 — Okta OIDC foundation
- Implemented: PKCE helper [typescript.oktaAuthorize()](auth/okta.ts:36); SecureStore adapter [auth/secure-storage.ts](auth/secure-storage.ts:1); Supabase client with persisted session [typescript.createClient()](config/supabase.ts:25); Okta sign-in/out [typescript.oktaSignIn()](context/supabase-provider.tsx:20) and [typescript.oktaSignOut()](context/supabase-provider.tsx:32); UI gate in [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1); deep-link scheme in [app.json](app.json:5).
- Gaps: Environment template completeness; device QA; local verifier and skew docs; logout robustness.

Stage 2 — Schema, directories, feature flags
- Implemented: Bootstrap and Stage 2 applied with verification SQL per [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1); indexes for stage_application, partner_org_id, derived_status, tenant_id per tracker notes.
- Gaps: None material observed in code; ensure features seeded per-tenant as new tenants appear.

Stage 3 — RBAC, RLS, Storage policies with CI tests
- Implemented: Helper [sql.using_rls_for_project()](supabase/migrations/20250817084500_stage3_policies.sql:9); verification and policy test suites in [docs/sql/stage3-verify.sql](docs/sql/stage3-verify.sql:1) and [docs/sql/stage3-policy-tests.sql](docs/sql/stage3-policy-tests.sql:1).
- Gaps: Confirm all policies actively reference the helper; expand negative cases as planned.

Stage 4 — Import endpoint, merge, membership materialization
- Implemented: Migration with lineage, anomalies, helper functions, merge RPC [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250817231500_stage4_import.sql:295), backfill [sql.fn_projects_membership_backfill()](supabase/migrations/20250817231500_stage4_import.sql:553), Edge function [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:1), verify and smoke tests.
- Gaps: Throttling/backpressure; anomalies dashboard/runbook; retention policy; minor upsert options cleanup.

Impacts and adjustments for Stage 5+
- Status recompute triggers
  - Add a call from [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250817231500_stage4_import.sql:295) to enqueue or invoke the deterministic status recompute for affected rows; ensure recompute is incremental and indexed.
- Business-day scheduler
  - Confirm the recompute cron at 00:05 tenant local aligns with import windows; skip unchanged rows.
- Index validation
  - Validate presence of a covering index for any derived status column used in filters; re-run [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1) or extend it.
- Observability
  - Add dashboards for recompute durations and failures; include correlation IDs from import to recompute.

Impacts and adjustments for Stage 6–8
- Stage 6
  - Enforce keyset pagination and virtualization in the list; gate CTAs via helpers documented in [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:298).
  - Attachments: enforce 25 MB client and server caps; perform server-side content-type checks before preview.
- Stage 7
  - Expand CI policy tests with targeted negative cases; run pen tests on Storage and RLS; wire Okta SIEM streaming validation.
- Stage 8
  - Formalize canary runbooks, including flag rollback paths and membership backfill execution using [sql.fn_projects_membership_backfill()](supabase/migrations/20250817231500_stage4_import.sql:553).

Exit criteria additions and clarifications
- Identity
  - Add exit tests for nonce/issuer failure, 5-minute skew tolerance, and logout redirect reliability.
- Import
  - Add exit tests for 1 rps rate limit, 429 backoff behavior, and anomalies visibility in dashboard.
- Directories
  - Add exit tests for ambiguous RM names and stewardship backfill flow.
- Observability
  - Verify SIEM pipeline ingestion and alerting thresholds.

Recommended action register
- Critical
  - A1 Remove [.env.example](.env.example:1) and update docs to reference [.env](.env:1) only for local/dev; confirm CI/workflows use repository secrets; note that PROJECTS_IMPORT_BEARER and SUPABASE_SERVICE_ROLE_KEY live exclusively in Supabase Function Secrets.
  - A2 Add post-login sync RPC and call sites after [typescript.oktaSignIn()](context/supabase-provider.tsx:20) and on refresh.
  - A3 Harden [typescript.oktaSignOut()](context/supabase-provider.tsx:32) with retry/timeout and explicit return URL.
  - A4 Implement per-tenant rate limiting in [typescript.handlePost()](supabase/functions/import-projects/index.ts:144) and document client backoff.
  - A5 Build anomalies dashboard and on-call runbook; link from tracker.
- High
  - B1 Add normalized unique index and audit fields to rm_directory.
  - B2 Add provider smoke-tests across environments; wire to CI.
  - B3 Document clock skew tolerance; add optional local ID token verification in [auth/okta.ts](auth/okta.ts:1).
  - B4 Add retention/cleanup job for staging_imports and import_anomalies.
  - B5 Enforce server-side content-type detection for previews.
- Medium
  - C1 Tidy [typescript.upsert()](supabase/functions/import-projects/index.ts:240) call to a single options object.
  - C2 Confirm all policies use [sql.using_rls_for_project()](supabase/migrations/20250817084500_stage3_policies.sql:9); extend verifications.
  - C3 Mandate keyset pagination in Stage 6 and validate index coverage.
- Low
  - D1 Remove or document unused accessToken in [typescript.oktaAuthorize()](auth/okta.ts:36).
  - D2 Normalize development-only logging and ensure no PII.

Decision: revisit Stages 1–4?
- Yes — targeted revisits recommended:
  - Stage 1: environment template completion; logout robustness; optional local verifier; post-login sync.
  - Stage 3: confirm policy helper reuse; expand negative tests.
  - Stage 4: add rate limiting, retention, anomalies dashboard; tidy upsert options.

Proposed timeline
- T+1 day: A1, C1, D1, D2.
- T+2–3 days: A2, A3, B2, B3.
- T+3–4 days: A4, A5, B1, B4, B5.
- Pre-Stage 5 start: confirm all Critical and High items closed; update tracker checklists and exit tests.

Appendix — cross-references
- Stage 1 code: [auth/okta.ts](auth/okta.ts:1), [context/supabase-provider.tsx](context/supabase-provider.tsx:1), [auth/secure-storage.ts](auth/secure-storage.ts:1), [config/supabase.ts](config/supabase.ts:1), [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1), [app.json](app.json:1).
- Stage 3 helper and tests: [supabase/migrations/20250817084500_stage3_policies.sql](supabase/migrations/20250817084500_stage3_policies.sql:1), [docs/sql/stage3-verify.sql](docs/sql/stage3-verify.sql:1), [docs/sql/stage3-policy-tests.sql](docs/sql/stage3-policy-tests.sql:1).
- Stage 4 migration and function: [supabase/migrations/20250817231500_stage4_import.sql](supabase/migrations/20250817231500_stage4_import.sql:1), [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:1), [docs/sql/stage4-verify.sql](docs/sql/stage4-verify.sql:1), [docs/sql/stage4-smoke-tests.sql](docs/sql/stage4-smoke-tests.sql:1).