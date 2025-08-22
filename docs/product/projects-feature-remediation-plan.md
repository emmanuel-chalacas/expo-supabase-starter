# Projects Feature — Variances Remediation Plan (Sorting, Search, DP Visibility, Timeline)

Author: Kilo Code
Status: Draft v0.1
Date: 2025-08-20

Scope
- Address the four prioritized variances against the PRD:
  1) Sorting and fallback logic differ from PRD
  2) Search is Stage Application only; Address search missing
  3) DP visibility risk due to client tenant filter
  4) Timeline tab renders only a subset of PRD milestones; EFSCD should not be in Timeline

Deliverables
- Database
  - New SQL migration adding an RPC for PRD-compliant list sorting with fallback-by-key-date and built-in search and filters
    - Path: supabase/migrations/20250820220000_stage7_projects_list_rpc.sql
    - Function: rpc_projects_list (security invoker; RLS applies)
- App changes
  - Projects list: remove tenant filter, switch to RPC for Newest, expand search to include address/suburb/state
    - File: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
  - Timeline tab: render all PRD milestones in specified order; exclude EFSCD from Timeline (keep in Overview)
    - File: [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/%5Bstage_application%5D.tsx)
- Verification docs
  - New SQL verify script for RPC correctness and keyset behavior
    - Path: docs/sql/stage7-list-rpc-verify.sql (added)
- Optional performance (defer unless needed)
  - sort_ts persisted column with trigger; pg_trgm indexes for contains-search

Notes
- RLS remains the authoritative visibility control; client must not restrict by tenant_id.
- EFSCD may be used in sorting fallback per PRD’s “latest key date present” rule but must not appear in the Timeline UI.

Acceptance summary
- List default sort matches PRD: Stage Application Created DESC; fallback to the latest key date (including EFSCD and other schedule dates) when Stage Application Created is unavailable.
- Search supports Stage Application or Address (address/suburb/state).
- Delivery Partner users see assigned Telco projects because client no longer filters by their DP tenant_id; RLS and membership govern scope.
- Timeline shows the following ordered milestones only: Stage Application Created, Developer Design Submitted, Developer Design Accepted, Issued to Delivery Partner, Practical Completion Notified, Practical Completion Certified, Delivery Partner PC Sub, In Service. EFSCD stays in Overview.

--------------------------------------------------------------------------------

Task 1 — Add RPC for PRD-compliant list sorting and search (DB migration)

Goal
- Provide a single RLS-respecting, keyset-friendly RPC that:
  - Computes sort_ts per project: coalesce(stage_application_created, greatest of key dates including EFSCD and other schedule dates)
  - Sorts by sort_ts DESC then id DESC for stable paging
  - Accepts filters for derived_status, development_type, build_type
  - Accepts a free-text search across stage_application, address, suburb, state
  - Implements keyset pagination via cursor_sort_ts and cursor_id

Migration deliverable
- File: supabase/migrations/20250820220000_stage7_projects_list_rpc.sql
- Contents outline:
  - create or replace function public.rpc_projects_list(
      p_search text default null,
      p_status text[] default null,
      p_dev_types text[] default null,
      p_build_types text[] default null,
      p_cursor_sort_ts timestamptz default null,
      p_cursor_id uuid default null,
      p_limit int default 25
    )
    returns table (
      id uuid,
      stage_application text,
      stage_application_created timestamptz,
      derived_status text,
      developer_class text,
      partner_org_name text,
      address text,
      suburb text,
      state text,
      development_type text,
      build_type text,
      sort_ts timestamptz
    )
    language sql
    security invoker
    as $$
      with base as (
        select
          p.id,
          p.stage_application,
          p.stage_application_created,
          p.derived_status,
          p.developer_class,
          po.name as partner_org_name,
          p.address, p.suburb, p.state,
          p.development_type, p.build_type,
          coalesce(
            p.stage_application_created,
            greatest(
              p.efscd::timestamptz,
              p.developer_design_submitted::timestamptz,
              p.developer_design_accepted::timestamptz,
              p.issued_to_delivery_partner::timestamptz,
              p.practical_completion_certified::timestamptz,
              p.delivery_partner_pc_sub::timestamptz,
              p.in_service::timestamptz
            )
          ) as sort_ts
        from public.projects p
        left join public.partner_org po on po.id = p.partner_org_id
      ),
      filtered as (
        select * from base
        where
          (p_status is null or array_length(p_status,1) is null or derived_status = any(p_status))
          and (p_dev_types is null or array_length(p_dev_types,1) is null or development_type = any(p_dev_types))
          and (p_build_types is null or array_length(p_build_types,1) is null or build_type = any(p_build_types))
          and (
            p_search is null
            or length(btrim(p_search)) = 0
            or
            (
              stage_application ilike ('%' || p_search || '%')
              or address ilike ('%' || p_search || '%')
              or suburb ilike ('%' || p_search || '%')
              or state ilike ('%' || p_search || '%')
            )
          )
      ),
      paged as (
        select * from filtered
        where
          (p_cursor_sort_ts is null and p_cursor_id is null)
          or
          (
            sort_ts < p_cursor_sort_ts
            or (sort_ts = p_cursor_sort_ts and id < p_cursor_id)
          )
        order by sort_ts desc, id desc
        limit greatest(1, p_limit)
      )
      select
        id, stage_application, stage_application_created, derived_status, developer_class, partner_org_name,
        address, suburb, state, development_type, build_type, sort_ts
      from paged
    $$;

Behavior
- Security invoker ensures RLS on public.projects restricts results correctly.
- Cursor is exclusive (strictly after the last item), matching typical keyset usage in the client.

Verification
- New script: docs/sql/stage7-list-rpc-verify.sql
  - Inserts few projects with varying date completeness; asserts ordering and cursor pagination.
  - Asserts search on stage_application and address/suburb/state.
  - Confirms RLS still governs results when run under limited roles (optional if local environment is service role).

### Deployment notes — Task 1 (DB: rpc_projects_list)
- Prerequisites:
  - Supabase CLI installed and linked to the target project per [docs/security/supabase-migrations-run-sheet.md](docs/security/supabase-migrations-run-sheet.md).
- Apply migration (remote):
  - supabase db push
  - This applies all pending migrations including [supabase/migrations/20250820220000_stage7_projects_list_rpc.sql](supabase/migrations/20250820220000_stage7_projects_list_rpc.sql)
- Apply migration (ad-hoc single file, optional):
  - supabase db execute --file supabase/migrations/20250820220000_stage7_projects_list_rpc.sql
- No downtime expected: [sql.create_function()](supabase/migrations/20250820220000_stage7_projects_list_rpc.sql:1) is CREATE OR REPLACE.
- Post-deploy smoke:
  - Use the Supabase SQL editor or CLI to run:
    - select count(*) from public.rpc_projects_list(null, null, null, null, null, null, 1);
  - Expect a non-error response; row visibility remains governed by RLS.
- Rollback:
  - Since this is additive and used by the UI in Task 2, prefer forward fix. If necessary:
    - create or replace function public.rpc_projects_list(...) with a previous known-good body in a hotfix migration.

--------------------------------------------------------------------------------

Task 2 — Projects list: switch to RPC and expand search; remove tenant filter

Goal
- Remove client-side tenant_id filter to avoid blocking DP users from seeing Telco-owned projects they are assigned to.
- Use the new RPC for “Newest” ordering to get PRD-correct fallback behavior.
- Expand search to include Stage Application and Address (address/suburb/state) with a single input.

Changes
- File: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Remove tenant scope predicate:
  - Delete .eq("tenant_id", tenantId)
- Replace “Newest” branch of loadPage with supabase.rpc("rpc_projects_list", {...}) call:
  - Inputs:
    - p_search: search
    - p_status: statusFilter
    - p_dev_types: devTypeFilter
    - p_build_types: buildTypeFilter
    - p_cursor_sort_ts, p_cursor_id: derived from last item returned
    - p_limit: PAGE_SIZE
  - Map returned fields to the current ProjectRow shape; preserve partner_org.name via partner_org_name.
  - Derive next cursor from { sort_ts, id }
- Update search input placeholder:
  - “Search Stage Application or Address”
- Keep “Oldest” support (two options):
  - Option A: quick: keep current old “Oldest” asc sort for small slices (unchanged)
  - Option B: preferred: add p_sort_direction param in RPC and use asc branch (can be done later)

Analytics
- Continue tracking list_viewed, search_submitted, filter_applied, project_opened as-is.

QA
- Sign in as DP role and verify projects appear without tenant_id client filter.
- Verify search and status/dev/build filters with and without cursor.

### Deployment notes — Task 2 (App: Projects list uses rpc_projects_list)
- Prerequisites:
  - Task 1 migration applied (rpc exists) and app configured for Supabase.
- App/UI refresh:
```
npx expo start -c
```
- Optional OTA/publish (if applicable to your release process):
```
npx expo export
```
- Smoke checks:
  - From the Projects tab, confirm results appear for DP users without client-side tenant_id filtering (RLS governs visibility).
  - Search by Stage Application and by Address fields and verify results.
  - Page forward with several filters applied; ensure no duplicates across page boundaries.
- Rollback:
  - Switch the “Newest” path back to the previous client-side ordering while keeping Task 1 RPC available for canary tests.

--------------------------------------------------------------------------------

Task 3 — Timeline tab: render full PRD milestones in the specified order; exclude EFSCD

Goal
- Show all milestones in precise order:
  1) Stage Application Created (date)
  2) Developer Design Submitted (date)
  3) Developer Design Accepted (date)
  4) Issued to Delivery Partner (date)
  5) Practical Completion Notified (date)
  6) Practical Completion Certified (already present)
  7) Delivery Partner PC Sub (date)
  8) In Service (date)
- Keep EFSCD in Overview/summary only, not in Timeline.

Changes
- File: [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/%5Bstage_application%5D.tsx)
- In the Timeline tab render block, build an array of tuples [label, value] in the above order:
  - Stage Application Created: proj.stage_application_created (render as local datetime)
  - Developer Design Submitted: proj.developer_design_submitted
  - Developer Design Accepted: proj.developer_design_accepted
  - Issued to Delivery Partner: proj.issued_to_delivery_partner
  - Practical Completion Notified: proj.practical_completion_notified
  - Practical Completion Certified: proj.practical_completion_certified
  - Delivery Partner PC Sub: proj.delivery_partner_pc_sub
  - In Service: proj.in_service
- Render each line with label and date; if null, “Not yet provided”.
- Ensure EFSCD remains in Overview (already present).

QA
- Open several projects with different date combinations; confirm ordering and labels.
- Confirm EFSCD is not displayed within the Timeline tab.

### Deployment notes — Task 3 (App: Timeline milestones order, EFSCD excluded)
- App/UI refresh:
```
npx expo start -c
```
- Smoke checks:
  - Open a project with a variety of milestone dates and confirm the Timeline shows exactly the eight milestones in the specified order.
  - For null dates, “Not yet provided” appears.
  - EFSCD does not appear in the Timeline tab but remains visible in Overview if present.
- Rollback:
  - Revert the Timeline rendering to the previous component iteration while leaving the RPC and Projects list intact.

--------------------------------------------------------------------------------

Task 4 — Verification artifacts

Goal
- Add a deterministic SQL verification script for the new list RPC and cursor semantics.

Deliverable
- File: docs/sql/stage7-list-rpc-verify.sql
- Script outline:
  - Seed projects with varying combinations of stage_application_created and other key dates
  - Call rpc_projects_list with and without cursors; assert sort order and page boundaries
  - Assert filtering by status/dev/build, assert search across stage_application and address
  - Output PASS rows for each assertion (similar style to Stage 5/6 verify scripts)

### Deployment notes — Task 4 (Verification: rpc_projects_list)
- Prerequisites:
  - Stage 7 RPC migration applied and Tasks 1–3 merged.
- Run verification (local or remote):
  - ```
    supabase db execute --file docs/sql/stage7-list-rpc-verify.sql
    ```
- Expected output:
  - Multiple “PASS …” rows indicating ordering, cursor paging, filters, and search all verified.
  - The script runs inside a transaction and rolls back; no persistent data changes.
- Troubleshooting:
  - If assertions fail, review seeded timestamps and ids; ensure the function body matches [supabase/migrations/20250820220000_stage7_projects_list_rpc.sql](supabase/migrations/20250820220000_stage7_projects_list_rpc.sql).
  - Confirm CLI session role/permissions match those used by earlier verify scripts.

--------------------------------------------------------------------------------

Task 5 — Optional performance hardening (defer unless needed)

A) Persisted sort_ts
- Add projects.sort_ts timestamptz
- Trigger to recompute when any of the key date columns change (same list used in RPC)
- Index on (sort_ts desc, id desc)
- Consider backfill with a one-off update, then rely on trigger

B) Search speed
- Enable pg_trgm and add GIN indexes:
  - create extension if not exists pg_trgm
  - create index if not exists projects_stage_application_trgm on public.projects using gin (lower(stage_application) gin_trgm_ops)
  - create index if not exists projects_address_trgm on public.projects using gin (lower(address) gin_trgm_ops)
  - create index if not exists projects_suburb_trgm on public.projects using gin (lower(suburb) gin_trgm_ops)
  - create index if not exists projects_state_trgm on public.projects using gin (lower(state) gin_trgm_ops)
- Only required if tenants grow significantly beyond MVP scale.

--------------------------------------------------------------------------------

Task 6 — Rollout and risk management

- Backward compatibility
  - UI can ship address search and tenant filter removal immediately
  - RPC switch for “Newest” can be feature-flagged for a short canary period if desired
- Monitoring
  - Log RPC performance and PostgREST latency
  - Track list_viewed counts per role to confirm DP adoption
- Rollback
  - If RPC issues occur, the list can temporarily revert to client ordering without fallback (keyset helper) while investigating

--------------------------------------------------------------------------------

File change checklist (for implementation)

- DB
  - Add [sql.rpc_projects_list()](supabase/migrations/20250820220000_stage7_projects_list_rpc.sql)

- App — Projects List
  - Edit [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
    - Remove .eq("tenant_id", tenantId)
    - Replace “Newest” load path to call supabase.rpc("rpc_projects_list", {...})
    - Update placeholder to “Search Stage Application or Address”
    - Map partner_org_name into partner_org: { name }

- App — Timeline
  - Edit [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/%5Bstage_application%5D.tsx)
    - Render ordered milestones listed in Task 3
    - Ensure EFSCD appears only in Overview

- Verification
  - Add [docs/sql/stage7-list-rpc-verify.sql](docs/sql/stage7-list-rpc-verify.sql)

--------------------------------------------------------------------------------

Open questions for confirmation

- Oldest sort behavior: should we also implement ascending sort via the RPC now, or retain the current minimal ASC client code until needed?
- Any additional filters to include in the RPC at this stage (e.g., Delivery Partner, Deployment Specialist) or leave for a later iteration aligned with PRD 6.1 extended filters?