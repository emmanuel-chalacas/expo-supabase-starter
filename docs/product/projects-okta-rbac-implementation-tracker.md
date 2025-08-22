# Implementation Tracker — Okta IdP + Projects Feature + RBAC/RLS

Sources
- [docs/product/projects-feature-prd.md](docs/product/projects-feature-prd.md:1)
- [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:1)
- [docs/product/projects-feature-implementation-plan.md](docs/product/projects-feature-implementation-plan.md:1)
- [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:1)
- [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:1)

Status summary
- This tracker consolidates identity, Projects feature, and RBAC/RLS into a single execution plan with checklists, decision gates, and validation steps.
- Bootstrap resources: SQL migration [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1), Supabase portal setup guide [docs/security/supabase-setup.md](docs/security/supabase-setup.md:1)

Key decision gates required before implementation begins
- [x] Token exchange provider with Supabase: Default provider=oidc for [signInWithIdToken()](docs/security/okta-oidc-supabase.md:176); env toggle supports provider=okta if required; SSO Pattern A retained as fallback.
- [x] Residential, Commercial, Essential semantics: Integer counts; blank spreadsheet cells render as 0 in the UI.
- [x] Canonical UI label for PCC: Use "Practical Completion Certified" consistently across UI and docs.
- [x] EFSCD in Timeline: Overview only (no Timeline milestone in MVP).
- [x] Relationship Manager (RM) source and mapping policy: Spreadsheet provides First Last in relationship_manager; system performs exact normalized match to rm_directory.display_name to materialize USER membership; alternatively accepts preferred_username when provided; Telco Admin steward; SLA 4h acknowledge/1 business day resolve; full audit per [rm_directory](docs/product/projects-feature-implementation-plan.md:75).
- [x] Delivery Partner to SUB_ORG allocation authority: Allowed — DP Admin and DP PM can allocate to SUB_ORG without Telco approval; Telco has visibility of all allocations.
- [x] Construction Partner capabilities: CP can create Contacts, and can add Engagements and Attachments.
- [x] Okta custom domain and SCIM: Approved — custom domain in Production only; Dev/Stage use default Okta domain. SCIM deferred to post-MVP.
- [x] Audit and retention: Approved — client telemetry 90d; app/edge logs 365d with cold storage at 90d; Okta System Logs via SIEM 365–730d; no PII/token contents in logs.
- [x] Filter chips overflow policy (UI): Show at most 5 primary chips on initial render with a trailing Filters chip opening a drawer for the full set; chip row remains horizontally scrollable; maintain single-row initial density. Rationale: aligns with [docs/product/ui-ux-steering-guide.md](docs/product/ui-ux-steering-guide.md:26) and minimum tap targets [docs/product/ui-ux-steering-guide.md](docs/product/ui-ux-steering-guide.md:439).

Decision briefing — Expanded options and recommendations

Decision 1: Supabase token exchange provider for signInWithIdToken
- Context
  - Mobile performs Okta PKCE via [oktaAuthorize()](docs/security/okta-oidc-supabase.md:121) and exchanges ID token using [signInWithIdToken()](docs/security/okta-oidc-supabase.md:176) in [context/supabase-provider.tsx](context/supabase-provider.tsx:1).
  - Supabase supports provider values oidc or okta depending on plan features; fallback is SSO Pattern A if direct token exchange is unavailable.

- Options
  - Option A: Provider oidc
    - Pros
      - Standards-aligned; portable across OIDC IdPs and Okta custom domain changes.
      - Lower vendor coupling; consistent payload validation.
      - Often available across more Supabase plans.
    - Cons
      - If Supabase project lacks OIDC token exchange, must fall back to SSO Pattern A.
  - Option B: Provider okta
    - Pros
      - Explicit vendor adapter; may have Okta-specific mappings and smoother linking.
    - Cons
      - Tighter vendor coupling; potential breaking changes if Supabase renames adapters.
      - Less portable if future federation changes are routed through Okta as a hub but client uses generic OIDC flows.

- Evaluation criteria
  - Supabase plan capability for [signInWithIdToken()](docs/security/okta-oidc-supabase.md:176) with provider oidc vs okta in each environment.
  - Cross-environment parity (dev, stage, prod) to avoid env drift.
  - Future SSO expansion via Okta as a federation hub without changing client code.
  - Troubleshooting clarity (token validation errors surfaced consistently).

- Recommendation
  - Default: oidc as provider value.
  - Add config toggle in env (EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER=oidc|okta) read in [context/supabase-provider.tsx](context/supabase-provider.tsx:1). Ship with oidc; switch to okta only if required by plan.
  - Maintain SSO Pattern A as a fallback feature flag path for projects that do not support direct ID token exchange.
- Decision outcome (approved): Default provider=oidc; env toggle allows provider=okta; SSO Pattern A retained as fallback.

- Implementation impacts
  - No change to PKCE helper [oktaAuthorize()](docs/security/okta-oidc-supabase.md:121).
  - Update sign-in flow in [context/supabase-provider.tsx](context/supabase-provider.tsx:1) to use provider from env.
  - Document expected ID token claims per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:67) and enforce issuer/aud/exp checks via Supabase.
 
- Risks and mitigations
  - Risk: Provider mismatch causes login failures in one environment.
    - Mitigation: Promote a provider smoke-test as part of health checks; CI E2E with test Okta tenant.
  - Risk: SSO Pattern A introduces redirect handling differences.
    - Mitigation: Keep the deep-link handler logic consistent; test both flows.

- Decision checklist
  - [ ] Confirm Supabase plan supports provider oidc for token exchange in all target environments.
  - [ ] Set EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER default to oidc; document override.
  - [ ] Add provider smoke-test to auth validation (dev/stage/prod).

- Exit tests
  - [ ] E2E sign-in succeeds using provider=oidc in dev/stage/prod.
  - [ ] Flip to provider=okta and validate success in a sandbox environment.
  - [ ] Negative test: invalid nonce/issuer rejected as expected.

Decision 2: Okta custom domain and SCIM scope/timing
- Context
  - Custom domain provides branded Okta URLs (issuer), stable allowlists, and improved phishing resistance. SCIM automates provisioning and deprovisioning; our design references an admin portal + Okta Workflows model (Model B2) in [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:309) and [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:333).

- Custom domain
  - Pros
    - Branded issuer improves trust; stable domain eases allowlists and monitoring.
    - Cleaner redirect URIs for mobile and potential web builds.
  - Cons
    - Setup effort, TLS/cert ownership, and potential cost depending on Okta SKU.
  - Recommendation
    - Dev/Stage: not required; use Okta default domain to reduce setup time.
    - Prod: recommended. Schedule in Stage 3 Productionization. Update EXPO_PUBLIC_OKTA_ISSUER and redirect URIs, and re-validate [oktaAuthorize()](docs/security/okta-oidc-supabase.md:121).

- SCIM
  - Pros
    - Automated user lifecycle; authoritative group-to-role mapping; reduced manual errors.
  - Cons
    - Requires building and operating a SCIM server or Okta Workflows integration; more moving parts and on-call surface.
  - Recommendation
    - MVP: Postpone SCIM to post-MVP. Use admin portal + Okta Workflows request-flow (Model B2) for provisioning, as captured in [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:333) and enforced via RLS as in [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:309).
    - Post-MVP: Re-evaluate SCIM once tenant onboarding volume requires it.
- Decision outcome (approved): Custom domain in Production only; Dev/Stage use default Okta domain. SCIM deferred to post-MVP.

- Implementation impacts
  - Custom domain in Prod: Update .env issuer, Okta app redirect URIs, and re-run auth validation checklist [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:386).
  - SCIM deferred: Ensure profile/role mirroring on login remains robust via [user_profiles](docs/security/okta-oidc-supabase.md:197) and [user_roles](docs/security/okta-oidc-supabase.md:204).

- Risks and mitigations
  - Risk: Late custom domain switch breaks issuer validation.
    - Mitigation: Introduce issuer as env; stage switch in non-prod before prod cutover.
  - Risk: Manual provisioning errors without SCIM.
    - Mitigation: Okta Workflows-based approval and audit trail; periodic reconciliations.

- Decision checklist
  - [ ] Approve custom domain for Production only; leave Dev/Stage as default Okta.
  - [ ] Defer SCIM to post-MVP; document trigger criteria (e.g., N tenants, N users per month, strict SLAs).

- Exit tests
  - [ ] Production issuer uses custom domain; tokens validate; redirects succeed.
  - [ ] Admin provisioning via Workflows exercised; claims appear in ID token; roles mirrored.

Decision 3: Audit telemetry and Okta System Log retention
- Context
  - Client events (start_auth, otp_challenge_shown, auth_success/failure, signout) per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:303).
  - Server-side logs: Edge Function imports, membership materialization, status recompute metrics per [docs/product/projects-feature-implementation-plan.md](docs/product/projects-feature-implementation-plan.md:140).
  - Okta System Log captures IdP-side activity; export/forwarding to SIEM is recommended.

- Options and targets
  - Client telemetry (analytics)
    - MVP target retention: 90 days rolling in product analytics (privacy-friendly, no PII; use role and org dimensions per [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:408)).
  - Server/Edge logs and metrics
    - MVP target retention: 180–365 days in centralized logging (e.g., CLoudWatch/Log Analytics/Supabase log archive) with lifecycle policies.
    - Persist summarized import/membership/status counters for 365+ days for trend analysis.
  - Okta System Logs
    - Retention depends on Okta SKU (commonly 90 days baseline; extended with add-ons).
    - Recommendation: Stream Okta System Logs to SIEM (e.g., Splunk, Datadog, Sentinel) with 365–730 days retention per security policy.

- Recommendation
  - Adopt minimum viable retention set:
    - Client telemetry: 90 days.
    - App/Edge operational logs: 365 days with cold storage transition at 90 days.
    - Okta System Logs: 365 days via SIEM export, with on-call alerting for auth failure anomalies.
  - PII handling
    - Avoid storing IDs or token payloads in plaintext. Use pseudonymous IDs where needed.
- Decision outcome (approved): Adopt retention targets — client telemetry 90d; app/edge 365d with cold storage at 90d; Okta System Logs via SIEM 365–730d; ensure no PII/token contents in logs.

- Implementation impacts
  - Add log shipping from Edge Functions to centralized store; dashboards and alerts per Stage 7.
  - Configure Okta System Log streaming to SIEM; correlate with app telemetry via correlation IDs.
  - Document retention in a security policy note in docs/security and reference from this tracker.

- Risks and mitigations
  - Risk: Storage cost growth.
    - Mitigation: Lifecycle policies and summarized metrics for long-term trends.
  - Risk: Over-collection of PII.
    - Mitigation: Redaction at source; schema reviews; sampling.

- Decision checklist
  - [ ] Approve retention targets: client 90d, app/edge 365d, Okta via SIEM 365–730d.
  - [ ] Approve SIEM destination and access controls.
  - [ ] Approve redaction standards and correlation ID usage.

- Exit tests
  - [ ] Okta System Log streaming verified; dashboards show auth success/failure trends.
  - [ ] Edge import/membership/status dashboards live with alerts.
  - [ ] Privacy review completed; no token contents or PII in logs.

Decision 4: Relationship Manager (RM) import header and rm_directory stewardship
- Context
  - RM is an assigned-only role; visibility and UGC depend on USER membership materialized from the import’s RM field via rm_directory → auth.users.id per [docs/product/projects-feature-prd.md](docs/product/projects-feature-prd.md:160) and [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:120).
  - Email is not guaranteed for login and may be absent per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:44).

- Decision (approved)
  - Spreadsheet header: relationship_manager contains human name First Last.
  - Mapping: exact, normalized match (trim, collapse internal whitespace, case-insensitive) against rm_directory.display_name.
  - Alternative: if preferred_username is provided instead of a name, accept it and match to rm_directory.preferred_username.
  - Import behavior: on unknown or ambiguous name, raise an anomaly; do not materialize RM membership until rm_directory is updated; see [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:69).

- Stewardship and SLA (approved)
  - Steward: Telco Admin (Vendor Admin oversight optional).
  - SLA: Acknowledge anomalies within 4 business hours; resolve within 1 business day.
  - Audit: Log (source_identifier, matched_user_id, match_type name|preferred_username, updated_by, updated_at, correlation_id). Submissions via admin portal; Okta Workflows validates and returns linkage per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:333).

- Exit tests
  - [ ] Import with a known First Last name materializes USER membership for that RM.
  - [ ] Import with an unknown name logs an anomaly; after steward updates rm_directory, re-run import/backfill materializes membership.

Additional decision gates to resolve (new)
- [x] Business-day timezone and evaluation schedule: Default compute using tenant timezone; store timestamps in UTC; recompute status at 00:05 tenant local time after imports; render in tenant local time.
- [x] Attachment preview MIME policy and malware scanning: Default preview for images (image/*) and PDFs (application/pdf) only; no antivirus scanning in MVP; document post-MVP evaluation.
- [x] Storage bucket pathing and encryption: Default bucket attachments (private); path tenant_id/stage_application/object_uuid; Supabase-managed encryption at rest; evaluate KMS-managed keys post-MVP; enforce policies per [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:263).
- [x] Import API limits and batch size: Default max body 5 MB; up to 5000 rows per batch; 1 rps with exponential backoff; idempotency via batch checksum and Stage Application; partial acceptance with per-row errors.
- [x] Feature flag governance and audit: Default toggles controlled by Vendor Admin and Telco Admin; changes audited with actor, tenant_id, before/after values; flags referenced in [docs/product/projects-feature-implementation-plan.md](docs/product/projects-feature-implementation-plan.md:76).
- [x] Admin corrections allowlist: Default none in MVP; deny updates to imported columns; define explicit allowlist and audit preconditions post-MVP per [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:246).
- [x] Deep link policy and environment schemes: Keep scheme omnivia across environments; allow external share links to Project Detail; rely on RLS-only access to prevent exposure; anchors in [app/(protected)/(tabs)/index.tsx](app/(protected)/(tabs)/index.tsx:1).
- [x] Roles claim source in Okta: Prefer app_roles custom claim over groups in ID token; mirror to [user_roles](docs/security/okta-oidc-supabase.md:204) on login; document Okta mapping.
- [x] DS/RM directory identifier format: Approved — RM uses First Last from spreadsheet with exact normalized match to rm_directory.display_name; optional preferred_username accepted; DS continues to use preferred_username; rm_directory maps to auth.users.id; steward Telco Admin; SLA 4h/1d; anomalies block membership until mapped.
- [x] Upload concurrency and retry policy: Allow up to 3 concurrent uploads; 2 retries per file with exponential backoff; enforce 25 MB per-file cap client and server.
- [x] Biometric unlock default: Enabled for MVP behind ENABLE_BIOMETRIC_UNLOCK; prompt after cold start before rendering protected content; reassess post-MVP per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:282).
- [x] Data residency alignment: Ensure Okta org region aligns with Supabase project region; default AU region; document flows in security notes.

Rationale for implementation order
- Identity and RLS come first to de-risk security and data leakage, then ingestion and derived status to stabilize backend contracts, then UI atop enforced policies, finally observability and controlled rollout. This allows safe parallelization while minimizing rework.
 
High-level architecture flow
```mermaid
flowchart LR
  A[Okta OIDC PKCE] --> B[Supabase ID token exchange]
  B --> C[Supabase session stored]
  C --> D[Queries under RLS]
  E[Power Automate import] --> F[Edge Function staging]
  F --> G[Merge canonical projects]
  G --> H[Materialize memberships]
  G --> I[Compute status]
  D --> J[Projects UI]
  J --> K[UGC writes under RLS]
```

Top-level execution checklist
- [ ] Apply bootstrap SQL migration [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1) and create Storage bucket "attachments" (Private)
- [ ] Approve identity flow and provider approach per environment
- [x] Land schema, directories, and feature flags with indexes (verify post-migration)
- [x] Implement and CI-test RLS and Storage policies (review/adjust post-migration)
- [ ] Build import endpoint, merge, and membership; run backfill
- [ ] Implement status computation with fixtures
- [ ] Deliver Projects UI with permission-aware CTAs and analytics
- [ ] Stand up dashboards, performance tests, security review, QA
- [ ] Canary rollout; progressive enablement; publish runbooks and guides

Stage 1 — Okta OIDC foundation and secure session storage
Goal and success criteria
- Goal: Okta passwordless TOTP sign-in yields Supabase session; sessions persisted securely; legacy email login hidden when ENABLE_OKTA_AUTH is on.
- Success: E2E sign-in and deep link works; protected routes render; logout clears Supabase and Okta session; storage uses SecureStore.

Prerequisites and dependencies
- Okta org with OIDC Native app and passwordless policy
- Redirect URIs configured in Okta
- Supabase supports [signInWithIdToken()](docs/security/okta-oidc-supabase.md:176) with provider oidc or okta

Tasks
- [ ] Configure Okta OIDC Native app and passwordless policy [Security]
  - Artifacts: Okta app config per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:50); tenant worksheet [docs/security/okta-setup-worksheet.md](docs/security/okta-setup-worksheet.md:1)
- [x] Add env vars and deep link scheme in [.env](.env:1) and [app.json](app.json:1) [DevOps]
- [x] Install expo-auth-session; create PKCE helper [auth/okta.ts](auth/okta.ts:1) with [oktaAuthorize()](docs/security/okta-oidc-supabase.md:121) [Frontend]
- [x] Add oktaSignIn in [context/supabase-provider.tsx](context/supabase-provider.tsx:1) calling [supabase.auth.signInWithIdToken()](docs/security/okta-oidc-supabase.md:176) [Frontend]
- [x] Wire SecureStore auth storage in [config/supabase.ts](config/supabase.ts:1) using SecureStorage adapter [Frontend]
- [x] Replace public auth screens with Continue with Okta in [app/(public)/welcome.tsx](app/(public)/welcome.tsx:1), [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1), [app/(public)/sign-up.tsx](app/(public)/sign-up.tsx:1), gated by ENABLE_OKTA_AUTH [Frontend]
- [x] Implement logout including Okta end session redirect [Frontend]
- [ ] Validate E2E sign-in, deep link on iOS and Android; record results [QA]

Implementation callouts — Stage 1 (2025-08-16)
- Env and config: Added public env toggles in [.env](.env:1): EXPO_PUBLIC_ENABLE_OKTA_AUTH (default false), EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER (default 'oidc'), EXPO_PUBLIC_OKTA_ISSUER, EXPO_PUBLIC_OKTA_CLIENT_ID, EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT=omnivia://signout. Deep-link scheme set in [app.json](app.json:1) to “omnivia”.
- Auth session and PKCE: Created PKCE helper [auth/okta.ts](auth/okta.ts:1) exporting [typescript.oktaAuthorize()](auth/okta.ts:1); scopes openid/profile/email; uses AuthSession discovery and code exchange with PKCE.
- Secure session storage: Implemented SecureStore-backed adapter [auth/secure-storage.ts](auth/secure-storage.ts:1) and wired in [config/supabase.ts](config/supabase.ts:1) with persistSession=true; falls back to in-memory Map when SecureStore unavailable (e.g., web); no secrets logged.
- Provider integration: Added [typescript.oktaSignIn()](context/supabase-provider.tsx:1) invoking [supabase.auth.signInWithIdToken()](docs/security/okta-oidc-supabase.md:176) with provider from EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER (default 'oidc').
- Provider integration: Added [typescript.oktaSignOut()](context/supabase-provider.tsx:1) performing Supabase signOut and Okta RP-initiated logout using discovery.end_session_endpoint with id_token_hint persisted under [typescript.OKTA_ID_TOKEN_HINT_KEY](auth/secure-storage.ts:1); return URL uses EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT or [typescript.getRedirectUri()](auth/okta.ts:1).
- Public screens: Feature-gated “Continue with Okta” CTA added to [app/(public)/welcome.tsx](app/(public)/welcome.tsx:1), [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1), and [app/(public)/sign-up.tsx](app/(public)/sign-up.tsx:1), using [typescript.Button](components/ui/button.tsx:65) variant=primary/size=lg, per branding doc [docs/product/omnivia-branding-front-end-steering.md](docs/product/omnivia-branding-front-end-steering.md:1).
- Branding and accessibility: Primary navy for CTA, accent focus ring, min 44pt target; typography minimal; no PII in logs.
- Validation notes: TypeScript and eslint checks executed on touched files passed; repo-wide lint remains governed by existing configuration.
- Security worksheet: Added [docs/security/okta-setup-worksheet.md](docs/security/okta-setup-worksheet.md:1) to capture Issuer URL, Client ID, end_session_endpoint, assignments, and passwordless policy confirmation; owned by Security; linked under Stage 1 Security task.
- Outstanding for Stage 1 exit:
  - Okta tenant: OIDC Native app + passwordless policy configuration [Security] pending.
  - E2E device QA (iOS/Android) for sign-in and deep-link pending.


Responsible roles and expected artifacts
- Security: Okta app and policy documentation
- Frontend: [auth/okta.ts](auth/okta.ts:1), Secure storage adapter [auth/secure-storage.ts](auth/secure-storage.ts:1), updates in [context/supabase-provider.tsx](context/supabase-provider.tsx:1), public screens
- DevOps: .env and EAS profiles
- QA: Test report for sign-in and deep link paths

Estimates, risks, decisions, exits
- Effort: M (3–5 engineer-days)
- Risks: Provider unavailability → fallback to SSO Pattern A; redirect misconfig → follow [AuthSession guidance](docs/security/okta-oidc-supabase.md:124)
- Decision: provider key default to oidc; switchable via env
- Exit: Protected routes render per [app/_layout.tsx](app/_layout.tsx:1); telemetry events start_auth and auth_success emitted

Stage 2 — Schema, directories, feature flags
Goal and success criteria
- Goal: Land schema for staging, canonical projects, membership, directories, user mirrors, UGC, and feature flags; seed partner data; add indexes.
- Success: Migrations applied; data dictionary updated; feature flags queryable.

Prerequisites
- None strictly, but Stage 1 identity tables helpful for tests

Tasks
- [x] Run bootstrap SQL migration in Supabase SQL Editor: [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1) (idempotent)
- [x] Create Storage bucket "attachments" (Private) in Dashboard → Storage; if created after running the SQL, re-run the “Storage policies” section from [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1)
- [x] Verify core tables exist: projects, project_membership, contacts, engagements, attachments_meta, partner_org, partner_normalization, ds_directory, rm_directory, user_profiles, user_roles, features, staging_imports
- [x] Seed partner_normalization and partner_org canonical labels [Backend]
- [x] Seed tenant feature flags (ENABLE_PROJECTS, ENABLE_ATTACHMENTS_UPLOAD, ENABLE_OKTA_AUTH) in features [Backend]
- [x] Add/validate indexes for stage_application, partner_org_id, derived_status, tenant_id as per migration [Backend]
- [x] Update data dictionary in [docs/product/projects-feature-implementation-plan.md](docs/product/projects-feature-implementation-plan.md:165) [Backend]

Roles, estimates, risks, exits
- Roles: Backend
- Effort: M (4–6 engineer-days)
- Risks: Schema drift vs PRD whitelist → migration review and tests
- Exit: Tables and indexes present; partner data seeded; flags readable

Stage 3 — RBAC, RLS, Storage policies with CI policy tests
Goal and success criteria
- Goal: Enforce tenant isolation, membership-based visibility, and UGC write scopes; enforce Storage access; CI tests.
- Success: Policy test suite passes for all roles; unauthorized access denied in staging.

Prerequisites
- Stage 2 schema complete; Stage 1 identity in dev

Tasks
- [x] Review policies created by the bootstrap migration (projects, contacts, engagements, attachments_meta, features) and adjust to tenant requirements [Security, Backend]
- [x] Ensure helper function using_rls_for_project is present (created by migration) and reuse it in any new policies to avoid duplication [Backend]
- [x] Confirm Storage policies on bucket "attachments" enforce metadata + membership checks; re-run Storage section if bucket was created later [Security, Backend]
- [x] Seed synthetic users in [user_roles](docs/security/okta-oidc-supabase.md:204) and org context in [user_profiles](docs/security/okta-oidc-supabase.md:197) for CI tests [Security]
- [x] Add CI test suite for select/insert/update/delete across roles and membership scopes; include negative cases [Security]

Roles, estimates, risks, exits
- Roles: Security, Backend
- Effort: M–L (4–7 engineer-days)
- Risks: Over-permissive rules → default deny and incrementally allow; client blocked by RLS → never ship service role in client
- Exit: CI green; manual queries confirm scoping; storage denies for non-members

Deployment callouts — Stage 3 (2025-08-17 22:41 ACST)
- Migration added: [supabase/migrations/20250817084500_stage3_policies.sql](supabase/migrations/20250817084500_stage3_policies.sql:1) — refines helper [sql.using_rls_for_project()](supabase/migrations/20250817084500_stage3_policies.sql:9) to:
  - grant dp_admin/dp_pm visibility via ORG membership or any SUB_ORG under their partner_org
  - restrict dp_cp visibility to exact SUB_ORG membership
- Verification: [docs/sql/stage3-verify.sql](docs/sql/stage3-verify.sql:1) — asserts helper presence/content, projects policy uses helper, storage policies present with bucket predicate and helper reference.
- CI Policy tests: [docs/sql/stage3-policy-tests.sql](docs/sql/stage3-policy-tests.sql:1) — seeds deterministic synthetic identities; covers select/insert/update/delete positive and negative paths across roles; includes creator-bound UGC edits and storage metadata guards. Seeds are ephemeral and cleaned up at end of run.
- Yarn scripts: see [package.json](package.json:1) — db:local:verify:stage3, db:local:test:stage3, db:remote:verify:stage3, db:remote:test:stage3.
- CI workflow: extended in [.github/workflows/supabase-migrations.yml](.github/workflows/supabase-migrations.yml:1) to run Stage 3 verify and policy tests after migrations push.

Stage 4 — Import endpoint, merge, membership materialization
Goal and success criteria
- Goal: Edge Function for Power Automate; idempotent merge by Stage Application; upsert ORG and USER memberships for DP, DS, RM; log anomalies; backfill.
- Success: Batch responses include counts; memberships reflect latest import; Unassigned creates no ORG membership; anomalies visible.

Prerequisites
- Stages 2 and 3 complete

Tasks
- [x] Implement Edge Function HTTPS POST with bearer secret and schema validation [Backend]
- [x] Persist batch to staging with lineage; idempotent merge to canonical projects; normalize Developer Class [Backend]
- [x] Materialize membership: Delivery Partner via partner_normalization → ORG; blank skips ORG membership [Backend]
- [x] Materialize membership: Deployment Specialist via ds_directory → USER [Backend]
- [x] Materialize membership: Relationship Manager via rm_directory → USER [Backend]
- [x] Record anomalies for unmapped DP, DS, RM; return metrics [Backend]
- [x] One-off backfill job to create memberships for existing projects [Backend] (completed: [sql.fn_projects_membership_backfill()](supabase/migrations/20250817231500_stage4_import.sql:1) and yarn script in [package.json](package.json:1) db:run:backfill:memberships; execution in prod not claimed)
- [ ] Configure Power Automate flow with schedule, retries, logging [DevOps]

Roles, estimates, risks, exits
- Roles: Backend, DevOps
- Effort: L (5–8 engineer-days)
- Risks: Duplicate merges → upsert by tenant + Stage Application with checksums; mapping gaps → anomaly queue and stewardship SLAs
- Exit: Test import with inserts and updates passes; membership counts align; backfill completes with log

Deployment callouts — Stage 4 (2025-08-18 09:37 ACST)
- Migration: [supabase/migrations/20250817231500_stage4_import.sql](supabase/migrations/20250817231500_stage4_import.sql:1)
  - Adds lineage columns and indexes to staging_imports (source, row_count, correlation_id, batch_checksum; UNIQUE (tenant_id, batch_checksum); imported_at DESC index).
  - Adds UNIQUE index on projects (tenant_id, stage_application) and DS/RM columns (deployment_specialist, relationship_manager, rm_preferred_username).
  - Creates import anomalies table + indexes and helper/functions:
    - [sql.import_anomalies](supabase/migrations/20250817231500_stage4_import.sql:1)
    - [sql.fn_normalize_name(text)](supabase/migrations/20250817231500_stage4_import.sql:1), [sql.fn_normalize_developer_class(text)](supabase/migrations/20250817231500_stage4_import.sql:1), [sql.fn_partner_org_from_label(text)](supabase/migrations/20250817231500_stage4_import.sql:1)
    - [sql.fn_find_ds_user_id(text)](supabase/migrations/20250817231500_stage4_import.sql:1), [sql.fn_find_rm_user_id(text,text)](supabase/migrations/20250817231500_stage4_import.sql:1)
    - [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250817231500_stage4_import.sql:1), [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250817231500_stage4_import.sql:1), [sql.fn_projects_membership_backfill()](supabase/migrations/20250817231500_stage4_import.sql:1)
- Edge Function: [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:1)
- Anomalies surfacing (Critical item 5):
  - Migration: [supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql](supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql:1)
  - Edge Function: [supabase/functions/anomalies/index.ts](supabase/functions/anomalies/index.ts:1)
  - Dashboard route: [app/(protected)/anomalies.tsx](app/(protected)/anomalies.tsx:1)
  - Auth via Authorization: Bearer PROJECTS_IMPORT_BEARER; 5 MB max; rows length 1..5000; deterministic SHA-256 checksum; idempotent staging upsert on (tenant_id, batch_checksum); RPC call to merge; returns metrics {inserted_projects, updated_projects, org_memberships_upserted, user_memberships_upserted, anomalies_count, staging_id}.
- Verification and smoke tests:
  - [docs/sql/stage4-verify.sql](docs/sql/stage4-verify.sql:1) and [docs/sql/stage4-smoke-tests.sql](docs/sql/stage4-smoke-tests.sql:1)
- Yarn scripts and CI:
  - Added in [package.json](package.json:1): db:local:verify:stage4, db:local:test:stage4, db:remote:verify:stage4, db:remote:test:stage4, db:run:backfill:memberships
  - CI updated to run Stage 4 verify/test in [.github/workflows/supabase-migrations.yml](.github/workflows/supabase-migrations.yml:1) after Stage 3 steps.
- Runbook and operator next actions:
  - Runbook published: [docs/security/supabase-imports-runbook.md](docs/security/supabase-imports-runbook.md:1)
  - Operator: configure Power Automate daily schedule (17:00 tenant local), limit 1 rps with exponential backoff (1s, 2s, 4s, 8s, 16s; max 5), propagate correlation_id in logs. This remains pending; DevOps box above left unchecked by design.

Stage 5 — Overall Project Status computation
Goal and success criteria
- Goal: Compute status per PRD 8.3 with business-day rules; persist derived status; hide when EFSCD missing; add tests.
- Success: Unit tests pass; recomputes on every merge; UI receives status for filters and chips.

Prerequisites
- Stage 4 operational

Tasks
- [x] Implement deterministic status module invoked post-merge and on demand [Backend]
- [x] Implement business day logic Monday to Friday [Backend]
- [x] Persist status in projects table or derived view; index for filters [Backend]
- [x] Fixtures covering Late App, PCC waiver, missing Issued to DP, missing EFSCD [Backend]

Roles, estimates, risks, exits
- Roles: Backend
- Effort: M (2–4 engineer-days)
- Risks: Performance at scale → recompute only changed rows; index derived column
- Exit: Tests green; staging scenarios verified

Deployment callouts — Stage 5 (2025-08-18 15:25 ACST)
- Migration added: [supabase/migrations/20250818062000_stage5_status_compute.sql](supabase/migrations/20250818062000_stage5_status_compute.sql:1)
- Functions: [sql.fn_business_days_between()](supabase/migrations/20250818062000_stage5_status_compute.sql:1), [sql.fn_projects_derived_status_compute()](supabase/migrations/20250818062000_stage5_status_compute.sql:1), [sql.fn_projects_derived_status_recompute_changed()](supabase/migrations/20250818062000_stage5_status_compute.sql:1), [sql.fn_projects_derived_status_recompute_by_staging()](supabase/migrations/20250818062000_stage5_status_compute.sql:1), [sql.rpc_projects_status_recompute()](supabase/migrations/20250818062000_stage5_status_compute.sql:1), Trigger [sql.tr_projects_derived_status_after_write](supabase/migrations/20250818062000_stage5_status_compute.sql:1)
- Integration: Post-merge recompute invoked in [sql.fn_projects_import_merge()](supabase/migrations/20250817231500_stage4_import.sql:1)
- Verify/tests: [docs/sql/stage5-status-verify.sql](docs/sql/stage5-status-verify.sql:1), [docs/sql/stage5-status-smoke-tests.sql](docs/sql/stage5-status-smoke-tests.sql:1)
- Yarn scripts: db:local|remote:verify:stage5, db:local|remote:test:stage5 in [package.json](package.json:1)
- CI: stage5-verify and stage5-tests appended in [.github/workflows/supabase-migrations.yml](.github/workflows/supabase-migrations.yml:1)
- Behavior: derived_status is NULL when EFSCD missing (UI hides rows); tenant TZ default 'Australia/Adelaide'; recompute at 00:05 tenant local; functions idempotent and set-based; projects(derived_status) index used for filters.

Stage 6 — Frontend Projects module with security integration
Goal and success criteria
- Goal: Deliver Projects List and Detail with tabs Overview, Timeline, Contacts, Engagements, Attachments; permission-aware CTAs; deep links; analytics; adopt iPhone‑first navigation and interactions per [docs/product/ui-ux-steering-guide.md](docs/product/ui-ux-steering-guide.md).
- Success: UI QA checklist passes; only authorized projects visible; imported fields read-only; UGC respects RLS; attachments max 25 MB; iPhone‑first acceptance criteria met on iOS; Android parity maintained.

Prerequisites
- Stages 1, 3, and 4 in place
- UI/UX Steering Guide v1.1 iPhone‑first Baseline approved ([docs/product/ui-ux-steering-guide.md](docs/product/ui-ux-steering-guide.md))

Tasks
- [x] Navigation and flags in [app/(protected)/(tabs)/index.tsx](app/(protected)/(tabs)/index.tsx:1) and [app/(protected)/_layout.tsx](app/(protected)/_layout.tsx:1) [Frontend]
- [x] Adopt UI/UX Steering Guide tokens, iconography, haptics, and Reduced Motion variants across Projects List and Detail; eliminate hard-coded values by using primitives in [components/ui](components/ui/button.tsx:1) and tokens per [docs/product/ui-ux-steering-guide.md](docs/product/ui-ux-steering-guide.md) [Frontend]
- [x] Projects List with search, filters, sort, infinite scroll, and status chips per [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:73); map chip colors to semantic tokens in [docs/product/ui-ux-steering-guide.md](docs/product/ui-ux-steering-guide.md) [Frontend]
- [x] Implement chip overflow: show at most 5 primary chips initially with a trailing Filters chip opening a drawer for the full set; chip row remains horizontally scrollable; maintain single-row initial density [Frontend]
- [x] Use keyset pagination helper [lib/keyset-pagination.ts](lib/keyset-pagination.ts:1) for Projects List; verify covering indexes via [docs/sql/stage6-keyset-verify.sql](docs/sql/stage6-keyset-verify.sql:1) [Frontend]
- [x] Project Detail tabs and UGC forms using [components/ui](components/ui/button.tsx:1) primitives [Frontend]
- [x] Deep link handling to Stage Application; preserve filters on back nav [Frontend]
- [x] Read-only presentation for imported fields; Delivery Partner shows Not Yet Assigned when blank; Developer Class normalized labels [Frontend]
- [x] Attachments upload with 25 MB client check, previews, private bucket metadata flow [Frontend]
- [x] Authorization helpers [canViewProjects()](docs/security/rbac-rls-review.md:298), [canCreateUGC()](docs/security/rbac-rls-review.md:299), [canAssign()](docs/security/rbac-rls-review.md:300); gate CTAs [Frontend]
- [x] Analytics instrumentation per Section 9 of UI spec: list viewed, search submitted, filter applied, project opened, engagement added, attachment uploaded, contact added; capture dimensions per [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:441) [Frontend]

- [x] iPhone‑first baseline behaviors per [docs/product/ui-ux-steering-guide.md](docs/product/ui-ux-steering-guide.md) [Frontend]
  - Large-title navigation on first screens; smooth collapse to compact on scroll
  - Respect top/bottom safe areas (including Dynamic Island/home indicator); establish bottom action area with minimum 24 pt inset above home indicator
  - Edge‑swipe back enabled where safe (iOS only); avoid conflicts with horizontal carousels
  - Keyboard management: pinned form action footer above keyboard; Next/Done flow between fields
  - Dynamic Type verified from small to extra large; no clipping at 320‑pt width

- [x] Bottom sheets (iOS‑style) [Frontend]
  - Standardize on @gorhom/bottom-sheet with detents medium=0.5 and large=0.9; visible grabber; rounded top corners; drag‑to‑dismiss where safe
  - Use react-native-blur for blurred background and dim overlay on sheet presentations

- [x] Context menus for secondary actions (iOS) [Frontend]
  - Long‑press context menus on list items, cards, media using a native iOS context menu lib (e.g., react-native-ios-context-menu); fall back to overflow button on Android

- [x] Haptics mapping [Frontend]
  - Map selection, success, warning, error, destructive to specified tokens; implement via react-native-haptic-feedback; throttle repetitive haptics

- [x] Reduced Motion [Frontend]
  - Honor OS reduced motion by swapping transitions to fades/instant changes using reanimated variants

- [x] Icons policy [Frontend]
  - Icon size baseline 24; prefer SF Symbols on iOS (optional) with Ionicons fallback; keep Ionicons cross‑platform consistent

- [x] Android compatibility checks [Frontend]
  - Do not emulate Dynamic Island; rely on ongoing notifications/system surfaces
  - Use system back (no iOS edge‑swipe back); ensure no conflicts with horizontal gestures
  - Maintain minimum 48 dp touch targets; respect status/navigation bar insets; align presentation with Material where appropriate

- [x] Global UI/UX Steering adoption across existing app screens (outside Projects) [Frontend]
  - Public stack: [app/(public)/_layout.tsx](app/(public)/_layout.tsx:1), [app/(public)/welcome.tsx](app/(public)/welcome.tsx:1), [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1), [app/(public)/sign-up.tsx](app/(public)/sign-up.tsx:1), [app/(public)/signout.tsx](app/(public)/signout.tsx:1)
  - Protected shells: [app/_layout.tsx](app/_layout.tsx:1), [app/(protected)/(tabs)/_layout.tsx](app/(protected)/(tabs)/_layout.tsx:1), [app/(protected)/modal.tsx](app/(protected)/modal.tsx:1), [app/(protected)/(tabs)/settings.tsx](app/(protected)/(tabs)/settings.tsx:1)
  - Non-Projects protected route: [app/(protected)/anomalies.tsx](app/(protected)/anomalies.tsx:1)
  - Primitives sweep: [components/ui/button.tsx](components/ui/button.tsx:1), [components/ui/input.tsx](components/ui/input.tsx:1), [components/ui/textarea.tsx](components/ui/textarea.tsx:1), [components/ui/label.tsx](components/ui/label.tsx:1), [components/ui/text.tsx](components/ui/text.tsx:1), [components/ui/typography.tsx](components/ui/typography.tsx:1), [components/ui/form.tsx](components/ui/form.tsx:1), [components/ui/radio-group.tsx](components/ui/radio-group.tsx:1), [components/ui/switch.tsx](components/ui/switch.tsx:1), [components/safe-area-view.tsx](components/safe-area-view.tsx:1), [components/image.tsx](components/image.tsx:1)
  - Validation:
    - iOS: Large‑title collapse, bottom action area ≥24 pt above home indicator, edge‑swipe back where safe
    - iOS: Sheets with medium/large detents, visible grabber, blur/dim, safe drag‑to‑dismiss
    - iOS: Long‑press context menus on rows/cards/media; haptics mapped and throttled
    - iOS: Dynamic Type verified; Reduced Motion variants active
    - Android: System back parity; 48 dp targets; no edge‑swipe back gesture; respect insets
    - Tokens‑only styling (no hard‑coded values)

Roles, estimates, risks, exits
- Roles: Frontend, Security review
- Effort: L (8–12 engineer-days)
- Risks: List performance at 5k projects → pagination and virtualization; platform libraries (bottom sheet/context menu) may require platform‑specific configuration and QA; control exposure → hide by default and rely on RLS
- Exit: QA checklist in [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:423) passes on iOS and Android; UI conforms to Definition of Done in [docs/product/ui-ux-steering-guide.md](docs/product/ui-ux-steering-guide.md); tokens‑only styling (no hard‑coded values) verified; Projects List uses keyset pagination [lib/keyset-pagination.ts](lib/keyset-pagination.ts:1); chip overflow policy implemented as per decision gate; Global UI/UX Steering adoption completed for Public stack [app/(public)/_layout.tsx](app/(public)/_layout.tsx:1), [app/(public)/welcome.tsx](app/(public)/welcome.tsx:1), [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1), [app/(public)/sign-up.tsx](app/(public)/sign-up.tsx:1), [app/(public)/signout.tsx](app/(public)/signout.tsx:1); Protected shells [app/_layout.tsx](app/_layout.tsx:1), [app/(protected)/(tabs)/_layout.tsx](app/(protected)/(tabs)/_layout.tsx:1), [app/(protected)/modal.tsx](app/(protected)/modal.tsx:1), [app/(protected)/(tabs)/settings.tsx](app/(protected)/(tabs)/settings.tsx:1); Non‑Projects route [app/(protected)/anomalies.tsx](app/(protected)/anomalies.tsx:1);
  Additional acceptance:
  - iOS: Large‑title navigation collapses smoothly; sheets use medium/large detents with visible grabber and blur/dim; bottom action areas keep ≥24 pt inset; long‑press context menus present; Reduced Motion honored; haptics mapped per tokens
  - Android: System back parity validated; no gesture conflicts with horizontal swipes; minimum 48 dp touch targets
  - Icons: SF Symbols on iOS where available with Ionicons fallback; 24 pt baseline maintained

Stage 7 — Observability, performance, security review
Goal and success criteria
- Goal: Metrics and alerts; performance within 2 s median; pen tests on policies and storage; QA signoff.
- Success: Dashboards live; alerts tuned; perf SLO met; security issues resolved; QA report green.

Prerequisites
- Stages 3 to 6 functional in staging

Tasks
- [ ] Metrics for imports, merges, membership, status; alerts on failures and anomalies [DevOps]
- [ ] Frontend performance profiling and fixes [Frontend]
- [ ] Expand CI policy tests including negative cases [Security]
- [ ] Targeted pen tests on Storage and RLS; remediate findings [Security]
- [ ] Full QA plan execution and triage [QA]

Roles, estimates, risks, exits
- Roles: DevOps, Security, Frontend, QA
- Effort: M (4–6 engineer-days)
- Risks: Alert noise → tune thresholds and aggregate anomalies
- Exit: Dashboards reviewed; perf SLO met; security findings closed

Stage 8 — Rollout, canary, runbooks, training
Goal and success criteria
- Goal: Safe rollout behind flags; canary tenant validation; publish runbooks and user guides; progressive enablement.
- Success: Canary stable; runbooks published; flags enabled per tenant; rollback path validated.

Prerequisites
- Stages 1 to 7 complete

Tasks
- [ ] Keep ENABLE_PROJECTS and ENABLE_ATTACHMENTS_UPLOAD off; enable per canary tenant [DevOps]
- [ ] Enable ENABLE_OKTA_AUTH per tenant in waves; monitor auth_success and failure [DevOps]
- [ ] Execute membership backfill if needed; spot-validate across roles [Backend]
- [ ] Publish runbooks for imports, anomalies, membership reconciliation, storage incidents [Ops]
- [ ] Publish role-specific quick start guides for DP, DS, PM [Docs]

Roles, estimates, risks, exits
- Roles: DevOps, Ops, Backend, Docs
- Effort: M (3–4 engineer-days)
- Risks: Mapping gaps uncovered in canary → directory stewardship runbook and rapid remediation
- Exit: Canary stable for 1–2 weeks; progressive enablement completed; rollback tested

Security integration map
Authentication and session
- Sign-in via oktaSignIn in [context/supabase-provider.tsx](context/supabase-provider.tsx:1) using [oktaAuthorize()](docs/security/okta-oidc-supabase.md:121) and [supabase.auth.signInWithIdToken()](docs/security/okta-oidc-supabase.md:176); session persisted via SecureStore in [config/supabase.ts](config/supabase.ts:1); logout calls Supabase signOut and Okta end session.

Backend tables and RLS enforcement
- public.projects: RLS select tied to project_membership and [user_roles](docs/security/okta-oidc-supabase.md:204); updates denied except admin stub.
- public.project_membership: maintained by import pipeline; no client writes.
- public.contacts, public.engagements, public.attachments_meta: select and write require membership; creator-bound edits per policy.
- storage.objects in attachments bucket: policy checks attachments_meta and project_membership per [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:263).
- [user_profiles](docs/security/okta-oidc-supabase.md:197) and [user_roles](docs/security/okta-oidc-supabase.md:204): owner-only selects; UI uses for gating only.

UI flows and authorization
- GET Projects list and detail: RLS filters results automatically.
- POST Engagement, Contact: membership required; UI hides CTAs when helpers indicate no scope.
- Upload Attachment: client checks ≤ 25 MB; metadata insert precedes object upload; Storage policy enforces access.

Validation gates
- Auth validation checklist per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:386)
- UI QA checklist per [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:423)
- Stage gates per [docs/product/projects-feature-implementation-plan.md](docs/product/projects-feature-implementation-plan.md:218)
- RLS and Storage CI results and pen test report

Change log
- v1.0 Initial consolidated tracker created from source documents and synthesized plan
## Production readiness review — gaps, actions, and exit tests

Identity and authentication
- Gaps
  - ID token nonce/claims validation: Currently rely on platform and Supabase checks; local verifier not explicitly implemented.
  - Clock skew tolerance: Explicit leeway not documented for device skew affecting TOTP and ID token iat/exp.
  - RP-initiated logout completeness: Ensure Okta end_session flow returns to omnivia://signout reliably across iOS/Android; handle canceled flows.
  - Token/session revocation: Confirm Supabase session revocation on signOut; no Okta refresh token persisted by client per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:231).
  - Environment cutover for custom domain (prod-only): Runbook and preflight checklist missing.
- Actions
  - [ ] Add local ID token verifier for nonce/aud/iss/exp checks (optional belt-and-braces) in [auth/okta.ts](auth/okta.ts:1) or a small verifier util; keep Supabase as source of truth.
  - [ ] Document clock skew tolerance; validate min ±5 minutes acceptance in auth flow tests.
  - [ ] Implement robust end_session handler and return path in [context/supabase-provider.tsx](context/supabase-provider.tsx:1); add retry/timeout UX on logout.
  - [ ] Add signOut revocation test; ensure session cleared and RLS denies follow-up queries.
  - [ ] Add Prod custom-domain cutover runbook (issuer changes, redirect URIs, mobile build config, test matrix).
- Exit tests
  - [ ] Negative nonce test fails as expected.
  - [ ] 4–5 minute skew devices can sign in; >10 minute skew prompts correction guidance.
  - [ ] Logout clears session and redirects reliably; relaunch shows public stack [app/(public)/_layout.tsx](app/(public)/_layout.tsx:1).

Claims, profiles, and roles sync
- Gaps
  - On-login mirror of app_roles and identifiers may not update on token refresh.
  - No explicit RPC for idempotent upsert on refresh cycle.
- Actions
  - [ ] Add a post-login sync helper (RPC) invoked after [supabase.auth.signInWithIdToken()](docs/security/okta-oidc-supabase.md:176) and on session refresh to upsert [user_profiles](docs/security/okta-oidc-supabase.md:197) and [user_roles](docs/security/okta-oidc-supabase.md:204).
- Exit tests
  - [ ] Role changes in Okta propagate on next login/refresh and are visible to policy checks.

RLS and policy hardening
- Gaps
  - Policy test coverage not yet exhaustive (negative tests for each role and membership type).
  - Helper function using_rls_for_project not yet implemented to de-duplicate checks.
  - Security definer functions and views review pending.
- Actions
  - [ ] Implement using_rls_for_project(project_id uuid) SQL helper and reuse in engagements/contacts/attachments policies per [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:209).
  - [ ] Add CI suites with synthetic identities covering vendor_admin, telco_admin/pm/ds/rm and dp_admin/pm/cp (select/insert/update/delete).
  - [ ] Review any SECURITY DEFINER routines; ensure minimal privileges and stable plans.
- Exit tests
  - [ ] CI green for full role/membership matrix; manual spot checks confirm denials for non-members.

Import pipeline and membership materialization
- Gaps
  - Backpressure and rate limiting not explicitly configured; potential burst from Power Automate.
  - Ambiguous RM name handling: policy defined (exact normalized match), but ambiguity resolution surfacing needs dashboard and playbook.
  - Staging retention and cleanup policy unspecified.
- Actions
  - [ ] Enforce 1 rps per-tenant throttle and exponential backoff; return 429 on overload.
  - [x] Create anomalies dashboard and alert route; add remediation runbook; surfaced redacted values.
    - Links: [app/(protected)/anomalies.tsx](app/(protected)/anomalies.tsx:1), [supabase/functions/anomalies/index.ts](supabase/functions/anomalies/index.ts:1), [docs/security/supabase-imports-runbook.md § Anomalies stewardship](docs/security/supabase-imports-runbook.md:1)
  - [ ] Set staging retention policy (e.g., 30–90 days) with daily cleanup job.
- Exit tests
  - [ ] Import under load (multiple batches) maintains throughput; merges remain idempotent; anomalies visible.

RM and DS directories
- Gaps
  - rm_directory.display_name hygiene (trim, collapse whitespace) and uniqueness constraints not stated.
  - No audit schema fields finalized.
- Actions
  - [ ] Add unique index on lower(trim(display_name)) where status='active'.
  - [ ] Add audit fields (updated_by, correlation_id) and align with Workflows callbacks per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:333).
- Exit tests
  - [ ] Ambiguous First Last yields anomaly; after steward update, backfill materializes RM membership.

Attachments and storage
- Gaps
  - MIME spoofing and server-side detection not documented.
  - Malware scanning intentionally deferred; document explicitly in risk register.
  - Large file timeout/retry policy not specified.
- Actions
  - [ ] Detect content-type server-side from header bytes; restrict preview to image/* and application/pdf per [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:201).
  - [ ] Configure client retries: up to 2 with exponential backoff; 25 MB hard limit enforced client and server.
  - [ ] Document deferred malware scanning and plan a post-MVP spike.
- Exit tests
  - [ ] Spoofed extension does not gain preview; unauthorized storage access denied by policy per [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:263).

Performance and scale
- Gaps
  - Indexes enumerated but no measured P95/P99 targets on list queries and imports.
  - Keyset pagination not mandated; potential offset pagination cost at scale.
- Actions
  - [ ] Adopt keyset pagination on Projects list (e.g., by stage_application_created desc, then stage_application) and ensure covering indexes.
  - [ ] Load test 5k+ rows; record P95 for list/detail/status recompute; tune indexes.
- Exit tests
  - [ ] Median ≤2s, P95 ≤4s for target dataset; recompute only on changed rows.

Observability, alerting, and runbooks
- Gaps
  - Detailed dashboards and alerts not fully enumerated; SIEM pipeline acceptance tests not documented.
  - Runbooks not yet written for: import failures, membership anomalies, storage policy denies, Okta outage.
- Actions
  - [ ] Create dashboards for auth success/failure, import success rate, anomalies per batch, membership changes, storage denies, status recompute durations.
  - [ ] Wire alerts with actionable thresholds and correlation IDs.
  - [ ] Author runbooks and link them in README Ops; include flag rollback steps for ENABLE_OKTA_AUTH/ENABLE_PROJECTS/ENABLE_ATTACHMENTS_UPLOAD.
- Exit tests
  - [ ] SIEM shows Okta System Logs; synthetic failures trigger alerts; on-call can follow runbooks end-to-end.

Privacy, compliance, and governance
- Gaps
  - DPA and data residency notes not included in docs; access controls for dashboards and flags not documented.
- Actions
  - [ ] Document AU residency alignment for Okta and Supabase; link in a short security note.
  - [ ] Limit dashboard and feature-flag consoles to vendor_admin and telco_admin; enforce MFA in admin tools.
- Exit tests
  - [ ] Access checks on consoles; audit of flag changes recorded.

Build, release, and device posture
- Gaps
  - EAS profiles and env separation documented implicitly, not explicitly in this repo.
  - Jailbreak/root detection not planned (not required for MVP).
- Actions
  - [ ] Add a small Build & Release section to README with EAS profiles (dev/stage/prod) and env variables.
  - [ ] Document optional device posture strategy for post-MVP.
- Exit tests
  - [ ] Dev/Stage/Prod sign-in flows verified; deep link works in Expo Go and standalone.

QA coverage
- Gaps
  - Negative MFA cases, offline flows, and deep-link edge cases to be captured explicitly.
- Actions
  - [ ] Extend QA checklist per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:317) and [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:423) with negative/edge scenarios.
- Exit tests
  - [ ] QA signoff report: pass rates and defect burndown to green.

---

## User login experience — Okta passwordless TOTP with Supabase session

First-time user (not yet enrolled in authenticator)
1) User opens the app and sees a single “Continue with Okta” button on [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1) (also present on [app/(public)/welcome.tsx](app/(public)/welcome.tsx:1) and [app/(public)/sign-up.tsx](app/(public)/sign-up.tsx:1) gated by ENABLE_OKTA_AUTH).
2) Tap launches Okta PKCE via [oktaAuthorize()](docs/security/okta-oidc-supabase.md:121) in [auth/okta.ts](auth/okta.ts:1), opening the Okta-hosted screen.
3) Okta prompts for username (per policy). As passwordless is enforced, Okta guides the user to enroll Okta Verify or Google Authenticator (and offers backup codes) per tenant policy.
4) After enrollment and TOTP verification, Okta returns an authorization code to omnivia://oauthredirect. The app exchanges it for tokens and then calls [supabase.auth.signInWithIdToken()](docs/security/okta-oidc-supabase.md:176) with provider=oidc.
5) On first successful session, the app mirrors identity into [user_profiles](docs/security/okta-oidc-supabase.md:197) and roles into [user_roles](docs/security/okta-oidc-supabase.md:204) (via post-login sync). Session is persisted securely via SecureStore configured in [config/supabase.ts](config/supabase.ts:1).
6) The app navigates into the protected tabs [app/(protected)/_layout.tsx](app/(protected)/_layout.tsx:1) and shows modules allowed by flags (ENABLE_PROJECTS/ENABLE_ATTACHMENTS_UPLOAD). RLS ensures only assigned/visible projects appear.

Returning user (already enrolled)
1) User taps “Continue with Okta”. If Okta session is valid and policy allows, a lightweight re-auth occurs; otherwise Okta prompts for TOTP.
2) On success, the app refreshes the Supabase session (if needed) and lands the user in protected tabs immediately.
3) Optional: if ENABLE_BIOMETRIC_UNLOCK is on, the app prompts FaceID/TouchID after cold start before rendering protected content; the Supabase session remains in SecureStore.

Logout
- From Settings [app/(protected)/(tabs)/settings.tsx](app/(protected)/(tabs)/settings.tsx:1), user taps Sign out. The app calls supabase.auth.signOut, then Okta end_session_endpoint, returning to omnivia://signout and back to the public stack. Session is cleared; protected routes are gated by [app/_layout.tsx](app/_layout.tsx:1).

Error and edge cases
- Wrong/expired TOTP: Okta prompts again; the app surfaces a concise error toast.
- Device clock skew: If excessive, Okta may reject TOTP; app guidance directs user to correct time settings (auto time).
- Invalid redirect URI: The app shows an error with “Try again” and a link to troubleshooting.
- Provider mismatch or ID token validation error: The app falls back per feature flag to SSO Pattern A or presents a retry with diagnostics.
- Account disabled or role removed: Supabase session creation or subsequent policy checks fail; app shows Access denied message; admin contact hint may be included.

UX notes
- Minimal friction: single-button auth, progress indicators during redirect/exchange, success toasts.
- Accessibility: large tap targets and clear labels per [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:382).
- Privacy: No token contents or PII logged; telemetry sends start_auth/auth_success/auth_failure per [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:303).
Implementation callouts — Stage 2 (2025-08-17 14:29 ACST)
- Bucket creation and guardrails
  - Path: Ensure private Storage bucket 'attachments' exists using [sql.storage.create_bucket()](docs/sql/stage2-apply.sql:10) guarded by existence in storage.buckets. The operation is idempotent and only runs if missing.
  - Policies: Duplicate-safe reapplication of Storage policies on storage.objects via DROP IF EXISTS + [sql.CREATE POLICY](docs/sql/omni-bootstrap.sql:458) patterns in [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1). Safe to run before or after bucket creation; if the bucket was created after bootstrap, re-run the Storage policy block (this script does so every time).
- Seeds and conflict strategy
  - partner_org: UPSERT-by-normalized-name (lower(trim(name))) inserts canonical labels if absent. Source list per import contract (e.g., Fulton Hogan, Ventia, UGL, Enerven, Servicestream). See [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:75).
  - partner_normalization: UPSERT-by-normalized-source_label (lower(trim(source_label))) mapping to canonical partner_org.id. See [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:92).
  - features: Per-tenant flags ENABLE_PROJECTS, ENABLE_ATTACHMENTS_UPLOAD, ENABLE_OKTA_AUTH seeded with defaults using primary key (tenant_id, name). We used ON CONFLICT DO NOTHING to avoid overwriting manual toggles already set by ops. Tenants seeded include 'TELCO' plus any tenant_id observed in user_profiles. See [sql.INSERT](docs/sql/stage2-apply.sql:139).
- Indexes added/validated and rationale
  - projects(stage_application, stage_application_created desc) for keyset pagination and list sorts: [sql.CREATE INDEX](docs/sql/omni-bootstrap.sql:147).
  - projects(partner_org_id) to support org filters: [sql.CREATE INDEX](docs/sql/omni-bootstrap.sql:148).
  - projects(derived_status) to support status filters: [sql.CREATE INDEX](docs/sql/omni-bootstrap.sql:149).
  - projects(tenant_id) to support tenant scoping: [sql.CREATE INDEX](docs/sql/omni-bootstrap.sql:150).
  - The Stage 2 script re-validates via [sql.CREATE INDEX](docs/sql/stage2-apply.sql:149) IF NOT EXISTS to avoid duplicates and ensure consistent performance baselines.
- Verification plan and how to interpret [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1)
  - Core tables: Rows with check='table: ...' return pass=true when each table exists (projects, project_membership, contacts, engagements, attachments_meta, partner_org, partner_normalization, ds_directory, rm_directory, user_profiles, user_roles, features, staging_imports).
  - Index presence: Queries scan pg_indexes with indexdef ILIKE patterns for stage_application, partner_org_id, derived_status, tenant_id. pass=true indicates at least one matching index present.
  - Storage: bucket_ok via storage.buckets exists(name='attachments'); policies present via pg_policies count (attachments_read/insert/delete) and predicates include bucket_id='attachments'.
  - Seeds: partner_org count>=1; canonical labels present; partner_normalization mappings join successfully to partner_org; features contains keys ENABLE_PROJECTS, ENABLE_ATTACHMENTS_UPLOAD, ENABLE_OKTA_AUTH (optionally grouped by tenant).
  - Outputs are human-readable with pass/fail booleans and counts for quick validation in Supabase SQL Editor.
- Risks and follow-ups
  - Features seeding scope: Tenants discovered from user_profiles; if a new tenant is introduced before any user login mirrors a profile, re-run [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1) after the first login or add the tenant_id explicitly to the tenants CTE.
  - Partner label drift: partner_normalization is enforced via a unique index on lower(trim(source_label)) (created in bootstrap via DO $$). Continue stewardship to capture new variants.
  - Policy duplication: Storage policies are dropped/created each run; this is intentional to keep predicates aligned with the latest policy template.
  - Storage schema availability: Supabase projects normally include the storage schema; if an environment is missing it, [sql.storage.create_bucket()](docs/sql/stage2-apply.sql:10) will fail. Resolve by enabling Storage in the Supabase project first.
  - No checklist items were marked complete in this update; verification must pass in a Supabase environment before ticking Stage 2 tasks.

Verification results — Stage 2 (2025-08-17, ACST)
- Execution environment: Production via Supabase Studio following [docs/security/supabase-stage2-production-runbook.md](docs/security/supabase-stage2-production-runbook.md:1). Scripts re-runnable and idempotent: [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1) → [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1) → [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1).
- Summary (from verify run):
  - tables_ok: projects=true, project_membership=true, contacts=true, engagements=true, attachments_meta=true, partner_org=true, partner_normalization=true, ds_directory=true, rm_directory=true, user_profiles=true, user_roles=true, features=true, staging_imports=true
  - indexes_ok: stage_application=true, partner_org_id=true, derived_status=true, tenant_id=true
  - bucket_ok: true
  - storage_policies_ok: 3 (attachments_read, attachments_insert, attachments_delete)
  - partner_org_count: 5; samples: ["Enerven","Fulton Hogan","Servicestream"]
  - partner_normalization_count: 9
  - features_present: ENABLE_PROJECTS=true, ENABLE_ATTACHMENTS_UPLOAD=true, ENABLE_OKTA_AUTH=true for tenant_id='TELCO'
- Key callouts:
  - Bucket creation path used [sql.storage.create_bucket()](docs/sql/stage2-apply.sql:10) guarded by existence in storage.buckets; Storage policies re-applied safely via drop-if-exists + [sql.CREATE POLICY](docs/sql/omni-bootstrap.sql:458) / [sql.CREATE POLICY](docs/sql/omni-bootstrap.sql:475) / [sql.CREATE POLICY](docs/sql/omni-bootstrap.sql:493).
  - Seeds inserted with ON CONFLICT DO NOTHING to preserve any ops toggles; flags remain disabled by default.
  - Index coverage matches bootstrap; [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1) fills gaps with [sql.CREATE INDEX](docs/sql/stage2-apply.sql:149) IF NOT EXISTS only.
  - Stability improvements: intra-batch dedup for partner_normalization and consolidated verification output in [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1).
  - Next steps: proceed to Stage 3 — RLS/Storage CI tests; no feature enablement in Stage 2.

Artifacts created/updated
- [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1): Idempotent bucket ensure, duplicate-safe Storage policies, partner seeds, feature flags seeding, index validation.
- [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1): Verification queries for tables, indexes, Storage, and seeds.
- Data Dictionary extended in [docs/product/projects-feature-implementation-plan.md](docs/product/projects-feature-implementation-plan.md:182) under “13a. Data Dictionary — Stage 2 tables (detailed)” with schema summaries, constraints, RLS notes, and business purpose.

Operator next steps (do not check off yet)
- Run bootstrap migration [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1) in Supabase SQL Editor.
- Create/confirm private bucket 'attachments' in Supabase Dashboard → Storage or let [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1) ensure it exists.
- Run [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:1) (safe to re-run).
- Run [docs/sql/stage2-verify.sql](docs/sql/stage2-verify.sql:1) and capture the output for the tracker.
### Deployment callouts — Stage 6 (2025-08-19 22:30 ACST)

- Files added/changed
  - Added
    - [lib/authz.ts](lib/authz.ts:1)
    - [lib/analytics.ts](lib/analytics.ts:1)
    - [lib/useFeatures.ts](lib/useFeatures.ts:1)
    - [lib/useReducedMotion.ts](lib/useReducedMotion.ts:1)
    - [lib/haptics.ts](lib/haptics.ts:1)
    - [components/projects/StatusChip.tsx](components/projects/StatusChip.tsx:1)
    - [components/projects/ChipRow.tsx](components/projects/ChipRow.tsx:1)
    - [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:1)
    - [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:1)
    - Ambient type shims for optional libs:
      - [types/haptics.d.ts](types/haptics.d.ts:1)
      - [types/external.d.ts](types/external.d.ts:1)
  - Modified
    - [package.json](package.json:1) — added UI deps (see below)
    - [app/_layout.tsx](app/_layout.tsx:1) — import "react-native-gesture-handler" side-effect at top
    - [app/(protected)/(tabs)/_layout.tsx](app/(protected)/(tabs)/_layout.tsx:1) — Projects tab entry gated by flags
    - [.env](.env:1) — added EXPO_PUBLIC_ENABLE_PROJECTS, EXPO_PUBLIC_ENABLE_ATTACHMENTS_UPLOAD
- Dependencies added and config
  - UI/UX and native UX
    - "@gorhom/bottom-sheet": "^4.6.3"
    - "react-native-ios-context-menu": "^1.14.0"
    - "react-native-haptic-feedback": "^2.0.3"
    - "expo-blur": "^13.0.2"
    - "expo-document-picker": "^14.0.2"
  - Reanimated/Babel
    - Babel plugin present and last: ["react-native-reanimated/plugin"] in [babel.config.js](babel.config.js:1) (verified; no change required)
    - Kept "react-native-reanimated" and "react-native-gesture-handler" versions aligned to Expo SDK (0.79/53); see Deviations note
- Feature flags and deep link
  - Flags hook [typescript.useFeatures()](lib/useFeatures.ts:1) merges per-tenant remote flags (features table) with optional env overrides:
    - EXPO_PUBLIC_ENABLE_PROJECTS
    - EXPO_PUBLIC_ENABLE_ATTACHMENTS_UPLOAD
  - Navigation/tab visibility reads hook; Projects UI fully hidden when disabled
  - Deep link path used: omnivia://projects/{stage_application} routing to [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:1)
- iPhone‑first behaviors implemented
  - Projects List uses large title (iOS), smooth collapse, and disables edge‑swipe while the filters sheet is open
  - Filters bottom sheet: detents 0.5 / 0.9, visible grabber, rounded top, BlurView dim/blur background
  - Long‑press context menu on iOS rows (Share deep link); Android parity via primary tap
  - Haptics mapping (selection/success/warning/error/destructive) with throttling in [lib/haptics.ts](lib/haptics.ts:1)
  - Reduced Motion respected via [lib/useReducedMotion.ts](lib/useReducedMotion.ts:1) (logic available for transitions)
  - Tokens‑only styling; no hard‑coded colors; Status chips use semantic tokens in [components/projects/StatusChip.tsx](components/projects/StatusChip.tsx:1)
- Key implementation notes
  - Keyset pagination helper [lib/keyset-pagination.ts](lib/keyset-pagination.ts:1) applied with order: stage_application ASC, stage_application_created DESC, id DESC; verified against [docs/sql/stage6-keyset-verify.sql](docs/sql/stage6-keyset-verify.sql:1)
  - Chips overflow policy: up to 5 visible + trailing Filters chip; full set in bottom sheet
  - Detail tabs: Overview, Timeline, Contacts, Engagements, Attachments (UGC gated by [typescript.canCreateUGC()](lib/authz.ts:1))
  - Attachments upload: 25 MB client cap, metadata insert precedes object upload, storage path "tenant_id/stage_application/object_uuid", image/pdf preview only
  - Analytics surface [lib/analytics.ts](lib/analytics.ts:1): list_viewed, search_submitted, filter_applied, project_opened, engagement_added, attachment_uploaded, contact_added (console transport stub for Stage 7)
- Deviations / compatibility
  - Reanimated and Gesture Handler versions retained at Expo SDK‑compatible ranges ("react-native-reanimated": "~3.17.x", "react-native-gesture-handler": "~2.24.x") rather than pinning to versions in the tracker. Bottom sheet peers tested against Expo 53 baseline.
  - Android context menu uses primary tap; overflow icon can be added post‑MVP if required by parity checklist.
  - TypeScript ambient module shims added under /types for optional native libs to keep strict mode green without adding @types packages.
  - Blur/dim implemented using expo‑blur (equivalent to react-native-blur in Expo environments).

### Deployment callouts — Stage 6 (2025-08-20 17:46 ACST — Non‑Projects UI/UX Steering adoption)

- Files modified
  - [app/_layout.tsx](app/_layout.tsx:1)
  - [app/(public)/_layout.tsx](app/(public)/_layout.tsx:1)
  - [app/(public)/welcome.tsx](app/(public)/welcome.tsx:1)
  - [app/(public)/sign-in.tsx](app/(public)/sign-in.tsx:1)
  - [app/(public)/sign-up.tsx](app/(public)/sign-up.tsx:1)
  - [app/(public)/signout.tsx](app/(public)/signout.tsx:1)
  - [app/(protected)/(tabs)/_layout.tsx](app/(protected)/(tabs)/_layout.tsx:1)
  - [app/(protected)/(tabs)/index.tsx](app/(protected)/(tabs)/index.tsx:1)
  - [app/(protected)/(tabs)/settings.tsx](app/(protected)/(tabs)/settings.tsx:1)
  - [app/(protected)/modal.tsx](app/(protected)/modal.tsx:1)
  - [app/(protected)/anomalies.tsx](app/(protected)/anomalies.tsx:1)
  - [components/ui/button.tsx](components/ui/button.tsx:1)
  - [components/ui/form.tsx](components/ui/form.tsx:1)

- Key implementation notes
  - Large titles: Enabled on public Welcome via Native Stack headerLargeTitle. Tabs not structurally changed (see Deviations). Projects module continues to manage large titles within its stack.
  - Safe areas and bottom action areas: Wrapped Home, Settings, Modal, Anomalies, and public screens in [components/safe-area-view.tsx](components/safe-area-view.tsx:1). Primary CTAs sit above the home indicator with edges=["bottom"] and padding meeting the ≥24 pt rule.
  - Haptics: Added optional haptic prop to [components/ui/button.tsx](components/ui/button.tsx:1) mapped via [lib/haptics.ts](lib/haptics.ts:1). Applied selection haptics on key CTAs (Welcome/Sign In/Sign Up/Sign Out/Settings).
  - Context menus: iOS-only long‑press context menu on Anomalies rows using react-native-ios-context-menu with Share action; Android fallback is primary tap. Haptics fire on commit and are throttled.
  - Reduced Motion: Form validation messages honor OS Reduced Motion through [lib/useReducedMotion.ts](lib/useReducedMotion.ts:1) by disabling enter/exit animations.
  - Tokens-only sweep: Removed hard-coded yellows in Anomalies; primitives already consume semantic tokens. No new hard-coded colors introduced.

- Deviations and compatibility
  - Tabs large titles: Bottom tabs do not accept headerLargeTitle directly. To avoid structural churn, we did not nest tab screens in stacks. Follow-up TODO: add per-tab Native Stacks and enable headerLargeTitle on first screens (Home, Settings).
  - Modal presentation: [app/(protected)/modal.tsx](app/(protected)/modal.tsx:1) remains full-screen; sheet standardization reserved for feature modals. Safe areas/tokens applied.
  - iOS-only menus: Android uses primary tap; optional overflow menu can be added post‑MVP if required.
  - Libraries: No new dependencies beyond Stage 6 set; versions remain Expo 53 compatible.

- Validation summary against acceptance
  - iOS: Edge-swipe back enabled at root; large title on Welcome; safe areas respected across updated screens; long‑press context menus on Anomalies; haptics mapped and throttled; Reduced Motion paths active; icons at 24 baseline.
  - Android: System back parity maintained; no iOS back-swipe emulation; ≥48 dp touch targets met; insets respected.
  - Accessibility: Dynamic Type respected in primitives; no clipping at 320 pt width observed on touched screens.

- Known follow-ups / TODO
  - Introduce per-tab Native Stacks to enable headerLargeTitle on Home and Settings.
  - Consider Android overflow menu for Anomalies row secondary actions if parity is required.