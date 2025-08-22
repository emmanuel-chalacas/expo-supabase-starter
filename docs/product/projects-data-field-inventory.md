# Projects Data Field Inventory — Projects Feature
Generated: 2025-08-20
Scope: Authoritative inventory of all project-related data fields across Source spreadsheet, Database (Supabase), App UI, and Derived/calculated logic.
Source anchors (implementation references):
- [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:32)
- [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:25)
- [supabase/migrations/20250817061900_omni_bootstrap.sql](supabase/migrations/20250817061900_omni_bootstrap.sql:131)
- [supabase/migrations/20250817231500_stage4_import.sql](supabase/migrations/20250817231500_stage4_import.sql:71)
- [supabase/migrations/20250818062000_stage5_status_compute.sql](supabase/migrations/20250818062000_stage5_status_compute.sql:6)
- [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:58)
- [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:35)
- [components/projects/StatusChip.tsx](components/projects/StatusChip.tsx:10)
- [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:314)

Legend
- Source spreadsheet = Field arrives from the Power Automate/SharePoint feed.
- Derived = Field is computed in SQL based on other fields.
- App-only = Created/edited in the app (UGC), never overwritten by imports.
- Not stored (MVP) = Present in contract/UI spec but not persisted in the current schema.

1. Canonical project fields (public.projects)
Table: Columns stored on public.projects with source, types, UI exposure, and dependencies.

| Canonical field | Source type | Supabase storage | UI label(s) | Data type | Where used in app | Dependencies/notes |
|---|---|---|---|---|---|---|
| id | System | public.projects.id | — | uuid | Internal identifiers; relations, RLS helper | Created by DB; not shown in UI |
| tenant_id | System | public.projects.tenant_id | — | text | Query scoping in list API | Used in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:192) eq(tenant_id) |
| stage_application | Source spreadsheet | public.projects.stage_application | Stage Application | string | List card title; detail header; search | Stable key; unique per tenant via index in [supabase/migrations/20250817231500_stage4_import.sql](supabase/migrations/20250817231500_stage4_import.sql:82) |
| stage_application_created | Source spreadsheet | public.projects.stage_application_created | Stage App Created | timestamptz | Detail Overview; sort/display; status Late App calc input | Read from import; preserved via COALESCE in [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:349) |
| delivery_partner_label | Source spreadsheet | public.projects.delivery_partner_label | Delivery Partner (raw) | text | Not shown; raw for audit | Normalized to partner_org via [sql.fn_partner_org_from_label(text)](supabase/migrations/20250817231500_stage4_import.sql:173) |
| partner_org_id | Derived | public.projects.partner_org_id | Delivery Partner | uuid | List/detail as partner_org.name | Drives ORG membership; null → Unassigned UI |
| developer_class | Source spreadsheet (normalized) | public.projects.developer_class | Developer Class | text | List/detail tag | Normalization via [sql.fn_normalize_developer_class(text)](supabase/migrations/20250817231500_stage4_import.sql:153) to Key Strategic/Managed/Inbound |
| deployment_specialist | Source spreadsheet | public.projects.deployment_specialist | Deployment Specialist | text | Not shown in current UI | Drives USER membership via [sql.fn_find_ds_user_id(text)](supabase/migrations/20250817231500_stage4_import.sql:194) |
| relationship_manager | Source spreadsheet | public.projects.relationship_manager | Relationship Manager | text | Planned in UI spec (Overview); not implemented | Drives USER membership via [sql.fn_find_rm_user_id(text,text)](supabase/migrations/20250817231500_stage4_import.sql:210) |
| rm_preferred_username | Source spreadsheet | public.projects.rm_preferred_username | Relationship Manager ID | text | Not shown | Preferred identifier for RM mapping |
| efscd | Source spreadsheet | public.projects.efscd | EFSCD | date | Detail Timeline; status compute | Added in [supabase/migrations/20250818062000_stage5_status_compute.sql](supabase/migrations/20250818062000_stage5_status_compute.sql:8) |
| developer_design_submitted | Source spreadsheet | public.projects.developer_design_submitted | Developer Design Submitted | date | Not in current UI | Available for future timeline/filters |
| developer_design_accepted | Source spreadsheet | public.projects.developer_design_accepted | Developer Design Accepted | date | Not in current UI | Input to status rule C in [sql.fn_projects_derived_status_compute(uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:59) |
| issued_to_delivery_partner | Source spreadsheet | public.projects.issued_to_delivery_partner | Issued to Delivery Partner | date | Not in current UI | Input to Late App waiver rules |
| practical_completion_certified | Source spreadsheet | public.projects.practical_completion_certified | Practical Completion Certified (PCC) | date | Not in current UI | Input to status rules D/E |
| delivery_partner_pc_sub | Source spreadsheet | public.projects.delivery_partner_pc_sub | Delivery Partner PC Sub | date | Not in current UI | UI spec shows as optional badge |
| in_service | Source spreadsheet | public.projects.in_service | In Service | date | Not in current UI | Status completion precedence input |
| derived_status | Derived | public.projects.derived_status | Overall Project Status | enum text | List chip; detail Overview | Allowed values enforced by CHECK in [supabase/migrations/20250818062000_stage5_status_compute.sql](supabase/migrations/20250818062000_stage5_status_compute.sql:24) |
| created_at | System | public.projects.created_at | — | timestamptz | Internal | Default now() |

Notes on partner_org name for UI: UI reads partner_org:partner_org_id(name) in list/detail to display the Delivery Partner label, see [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:195) and [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:145).

2. Source spreadsheet fields present in contract but not stored in DB (MVP gap)
The following headers are accepted by the import contract but are not persisted on public.projects in the current migrations. They appear in the UI spec and should be added if required for UI/filters/reports.

| Contract header | Source type | Supabase storage | UI label(s) | Data type | Where used (spec) | Notes |
|---|---|---|---|---|---|---|
| address | Source spreadsheet | Not stored | Address | string | Overview, List secondary line | In [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:186) |
| development_type | Source spreadsheet | Not stored | Development type | enum | Overview, filters | Allowed: Residential, Commercial, Mixed Use |
| build_type | Source spreadsheet | Not stored | Build Type | enum | Overview, filters | Allowed: SDU, MDU, HMDU, MCU |
| fod_id | Source spreadsheet | Not stored | FOD ID | string | Overview (when present) | — |
| premises_count | Source spreadsheet | Not stored | Premises Count | integer | Overview counters | Display as numeric pill |
| residential | Source spreadsheet | Not stored | Residential | integer | Overview counters | UI decision resolved as integer count |
| commercial | Source spreadsheet | Not stored | Commercial | integer | Overview counters | — |
| essential | Source spreadsheet | Not stored | Essential | integer | Overview counters | — |
| latitude | Source spreadsheet | Not stored | latitude | decimal | Overview (link to maps) | Link-only rule in PRD |
| longitude | Source spreadsheet | Not stored | longitude | decimal | Overview (link to maps) | — |

3. App-only user-generated content (UGC)
These fields are created/edited in the app and governed by RLS. They are never overwritten by imports.

3.1 Contacts — table public.contacts
Source: App-only
Storage anchor: [supabase/migrations/20250817061900_omni_bootstrap.sql](supabase/migrations/20250817061900_omni_bootstrap.sql:171)
UI: Project Detail → Contacts tab, see [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:560)

| Field | Supabase storage | UI label | Data type | Where used | Notes |
|---|---|---|---|---|---|
| id | public.contacts.id | — | uuid | Internal | — |
| project_id | public.contacts.project_id | — | uuid | RLS scope | FK to projects |
| created_by | public.contacts.created_by | — | uuid | RLS creator checks | Must equal auth.uid() on insert |
| name | public.contacts.name | Name | string | List + form | Required |
| company | public.contacts.company | Company | string | List + form | Optional |
| role | public.contacts.role | Role | string | List + form | Optional |
| phone | public.contacts.phone | Phone | string | List + form | Optional |
| email | public.contacts.email | Email | string | List + form | Optional |
| created_at | public.contacts.created_at | — | timestamptz | List ordering | — |
| updated_at | public.contacts.updated_at | — | timestamptz | Internal | — |

3.2 Engagements — table public.engagements
Source: App-only
Storage anchor: [supabase/migrations/20250817061900_omni_bootstrap.sql](supabase/migrations/20250817061900_omni_bootstrap.sql:185)
UI: Project Detail → Engagements tab, see [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:610)

| Field | Supabase storage | UI label | Data type | Where used | Notes |
|---|---|---|---|---|---|
| id | public.engagements.id | — | uuid | Internal | — |
| project_id | public.engagements.project_id | — | uuid | RLS scope | FK to projects |
| created_by | public.engagements.created_by | — | uuid | RLS creator checks | Must equal auth.uid() on insert |
| kind | public.engagements.kind | Kind | text | List + future filters | UI inserts "note" today |
| body | public.engagements.body | Notes | text | List | Required |
| created_at | public.engagements.created_at | — | timestamptz | List ordering | — |
| updated_at | public.engagements.updated_at | — | timestamptz | Internal | — |

3.3 Attachments metadata — table public.attachments_meta
Source: App-only
Storage anchor: [supabase/migrations/20250817061900_omni_bootstrap.sql](supabase/migrations/20250817061900_omni_bootstrap.sql:198)
UI: Project Detail → Attachments tab, see [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:647)

| Field | Supabase storage | UI label | Data type | Where used | Notes |
|---|---|---|---|---|---|
| id | public.attachments_meta.id | — | uuid | Internal | — |
| project_id | public.attachments_meta.project_id | — | uuid | RLS scope | FK to projects |
| created_by | public.attachments_meta.created_by | — | uuid | RLS creator checks | Must equal auth.uid() on insert |
| bucket | public.attachments_meta.bucket | — | text | Internal | Always "attachments" |
| object_name | public.attachments_meta.object_name | Filename | text | List | Path: tenant_id/stage_application/object_uuid |
| content_type | public.attachments_meta.content_type | Type | text | List | e.g., image/jpeg, application/pdf |
| size_bytes | public.attachments_meta.size_bytes | Size | bigint | List | Shown via formatter |
| created_at | public.attachments_meta.created_at | — | timestamptz | List ordering | — |

4. Assignment, membership, and directories (supporting fields)
These fields support visibility and membership derived from imported Delivery Partner / DS / RM values.

| Concept | Supabase storage | Purpose | Notes |
|---|---|---|---|
| Partner org (canonical) | public.partner_org.id, public.partner_org.name | Canonical Delivery Partner orgs | Seeded in [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:74) |
| Partner normalization | public.partner_normalization.source_label → partner_org_id | Map import labels to canonical | Unique on lower(trim(source_label)) |
| Project membership | public.project_membership.member_partner_org_id | ORG visibility | Materialized/upserted in merge |
| Project membership | public.project_membership.member_user_id | USER visibility (DS, RM) | Reconciled in merge/backfill |
| DS directory | public.ds_directory.display_name, preferred_username, user_id | Map DS identifiers to auth.users | Lookup via [sql.fn_find_ds_user_id(text)](supabase/migrations/20250817231500_stage4_import.sql:194) |
| RM directory | public.rm_directory.display_name, preferred_username, user_id | Map RM identifiers to auth.users | Lookup via [sql.fn_find_rm_user_id(text,text)](supabase/migrations/20250817231500_stage4_import.sql:210) |
| Import anomalies | public.import_anomalies.* | Record unresolved mappings and issues | Written by merge RPC, see [supabase/migrations/20250817231500_stage4_import.sql](supabase/migrations/20250817231500_stage4_import.sql:93) |
| Staging lineage | public.staging_imports.* (batch_id, batch_checksum, row_count, source, correlation_id, raw) | Idempotency and audit | Referenced by [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250817231500_stage4_import.sql:243) |

5. Derived/calculated fields and definitions

5.1 Overall Project Status — derived_status
- Storage: public.projects.derived_status (text, constrained), see [supabase/migrations/20250818062000_stage5_status_compute.sql](supabase/migrations/20250818062000_stage5_status_compute.sql:24)
- Values: In Progress; In Progress - Overdue; Complete; Complete Overdue; Complete Overdue Late App; see [components/projects/StatusChip.tsx](components/projects/StatusChip.tsx:10)
- Computation: [sql.fn_projects_derived_status_compute(uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:59) using inputs efscd, stage_application_created (tenant-local date), developer_design_accepted, issued_to_delivery_partner, practical_completion_certified, in_service, and business-day deltas from [sql.fn_business_days_between(date,date)](supabase/migrations/20250818062000_stage5_status_compute.sql:41)
- Recompute triggers:
  - On write to watched date columns via trigger [sql.trg_projects_status_after_write()](supabase/migrations/20250818062000_stage5_status_compute.sql:316)
  - After imports for affected projects via [sql.fn_projects_derived_status_recompute_by_staging(uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:234)

5.2 Late App classification (ephemeral)
- Not stored as a column; computed inside [sql.fn_projects_derived_status_compute(uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:124) using business days between stage_application_created (tenant-local date) and efscd < 70.
- Influences which overdue rules apply (e.g., PCC waiver and completion labels).

5.3 Display rule — Delivery Partner Not Yet Assigned
- When partner_org_id is null (delivery_partner blank or Unassigned), UI displays Delivery Partner as Not Yet Assigned; see [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:167) and UI implementations [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:417)

6. Cross-reference: field usage in the current app build

Projects List (index)
- Selects: id, stage_application, stage_application_created, derived_status, developer_class, partner_org:partner_org_id(name) from public.projects; see [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:192)
- Search/filter implemented: Stage Application ilike; Overall Project Status chip filters; excludes rows with derived_status is null by default; see [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:195)
- UI chips defined for status values; see [components/projects/StatusChip.tsx](components/projects/StatusChip.tsx:16)

Project Detail
- Overview displays: Stage Application, Delivery Partner (partner_org.name), Developer Class, Derived Status, Stage App Created; see [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:515)
- Timeline displays: EFSCD only (MVP); other milestones are fetched but not shown yet; see [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:546)
- Contacts tab uses fields from public.contacts; see [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:560)
- Engagements tab uses fields from public.engagements; see [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:611)
- Attachments tab uses fields from public.attachments_meta; see [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:648)

7. Gaps and proposed changes for alignment

- Persist contract fields needed by UI/filters: address, development_type, build_type, fod_id, premises_count, residential, commercial, essential, latitude, longitude on public.projects; add indexes for planned filters.
- Extend [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:349) to upsert the above fields (COALESCE-preserving where appropriate) and normalize allowed codes.
- Update Projects List and Detail screens to fetch/show Address and planned chips/filters per [docs/product/projects-feature-ui-ux.md](docs/product/projects-feature-ui-ux.md:346).
- Consider storing Late App as a materialized boolean if needed for reporting; otherwise keep as computed.
- Confirm labels and enums in UI match status and developer class canonical sets.

End of inventory.
8. Implementation Plan — Field Changes and Missed Fields Backfill (for review)

A. Summary of required changes (per feedback)
- Remove rm_preferred_username from spreadsheet contract and import path; relationship_manager remains present as the sole RM identifier.
- Split Address into three spreadsheet columns: Address, Suburb, State; persist all three and display a composed address in UI.
- Add Practical Completion Notified milestone (date) sourced from spreadsheet; timeline placement immediately before Practical Completion Certified.
- Make development_type derived on the server:
  - If residential > 0 and commercial = 0 → Residential
  - If commercial > 0 and residential = 0 → Commercial
  - If residential > 0 and commercial > 0 → Mixed Use
  - Else → null
- Persist the previously missed spec fields to public.projects and surface in UI: build_type, fod_id, premises_count, residential, commercial, essential, latitude, longitude, plus the address triplet.

B. Database schema migration (Stage 6)
- New migration file: [supabase/migrations/20250820100000_stage6_projects_field_alignment.sql](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1)
- Alter public.projects (idempotent, IF NOT EXISTS):
  - address text
  - suburb text
  - state text
  - build_type text
  - fod_id text
  - premises_count integer check (premises_count >= 0)
  - residential integer default 0 check (residential >= 0)
  - commercial integer default 0 check (commercial >= 0)
  - essential integer default 0 check (essential >= 0)
  - latitude numeric(9,6) null
  - longitude numeric(9,6) null
  - development_type text check (development_type in ('Residential','Commercial','Mixed Use'))
  - practical_completion_notified date
- Indexes (duplicates-safe):
  - create index if not exists projects_devtype_idx on public.projects (development_type)
  - create index if not exists projects_build_type_idx on public.projects (build_type)
  - optional for geo-search later: none required now
- Notes:
  - Keep rm_preferred_username column in DB for compatibility, but stop updating it; schedule deprecation in a future migration after data audit.

C. Import contract and Edge Function updates
- Update contract:
  - Remove development_type and rm_preferred_username headers
  - Add Suburb, State, Practical Completion Notified headers
  - Clarify development_type derivation rules (server-side) and address composition for UI
  - File to edit: [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:32)
- Edge Function changes: [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:25)
  - Update ROW_KEYS: remove development_type, rm_preferred_username; add suburb, state, practical_completion_notified
  - normalizeRow:
    - Ensure premises_count, residential, commercial, essential → integers (>=0, default 0)
    - Ensure latitude, longitude → floats (nullable)
    - New string keys: suburb, state
  - stableChecksumString: include the new keys in the exact order to match the SQL checksum
  - Auth, rate limiting, and staging write are unchanged

D. Merge and compute functions (SQL) updates
- Update rows checksum helper to reflect new keys:
  - Function: [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250817231500_stage4_import.sql:243)
  - Actions: remove development_type and rm_preferred_username entries; add suburb, state, practical_completion_notified in the concatenation list
- Update merge RPC to persist new fields and derive development_type:
  - Function: [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:349)
  - Parse new fields:
    - Address (text), Suburb (text), State (text)
    - build_type (text), fod_id (text)
    - premises_count, residential, commercial, essential (int)
    - latitude, longitude (numeric)
    - practical_completion_notified (date from timestamptz::date)
  - Derive development_type in code path (not from payload):
    - case
      when residential > 0 and commercial > 0 then 'Mixed Use'
      when residential > 0 then 'Residential'
      when commercial > 0 then 'Commercial'
      else null
    - Write development_type in insert and on-conflict update (COALESCE-preserving if you want to avoid overwriting with nulls)
  - Stop reading rm_preferred_username from payload; set v_rm_preferred_username := null; remove it from inserted/updated columns (leave column intact, no-op updates)
  - Add new columns to INSERT ... VALUES and ON CONFLICT DO UPDATE set-list with COALESCE rules:
    - address, suburb, state, build_type, fod_id
    - premises_count, residential, commercial, essential
    - latitude, longitude
    - practical_completion_notified
    - development_type (computed)
  - Recompute derived status unchanged (no rules depend on Practical Completion Notified today)
- Status compute:
  - No changes to [sql.fn_projects_derived_status_compute(uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:59)
  - Consider including practical_completion_notified in a future status rules iteration if product decides

E. UI updates (Expo app)
- Projects List: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:58)
  - Select additional fields: address, suburb, state (compose second line as "Address, Suburb State")
  - Later: add filters for development_type and build_type once present in DB
- Project Detail: [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:35)
  - Overview: display composed address (Address, Suburb State)
  - Timeline tab: add "Practical Completion Notified" milestone (date) immediately before "Practical Completion Certified"
  - Consider surfacing premises counters (premises_count, residential, commercial, essential) in Overview per UI spec
- No UI dependency on rm_preferred_username; RM is display_name-based only

F. Verification and test artifacts
- New verification script: [docs/sql/stage6-field-alignment-verify.sql](docs/sql/stage6-field-alignment-verify.sql:1)
  - Asserts:
    - Columns exist on public.projects
    - Check constraints present for counts and development_type
    - Merge writes new columns on a sample import payload
    - development_type derived correctly for sample permutations of residential/commercial
    - practical_completion_notified is populated when provided
- Update smoke tests as needed:
  - Extend [docs/sql/stage5-status-smoke-tests.sql](docs/sql/stage5-status-smoke-tests.sql:1) minimally to assert no change in status logic when practical_completion_notified is present
- Update contract verify (optional):
  - Add a quick check for contract header presence post-edit

G. Backfill strategy
- Development_type is derived; for existing rows without counts, leave null until next import
- If any historical backfill is desired:
  - Run a one-off SQL to derive development_type for rows where residential/commercial exist
  - Optional backfill for address triplet if a single address string existed elsewhere (not present today)

H. Rollout order and deployment notes
1) Apply schema migration: [supabase/migrations/20250820100000_stage6_projects_field_alignment.sql](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1)
2) Update Edge Function: [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:25)
3) Update Stage 4 SQL helper: [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250817231500_stage4_import.sql:243)
4) Update Stage 5 merge RPC: [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:349)
5) Update Import Contract doc: [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:32)
6) Deploy UI updates: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:58), [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:35)
7) Run verification SQL: [docs/sql/stage6-field-alignment-verify.sql](docs/sql/stage6-field-alignment-verify.sql:1)

- Downtime: None expected; functions are CREATE OR REPLACE; migration is additive
- Rollback: Re-deploy previous Edge Function/SQL versions; new columns can remain (unused) without impact

I. Acceptance criteria
- Import accepts Address, Suburb, State, Practical Completion Notified and no longer requires development_type or rm_preferred_username
- public.projects rows persist the new fields; development_type is derived correctly from counts
- Projects List shows composed address; Detail Timeline shows Practical Completion Notified in the correct position
- Derived status values remain unchanged by the presence/absence of Practical Completion Notified
- Verification SQL passes in both local and remote modes

J. Timeline and responsibilities (suggested)
- Day 1: Schema migration; Edge Function and SQL helpers updates
- Day 2: Merge RPC update; Contract doc update; Verification SQL
- Day 3: UI updates; QA pass on UI and verification scripts; stakeholder review
- Day 4: Enable updated import from Power Automate; monitor; finalize deprecation note for rm_preferred_username

K. Notes and deprecation
- rm_preferred_username: cease reading/updating now; plan removal after a cooling-off period and data audit in a subsequent migration
- development_type: treated as derived; contract and ETL should not attempt to send this field
L. UI exposure checklist — Section 2 fields (binding)

Objective: Ensure every Section 2 field currently missing from the UI becomes visible in the app, except latitude and longitude which remain stored-only for future features.

Binding UI changes
- Projects List [ProjectsListScreen](app/(protected)/(tabs)/projects/index.tsx:77)
  - Render second line as a composed address using Address, Suburb, State (e.g., “12 Main St, Adelaide SA”).
  - Add filters:
    - Development Type (multi-select): Residential, Commercial, Mixed Use.
    - Build Type (multi-select): SDU, MDU, HMDU, MCU.
- Project Detail — Overview [ProjectDetailScreen](app/(protected)/projects/[stage_application].tsx:84)
  - Identification and Address:
    - Composed Address line (Address, Suburb State).
    - FOD ID (when present).
  - Classification:
    - Development Type (derived on server).
    - Build Type.
  - Scale:
    - Premises Count (total).
    - Residential, Commercial, Essential (integer counters).
- Project Detail — Timeline [ProjectDetailScreen](app/(protected)/projects/[stage_application].tsx:542)
  - Insert milestone “Practical Completion Notified” immediately before “Practical Completion Certified”.

Storage-only fields (not displayed)
- Latitude and Longitude remain hidden in the UI; retained in the database for future features.

Acceptance checks (must pass)
- List screen shows composed address line and exposes Development Type and Build Type filters; queries include these fields in the select projection in [ProjectsListScreen](app/(protected)/(tabs)/projects/index.tsx:192).
- Detail Overview shows Development Type, Build Type, FOD ID (if present), Premises Count, and Residential/Commercial/Essential counters in [ProjectDetailScreen](app/(protected)/projects/[stage_application].tsx:515).
- Detail Timeline shows “Practical Completion Notified” before “Practical Completion Certified” in [ProjectDetailScreen](app/(protected)/projects/[stage_application].tsx:546).
- Latitude and Longitude are not rendered anywhere in the UI but exist in public.projects for future use.

Notes
- Development Type is derived on the server (not from spreadsheet) per rules in Section 8.D; UI only displays the computed value.
- This checklist is binding for implementation and QA; it supersedes any “consider” language elsewhere in this document for the listed fields.
M. Consolidated Task List — Implement all agreed changes

Execution order is optimized to avoid breaking imports and to keep UI in sync with schema and merge semantics.

1) Database migrations (Stage 6)
- Create migration: [supabase/migrations/20250820100000_stage6_projects_field_alignment.sql](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1)
  - public.projects (add columns if not exists)
    - address text
    - suburb text
    - state text
    - build_type text
    - fod_id text
    - premises_count integer check (premises_count >= 0)
    - residential integer default 0 check (residential >= 0)
    - commercial integer default 0 check (commercial >= 0)
    - essential integer default 0 check (essential >= 0)
    - latitude numeric(9,6) null
    - longitude numeric(9,6) null
    - development_type text check (development_type in ('Residential','Commercial','Mixed Use'))
    - practical_completion_notified date
  - Indexes (duplicates-safe)
    - create index if not exists projects_devtype_idx on public.projects (development_type)
    - create index if not exists projects_build_type_idx on public.projects (build_type)
  - public.contacts (extend schema)
    - add column if not exists company text null
    - add column if not exists role text null

Deployment Notes — Task 1
- [x] Created migration: [supabase/migrations/20250820100000_stage6_projects_field_alignment.sql](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1) — Adds public.projects columns (address, suburb, state, build_type, fod_id, premises_count, residential, commercial, essential, latitude, longitude, development_type, practical_completion_notified); enforces named CHECKs (projects_premises_count_nonneg_chk, projects_residential_nonneg_chk, projects_commercial_nonneg_chk, projects_essential_nonneg_chk, projects_development_type_enum_chk); creates indexes (projects_devtype_idx, projects_build_type_idx); extends public.contacts with company, role. Idempotent via ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS and conditional DO $$ ... $$ guards; defaults for count columns coerced to 0 if column pre-existed without a default.

- [ ] Apply locally (linked project via Supabase CLI)
yarn db:push
# or
supabase db push

- [ ] Runbook reference
[docs/security/supabase-migrations-run-sheet.md](docs/security/supabase-migrations-run-sheet.md:1)

- [ ] Post-apply verification (psql or node runner with -e)
-- Projects columns
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'projects'
  and column_name in (
    'address','suburb','state','build_type','fod_id',
    'premises_count','residential','commercial','essential',
    'latitude','longitude','development_type','practical_completion_notified'
  )
order by column_name;

-- Non-negative and enum constraints
select conname
from pg_constraint
where conrelid = 'public.projects'::regclass
  and conname in (
    'projects_premises_count_nonneg_chk',
    'projects_residential_nonneg_chk',
    'projects_commercial_nonneg_chk',
    'projects_essential_nonneg_chk',
    'projects_development_type_enum_chk'
  )
order by conname;

-- Indexes present
select indexname
from pg_indexes
where schemaname = 'public' and tablename = 'projects'
  and indexname in ('projects_devtype_idx','projects_build_type_idx')
order by indexname;

-- Contacts columns
select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'contacts'
  and column_name in ('company','role')
order by column_name;

- [ ] Rollback note
Additive-only migration; safe to leave in place if subsequent steps are reverted.
2) Import contract and documentation updates
- Edit contract headers and rules: [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:32)
  - Remove development_type (now derived server-side)
  - Remove rm_preferred_username
  - Add Suburb, State, Practical Completion Notified
  - Clarify Address triplet presentation in UI and development_type derivation from residential/commercial counts

Deployment Notes — Task 2
- Summary of edits
  - Contract updates in [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:32):
    - Removed headers: development_type, rm_preferred_username (RM mapping now via relationship_manager only with server-side directory resolution).
    - Added headers: suburb, state, practical_completion_notified.
    - Clarified: development_type is derived on the server from residential/commercial counts (see rules in [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:234)); UI composes address as "Address, Suburb State".
    - Canonical header order explicitly documented (practical_completion_notified placed after issued_to_delivery_partner):
      ```
      stage_application,address,suburb,state,eFscd,build_type,delivery_partner,fod_id,premises_count,residential,commercial,essential,developer_class,latitude,longitude,relationship_manager,deployment_specialist,stage_application_created,developer_design_submitted,developer_design_accepted,issued_to_delivery_partner,practical_completion_notified,practical_completion_certified,delivery_partner_pc_sub,in_service
      ```
    - Mapping table additions:
      - suburb → public.projects.suburb (text)
      - state → public.projects.state (text)
      - practical_completion_notified → public.projects.practical_completion_notified (date; parsed from timestamptz::date in merge, see [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:232))
- External integration (Power Automate/SharePoint)
  - Update the exporter to emit the new headers and remove the deprecated ones (development_type, rm_preferred_username). Use the canonical order above to minimize diff noise in checksum and merge logic.
  - Validate a pilot CSV with the new columns against the import endpoint and confirm a 200 response with no header warnings.
  - Confirm Supabase staging receives payloads by checking staging lineage entries (see public.staging_imports in [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:128)).
- Verification steps (manual quick checks)
  - Confirm the contract document’s header list matches the expected set: no development_type / rm_preferred_username; includes suburb, state, practical_completion_notified (see [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:32)).
  - After Task 3 + 4 are deployed, run simple SELECTs to verify persistence:
    ```
    select stage_application, address, suburb, state, practical_completion_notified
    from public.projects
    order by stage_application
    limit 10;
    ```
- Runbook references
  - Imports operations: [docs/security/supabase-imports-runbook.md](docs/security/supabase-imports-runbook.md:1)
  - Migration execution: [docs/security/supabase-migrations-run-sheet.md](docs/security/supabase-migrations-run-sheet.md:1)
- Rollback note
  - Contract changes are forward-only for the data producer. If rollback is needed, temporarily re-add the old headers in the exporter while keeping the server tolerant to extra columns. No database schema rollback required.
3) Edge Function ingestion updates
- Update row schema and normalization: [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:25)
  - Update ROW_KEYS:
    - Remove development_type, rm_preferred_username
    - Add suburb, state, practical_completion_notified
  - Update normalizeRow:
    - Integers: premises_count, residential, commercial, essential (>=0, blanks → 0)
    - Floats: latitude, longitude (nullable)
    - Strings: address, suburb, state, build_type, fod_id, relationship_manager, deployment_specialist
  - Update stableChecksumString to include the new keys and match SQL order exactly

Deployment Notes — Task 3
- Summary of edits
  - In [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:25):
    - Removed keys: development_type, rm_preferred_username (omitted from payload and checksum).
    - Added keys: suburb, state, practical_completion_notified.
    - [normalizeRow()](supabase/functions/import-projects/index.ts:162) normalization:
      - Integers: premises_count, residential, commercial, essential → non-negative integers; blanks/invalid → 0.
      - Floats: latitude, longitude → parse to float; blanks/invalid → null.
      - Strings: address, suburb, state, build_type, fod_id, relationship_manager, deployment_specialist → trim; blanks → null.
      - Date: practical_completion_notified → ISO date string “YYYY-MM-DD” (discard timezone); blanks/invalid → null.
    - [stableChecksumString()](supabase/functions/import-projects/index.ts:185) ordering mirrors the Stage 4 SQL helper with Stage 6 insertions:
      - Address group: address, suburb, state (in that order).
      - Milestone group: practical_completion_notified immediately before practical_completion_certified.
      - Deprecated keys are not included in the checksum.
    - Staging payload (staging_imports.raw) now contains only the updated key set; deprecated keys are dropped even if present in inbound rows.
  - Ordering reference: [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250817231500_stage4_import.sql:243). This function will be updated in Task 4 to the same set/order to keep checksums consistent server-side.

- Deployment
  - supabase functions deploy import-projects
  - Optional local test: supabase functions serve --env-file .env

- Coordination
  - Task 3 (Edge Function) and Task 4 (SQL helpers) must be released together to avoid checksum mismatches between [stableChecksumString()](supabase/functions/import-projects/index.ts:185) and [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250817231500_stage4_import.sql:243).

- Quick verification
  - Send a sample row including suburb, state, practical_completion_notified via the function ingress; expect a 200 response.
  - Verify public.staging_imports:
    - Presence of new keys in raw (suburb/state/practical_completion_notified).
    - Check that batch_checksum is stable across repeated submissions of the same normalized data.
  - Confirm deprecated keys (development_type, rm_preferred_username) are ignored if sent by legacy exporters.

- Rollback
  - Re-deploy the previous Edge Function version if needed. The server tolerates extra/unused columns and the Stage 6 migration is additive, so no schema rollback is required.
4) SQL helpers and merge RPC updates
- Update checksum helper list: [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250817231500_stage4_import.sql:243)
  - Remove development_type, rm_preferred_username
  - Add suburb, state, practical_completion_notified
- Update merge upsert and derivation logic: [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:349)
  - Parse and coalesce-preserve:
    - address, suburb, state, build_type, fod_id
    - premises_count, residential, commercial, essential
    - latitude, longitude
    - practical_completion_notified (timestamptz::date)
  - Derive development_type server-side from residential/commercial:
    - both > 0 → 'Mixed Use'
    - residential > 0 only → 'Residential'
    - commercial > 0 only → 'Commercial'
    - else null
  - Cease reading/writing rm_preferred_username (leave column in DB; no-op)
  - Keep post-merge recompute call for status unchanged

Deployment Notes — Task 4
- Summary:
  - Functions replaced: [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250820101500_stage6_functions_alignment.sql:1), [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250820101500_stage6_functions_alignment.sql:1).
  - Keys removed: development_type, rm_preferred_username; Keys added: suburb, state, practical_completion_notified.
  - Development Type now computed server-side from residential/commercial.
- Apply:
  - supabase db push
  - Or follow [docs/security/supabase-migrations-run-sheet.md](docs/security/supabase-migrations-run-sheet.md:1)
- Coordination:
  - Deploy together with Task 3 (Edge Function) to prevent checksum mismatches.
- Verification (quick checks):
  - select proname from pg_proc where proname in ('fn_rows_checksum','fn_projects_import_merge');
  - Review concatenation order in [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250820101500_stage6_functions_alignment.sql:1) matches importer key order.
  - Exercise merge with a minimal staging payload including suburb/state/practical_completion_notified; SELECT from public.projects confirms persisted fields and derived development_type expected for permutations of residential/commercial.
- Rollback:
  - Re-deploy previous function migration; DB schema from Task 1 is additive and compatible.
5) UI — Projects List
- File: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:58)
  - Select projection: add address, suburb, state, development_type, build_type
  - Render composed address as second line: “Address, Suburb State”
  - Filters:
    - Multi-select Development Type chips
    - Multi-select Build Type chips
  - Query builder: apply .in() filters for development_type and build_type (with supporting indexes from task 1)

Deployment Notes — Task 5
- Summary of changes (UI):
  - Extended projection in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:192) to include address, suburb, state, development_type, build_type while preserving existing eq(tenant_id), not(derived_status is null), search ilike, and status .in() filters per spec [Task 5](docs/product/projects-data-field-inventory.md:541).
  - Added additional fields to row type in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:58): address, suburb, state, development_type, build_type.
  - Render: Composed secondary line as “Address, Suburb State” in renderItem with null-safe formatting in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:385). If address is missing, the line is hidden; when suburb/state are missing, available parts render without dangling punctuation/spaces.
  - Filters (multi-select):
    - Development Type chips (Residential, Commercial, Mixed Use) with .in('development_type', selections) applied in the query builder in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:192).
    - Build Type chips (SDU, MDU, HMDU, MCU) with .in('build_type', selections) applied in the query builder in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:192).
    - Chip groups surface inline (above the list) and inside the Filters bottom sheet with clear labels in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:487).
  - Inline comments reference spec anchors and index support per [supabase/migrations/20250820100000_stage6_projects_field_alignment.sql](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1).

- Deployment
  - Expo (local): npx expo start -c
  - OTA update (if applicable): use your standard command (e.g., eas update) or static export: npx expo export

- Verification
  - List rendering:
    - Items display “Address, Suburb State” where available; when Address is blank, the secondary line is hidden. See implementation in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:385).
  - Filters:
    - Development Type chips filter rows via SQL .in('development_type', ...); Build Type chips filter rows via SQL .in('build_type', ...). Confirm each independently and in combination.
    - Confirm existing search and status chips continue to work as before (ilike on Stage Application; .in() on Overall Status).
  - Performance:
    - Validate list remains responsive with filters. Dev/Build filters are index-backed by [projects_devtype_idx](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1) and [projects_build_type_idx](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1).

- Rollback
  - UI-only: revert [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:58) to the previous commit; backend schema changes from Task 1 are additive and remain compatible.
6) UI — Project Detail (Overview and Timeline)
- File: [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:35)
  - Overview tab:
    - Show composed address (Address, Suburb State)
    - Show FOD ID when present
    - Show Development Type (derived) and Build Type
    - Show Premises Count
    - Show Residential, Commercial, Essential counters
  - Timeline tab:
    - Insert “Practical Completion Notified” milestone before “Practical Completion Certified”
  - Do not display latitude/longitude (stored-only)

Deployment Notes — Task 6
- Summary of UI edits
  - In [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:35), the Project Detail screen now surfaces the following on the Overview tab (see render section around [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:515)):
    - Composed address line “Address, Suburb State” with null-safe formatting:
      - Address required to show the line.
      - Suburb/State optional without dangling punctuation/spaces.
    - FOD ID (shown when present).
    - Development Type (server-derived) and Build Type (strings).
    - Premises Count total and counters for Residential, Commercial, Essential (integers).
  - Timeline tab (see block around [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:546)):
    - New milestone row “Practical Completion Notified” shown immediately before “Practical Completion Certified”; hides when null. EFSCD row retained unchanged.
- Deployment steps
  - Restart Expo to clear cache:
    npx expo start -c
  - OTA updates (if applicable): publish via your standard command (e.g., eas update) or static export (npx expo export) as per your release process.
- Verification steps
  - Overview:
    - Open a project with address and counters; confirm the composed line appears exactly as “Address, Suburb State”.
    - Remove suburb/state to confirm no dangling comma/space; remove address to confirm the address line is omitted entirely.
    - Validate Development Type and Build Type display. Development Type must reflect the server-derived value (no client derivation).
    - Confirm Premises Count and Residential/Commercial/Essential counters render correctly as integers.
    - Confirm latitude/longitude are not displayed (storage-only by design).
  - Timeline:
    - With a project containing practical_completion_notified, verify the “Practical Completion Notified” row appears immediately before “Practical Completion Certified”.
    - When practical_completion_notified is null, verify the row is hidden and that other milestones (e.g., EFSCD, PCC) retain their current behavior.
- Notes
  - Latitude/Longitude remain hidden by design; storage-only per [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:332).
  - Values must reflect server-derived Development Type; the UI does not compute/derive this value.
- Rollback
  - UI-only: revert [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:35) to the previous commit; backend schema remains additive and compatible.
7) UI — Contacts form and list
- File: [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:560)
  - Extend Add Contact form:
    - Add Company (optional)
    - Add Role (optional)
  - Insert payload to include company and role in supabase.from("contacts").insert({ ... })
  - Render company and role in Contacts list items when present

Deployment Notes — Task 7
- Summary
  - The Add Contact form in [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:560) is extended with optional Company and Role fields. Insert payload writes company and role. Contacts list renders company and role when present.
- Deployment
  - Restart Expo cache:
    ```
    npx expo start -c
    ```
- Verification
  - Create a contact with only Name → succeeds.
  - Create a contact including Company and/or Role → values appear in the Contacts list item secondary line.
  - Confirm persistence in DB:
    ```sql
    select name, company, role
    from public.contacts
    order by created_at desc
    limit 5;
    ```
- RLS note
  - created_by must equal the authenticated user on insert; this screen passes the current user id to satisfy policy (see [supabase/migrations/20250817061900_omni_bootstrap.sql](supabase/migrations/20250817061900_omni_bootstrap.sql:171)).
- Rollback
  - Revert UI changes in [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:560) to the previous commit; schema from Task 1 is additive and remains compatible.
8) Verification SQL and smoke tests
- Create verification script: [docs/sql/stage6-field-alignment-verify.sql](docs/sql/stage6-field-alignment-verify.sql:1)
  - Assert new public.projects columns exist with constraints and indexes
  - Assert public.contacts has company and role columns
  - Insert sample staging payload; run merge; verify
    - development_type derivation matrix (residential/commercial permutations)
    - practical_completion_notified persisted
    - address triplet persisted
- Update status smoke tests: [docs/sql/stage5-status-smoke-tests.sql](docs/sql/stage5-status-smoke-tests.sql:1)
  - Add assertion that presence/absence of practical_completion_notified does not affect derived_status outcomes

Deployment Notes — Task 8
- Summary
  - Created verification script [docs/sql/stage6-field-alignment-verify.sql](docs/sql/stage6-field-alignment-verify.sql:1) to assert schema, constraints, indexes, and merge behavior (development_type derivation, address triplet persistence, Practical Completion Notified persistence).
  - Updated status smoke tests [docs/sql/stage5-status-smoke-tests.sql](docs/sql/stage5-status-smoke-tests.sql:1) to assert Practical Completion Notified (PCN) does not change derived_status.
- How to run locally
  - node [scripts/run-sql.js](scripts/run-sql.js:1) docs/sql/stage6-field-alignment-verify.sql
  - node [scripts/run-sql.js](scripts/run-sql.js:1) docs/sql/stage5-status-smoke-tests.sql
  - Or using Supabase CLI:
    - supabase db execute --file docs/sql/stage6-field-alignment-verify.sql
    - supabase db execute --file docs/sql/stage5-status-smoke-tests.sql
- Remote run option
  - Follow [docs/security/supabase-migrations-run-sheet.md](docs/security/supabase-migrations-run-sheet.md:1) for executing verification scripts against the target environment.
- Expected outputs
  - “OK” notices for schema checks and derivation matrix in [docs/sql/stage6-field-alignment-verify.sql](docs/sql/stage6-field-alignment-verify.sql:1).
  - Smoke test addendum prints “PCN does not affect derived_status: OK” from [docs/sql/stage5-status-smoke-tests.sql](docs/sql/stage5-status-smoke-tests.sql:1).
- Rollback
  - Scripts are read-only or idempotent; no rollback required. If needed, revert edits to [docs/sql/stage5-status-smoke-tests.sql](docs/sql/stage5-status-smoke-tests.sql:1).
9) Rollout, QA, and runbook updates
- Apply migration: [supabase/migrations/20250820100000_stage6_projects_field_alignment.sql](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1)
- Deploy Edge Function: [supabase/functions/import-projects/index.ts](supabase/functions/import-projects/index.ts:25)
- Apply SQL helper and merge RPC updates:
  - [sql.fn_rows_checksum(jsonb)](supabase/migrations/20250817231500_stage4_import.sql:243)
  - [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](supabase/migrations/20250818062000_stage5_status_compute.sql:349)
- Update Import Contract doc: [docs/product/projects-import-contract.md](docs/product/projects-import-contract.md:32)
- Ship UI changes:
  - [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:58)
  - [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:35)
- Run verification: [docs/sql/stage6-field-alignment-verify.sql](docs/sql/stage6-field-alignment-verify.sql:1) locally and remote
- QA against “L. UI exposure checklist — Section 2 fields (binding)” in this document
- Update runbooks as needed (imports, anomalies, UI usage)

Deployment Notes — Task 9
- Summary:
  - Updated [docs/security/supabase-migrations-run-sheet.md](docs/security/supabase-migrations-run-sheet.md:1) with “Stage 6 — Projects Field Alignment Rollout”
  - Updated [docs/security/supabase-imports-runbook.md](docs/security/supabase-imports-runbook.md:1) with “Stage 6 Importer Coordination”
- Rollout commands (exact lines):
```
supabase db push
supabase functions deploy import-projects
supabase db execute --file supabase/migrations/20250820101500_stage6_functions_alignment.sql
supabase db execute --file docs/sql/stage6-field-alignment-verify.sql
supabase db execute --file docs/sql/stage5-status-smoke-tests.sql
npx expo start -c
```
- QA checklist (reference binding UI checks in Section L):
  - Validate List composed address and filters in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx:192)
  - Validate Detail Overview fields and counters in [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:515)
  - Validate Timeline “Practical Completion Notified” placement in [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx:546)
- Coordination note:
  - Deploy Task 3 and Task 4 together to keep checksum alignment (function/sql).
- Rollback note:
  - Re-deploy previous Edge Function; function migration can be reverted if versioned; DB columns remain additive/safe.
11) Acceptance criteria (recap)
- Contract: Accepts Address, Suburb, State, Practical Completion Notified; does not send development_type or rm_preferred_username
- DB: public.projects and public.contacts have new columns with constraints/indexes as specified
- Ingestion and merge: Keys updated; development_type derived; rm_preferred_username ignored
- UI: Section 2 fields now shown (except latitude/longitude); Timeline includes Practical Completion Notified; Contacts capture Company and Role
- Tests: Verification and smoke tests pass; status compute unaffected by Practical Completion Notified