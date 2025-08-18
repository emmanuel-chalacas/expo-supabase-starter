# Projects Feature — Product Requirements Document

Author: Kilo Code
Status: Draft v0.5
Audience: Product managers, delivery partners, stakeholders
Date: 2025-08-15
References: [docs/projects-feature.md](docs/projects-feature.md), [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md), [docs/okta-oidc-supabase.md](docs/okta-oidc-supabase.md)

1. Summary
- The Projects Feature provides a unified, role-aware workspace to view project details, manage timelines, capture stakeholder engagement, store attachments, and collaborate with assigned delivery partners. It maintains a clean separation between data imported from the client spreadsheet and data created within the app, and scales for future integrations and reporting.

2. Problem statement and context
- Project information is fragmented across spreadsheets and ad-hoc communications, making it hard for PMs and delivery partners to stay aligned.
- Delivery partners need an accurate, up to date view of their assigned projects and an easy way to report progress and attach evidence from the field.
- PMs and deployment specialists need a single place to understand project status, review engagements, and coordinate with delivery partners while protecting imported master data from accidental edits.

3. Goals and success criteria
3.1 Goals
- Enable PMs and delivery partners to view and update project records based on permissions.
- Maintain separation of concerns between client imported data and app created data.
- Ensure role based data access so a delivery partner only sees assigned projects.
- Provide a scalable data structure to support future integrations and reporting.

3.2 Success criteria
- Visibility: Delivery partners see only assigned projects in lists and detail views.
- Edit scope: Imported project attributes are read only for non admin roles; user generated content is editable by authorized members.
- Adoption: 80 percent of active delivery partners log at least one engagement per week within three weeks of launch.
- Data quality: Fewer than 1 percent of imports require manual correction after automated merge and no user generated records are lost on import.
- Performance: Project list and detail load within two seconds on median mobile networks for tenants with up to five thousand projects.

4. Non goals
- Billing, invoice management, and notifications.
- Advanced offline first sync and conflict resolution beyond basic client caching.
- In app chat threads beyond comments captured as engagements.
- Complex scheduling or Gantt editing tooling.

5. Users and roles
Primary personas
- Project Manager: Oversees multiple projects, needs high level visibility, manages timelines, reviews partner activity, and curates stakeholder records.
- Deployment Specialist (Telco): Works for the main telco tenant, needs to see only the projects assigned to them (based on the synced Deployment Specialist field), logs engagements, and reviews partner activity.
- Relationship Manager (Telco): Sees only projects explicitly assigned to them (based on the synced Relationship Manager field), can create user-generated content on assigned projects.
- Delivery Partner: Works on assigned projects for one delivery partner organization, needs to see only their organization’s assigned projects, logs engagements, and uploads attachments.

Secondary roles
- Tenant Admin (Telco): Configures telco tenant data access, sets membership and roles, may perform administrative edits.
- Tenant Admin (Delivery Partner): Manages their organization’s users; has visibility only to their organization’s assigned projects via explicit project membership.
- Support or Vendor Admin: Limited, audited access for operational support when required.

Access control overview
- Delivery Partner: Sees only projects their delivery partner organization is assigned to; can add contacts, engagements, and attachments on those projects. Cannot change imported master data.
- Deployment Specialist (Telco): Sees only the projects where they are named as Deployment Specialist in the synced data (materialized as project membership).
- Project Manager (Telco): Sees projects for the telco tenant; can add and edit user generated content and, where permitted, manage membership.
- Tenant Admin (Telco): Full CRUD within telco tenant including certain imported field corrections aligned with policy.

6. Core user journeys
6.1 Browse and search projects
- Open the Projects list showing projects visible to the user by role and membership.
- Search by Stage Application (Application Number) or Address; filter by Development type, Build Type, Delivery Partner, Deployment Specialist (telco-only), Overall Project Status, or key date fields including Expected First Service Connection Date (EFSCD), Stage Application Created, Developer Design Submitted, Developer Design Accepted, Issued to Delivery Partner, Delivery Partner PC Sub, Practical Completion Certified, and In Service.
- Default sort: Descending by Stage Application Created; fallback to the latest key date present when Stage Application Created is unavailable.

6.2 View project detail
- See summary including key imported attributes, including FOD ID where present.
- Navigate tabs for Overview, Timeline, Contacts, Engagements, Attachments.

6.3 Manage timeline
- View timeline events derived from imported date fields:
  - Stage Application Created
  - Developer Design Submitted
  - Developer Design Accepted
  - Issued to Delivery Partner
  - Practical Completion Certified
  - Delivery Partner PC Sub
  - In Service
- Add simple timeline notes via engagements for on the ground updates.

6.4 Manage stakeholders and contacts
- Add and edit project scoped contacts captured in app.
- Link engagements to contacts where applicable.

6.5 Log engagements
- Record site visits, progress notes, or calls with notes and timestamps.
- Optionally tag to a contact and attach photos or documents.

6.6 Manage attachments
- Upload images and documents from device.
- View file previews and metadata; enforce access by membership.
- Constraints: Accept any file type; maximum 25 MB per file.

6.7 Collaborate with delivery partners
- PMs and deployment specialists review partner logged engagements and attachments.
- PMs provide feedback via new engagements or comments.

7. Feature scope for MVP
Included
- Protected Projects list filtered by role and membership.
- Project detail with tabs Overview, Timeline, Contacts, Attachments.
- Create and edit contacts and engagements for authorized users.
- Upload and view attachments with metadata and storage access control.
- Basic search and status filters on the Projects list.
- Read only imported project attributes in detail view for non admin roles.

Deferred
- Bulk actions, advanced filters, offline queueing, advanced timeline editing, and notifications.

8. Data ownership and sources high level
- Imported master data: See the Spreadsheet-synced fields list below. These are treated as read only for delivery partners and are corrected by admins via controlled processes.
- Unique identifier: Stage Application (Application Number) is a 14-character identifier beginning with STG-. It is the stable key for imports, joins, and search.
- App created data: Contacts, engagements, and attachment metadata are created in the app and never overwritten by imports.
- Merge behavior: Imports match projects by tenant id and Stage Application (Application Number). Imported updates refresh only these synced fields, preserving user generated content.
- Lineage and audit: Each project indicates which attributes are synced from spreadsheet versus app created. Attachment objects are stored in a private bucket with metadata rows used for authorization.

8.1 Spreadsheet-synced fields
The following fields sync from the client spreadsheet into the canonical project record. Do not add additional fields to this sync set.
- Stage Application
- Address
- Expected First Service Connection Date (EFSCD)
- Development type (Residential, Commercial, Mixed Use)
- Build Type (SDU, MDU, HMDU, MCU)
- Delivery Partner (Fulton Hogan, Ventia, UGL, Enerven, Servicestream, Not Yet Assigned)
- FOD ID
- Premises Count
- Residential
- Commercial
- Essential
- Developer Class - (Key Strategic, Managed, Inbound)
- latitude
- longitude
- Relationship Manager
- Deployment Specialist
- Stage Application Created
- Developer Design Submitted
- Developer Design Accepted
- Issued to Delivery Partner
- Practical Completion Certified
- Delivery Partner PC Sub
- In Service



Data type notes
- Residential, Commercial, Essential: integer counts (display as numeric counters in UI).

Normalization rules
- Delivery Partner: When the source spreadsheet Delivery Partner cell is blank, treat the project as Unassigned. UI must display Delivery Partner as Not Yet Assigned. No ORG membership is materialized for Unassigned rows.
- Developer Class: Source may provide Class 1, Class 2, Class 3, Class 4. Normalize to labels for UI and filters:
  - Class 1 → Key Strategic
  - Class 2 → Managed
  - Class 3 → Inbound
  - Class 4 → Inbound

UI exposure note: Not all of the above fields will appear in the front end UI. The exposure subset per role and screen will be confirmed in detailed design.

8.2 Assignment and tenancy model (visibility derived from synced fields)
- Tenancy
  - The main telco organization is modeled as the primary tenant that owns all canonical project records.
  - Delivery partner organizations are modeled as separate tenants for identity and administration of their users.
- Cross-organization access (scoped)
  - Delivery partner users are granted scoped access to the telco tenant’s projects via project membership. They see only projects where the synced Delivery Partner field matches their organization and membership is materialized accordingly. When Delivery Partner is blank (Unassigned), no ORG membership is created.
  - Deployment Specialist (telco staff) visibility is scoped by the synced Deployment Specialist field and materialized as project membership for that user within the telco tenant.
  - Relationship Manager (telco staff) visibility is assigned-only, scoped by the synced Relationship Manager field and materialized as project membership for that user within the telco tenant.
- Materialization
  - On each import, the system updates project membership based on Delivery Partner, Deployment Specialist, and Relationship Manager values. This drives list visibility and write permissions for user generated content.
  - No additional synced fields are introduced; membership is derived strictly from the provided list. Refer to [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md) for enforcement details.

8.3 Overall Project Status (derived)
- Status values
  - In Progress
  - In Progress - Overdue
  - Complete
  - Complete Overdue
  - Complete Overdue (Late App)

- Business-day calendar (MVP)
  - Business days are Monday to Friday; public holidays are not considered.

- Definitions and rules
  - Late Application
    - A project is considered Late App if Stage Application Created is less than 70 business days prior to EFSCD.
  - Completion precedence
    - If In Service is present:
      - Complete when In Service is on or before EFSCD.
      - Complete Overdue when In Service is after EFSCD.
      - Complete Overdue (Late App) when In Service is after EFSCD and the project is Late App.
  - In-progress evaluation (when In Service is not present)
    - In Progress if none of the overdue conditions apply as of today; otherwise In Progress - Overdue.
    - Overdue conditions as of today include any of:
      - Today is after EFSCD and In Service is not set.
      - Fewer than 60 business days remain until EFSCD and Developer Design Accepted is not achieved.
      - Developer Design Accepted occurred later than 60 business days before EFSCD.
      - Fewer than 20 business days remain until EFSCD and Practical Completion Certified (PCC) is not achieved, and either:
        - The project is not Late App; or
        - The project is Late App and more than 20 business days have elapsed since Issued to Delivery Partner without PCC achieved.
      - PCC occurred later than the allowed window:
        - Standard rule (not Late App): later than 20 business days before EFSCD.
        - Late App waiver: later than 20 business days after Issued to Delivery Partner.
    - Missing Issued to Delivery Partner on Late Apps
      - If Issued to Delivery Partner is missing, apply the standard PCC rule (require PCC at least 20 business days before EFSCD).
  - Dynamic recomputation
    - Overall Project Status is computed from the latest imported dates and is recalculated on each import. If EFSCD moves, status may change (e.g., from Overdue to not Overdue). No sticky states are retained.
  - Handling missing inputs
    - If EFSCD is missing, the status is not computed in MVP; UI hides the status chip and filters exclude these rows unless specified otherwise.

9. Access control principles high level
- Tenant scope: All data is tenant scoped and isolated.
- Project membership: Delivery partners and deployment specialists are assigned per project. Membership gates visibility and write access for user generated content.
- Role scopes: Tenant Admin (Telco) may edit certain imported attributes; delivery partners cannot. PMs and deployment specialists primarily edit user generated content within their scope.
- Assignment keys: Delivery Partner and Deployment Specialist (synced fields) are the authoritative keys for assignment and are used to derive project membership.
- Defense in depth: Client UI reflects permissions but enforcement occurs in backend policies outlined in [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md).

10. Integrations and sync overview
- Source import: Client spreadsheet rows flow via Power Automate to a secure API endpoint which stages records and triggers a merge into canonical projects.
- Identity: Authentication uses Okta OIDC to establish a Supabase session; see [docs/okta-oidc-supabase.md](docs/okta-oidc-supabase.md).
- Assignment materialization: The Delivery Partner and Deployment Specialist fields from the import drive project membership updates so that:
  - Delivery partner users see only their organization’s assigned projects.
  - Telco deployment specialists see only projects assigned to them.
- Storage: Attachments are uploaded to a private storage bucket; reads and writes are authorized via attachment metadata and membership.
- Extensibility: The data model separates imported fields from user generated content for clean integration, audit, and reporting.

Mermaid overview
```mermaid
flowchart LR
  A[Client spreadsheet] --> B[Power Automate]
  B --> C[Staging area]
  C --> D[Merge into projects]
  D --> E[Materialize membership]
  E --> F[Role-aware projects list]
  F --> G[User generated content]
  G --> H[Attachments storage]
```

11. Reporting and analytics considerations
- Separation of concerns enables straightforward BI models that join canonical projects with user generated contacts, engagements, and attachments without collision.
- Use Stage Application (Application Number) as the stable key for cross system joins and historical reporting.
- Engage dimensions for Delivery Partner and Deployment Specialist for ownership and performance reporting.
- Include EFSCD in schedule adherence reporting and timeline visuals.
- Include Overall Project Status as a reporting dimension for schedule adherence. Status is recomputed on each import; if historical trending is required, persist the computed status per import snapshot in the reporting layer.
- Ensure timestamps are captured in UTC with tenant local rendering at the app layer.

12. UX principles and guidelines
- Mobile first: Optimize for quick capture of engagements and attachments in the field.
- Clarity: Clearly label imported fields as read only and highlight user editable areas.
- Minimal friction: One tap to add an engagement or attachment from project detail.
- Traceability: Show last import time and source for master data to build trust.
- Location presentation: Link-only to external maps using latitude/longitude in MVP; no inline map preview.
- Deep linking: Support deep link navigation to Project Detail by Stage Application for share actions and QA.

13. Non functional requirements
- Performance: Median two second load for lists and detail at target scale.
- Reliability: Imports succeed reliably with idempotent upserts; app gracefully handles partial failures.
- Security and privacy: Role based visibility and storage access control for attachments; tenant isolation by default.
- Scalability: Support growing tenants and additional integrations without schema redesign.
- Attachments: Accept any file type; maximum 25 MB per file; clear validation errors presented on exceed.

14. Risks and mitigations
- Incorrect joins during import could duplicate or overwrite data. Mitigation: Stage Application per tenant and idempotent merge with audit.
- Over permissive access could expose projects. Mitigation: Enforce membership checks on all project scoped reads and writes, with periodic policy tests.
- Attachment exposure if storage rules are misconfigured. Mitigation: Private bucket with access mediated by metadata and membership checks.
- Data drift between spreadsheet and app. Mitigation: Clear ownership, read only flags in UI, and regular import cadence with alerts on anomalies.

15. Open questions to resolve in detailed design
- Confirm UI exposure subset of spreadsheet-synced fields per role.
- Mapping approach: How are Delivery Partner (org names) and Deployment Specialist (people) mapped to user accounts and partner organizations for membership materialization?
- Assignment exceptions: How to handle projects temporarily reassigned across delivery partners or between deployment specialists?
- Residential, Commercial, Essential semantics: confirm whether each is an integer count or a boolean flag to ensure accurate UI representation.
- Allowed file types (if any restrictions beyond max size) and multi-file selection limits for attachments.
- Timeline representation and whether milestones should be editable by PMs in app.
- Requirements for audit trail visibility in the UI.

16. Milestones and rollout plan
- M1 Read only visibility: Projects list and detail pulling imported attributes; role based scoping; deep linking enabled.
- M2 Collaboration: Contacts and engagements creation and viewing by authorized users.
- M3 Evidence: Attachments upload and preview with storage controls.
- M4 Assignment automation: Membership materialization from Delivery Partner and Deployment Specialist fields.
- M5 Reporting readiness: Validate data completeness and add basic exports if needed.
- Feature flags: Ability to enable Projects and Attachments modules per tenant for gradual rollout.

17. Dependencies
- Identity and session handling as described in [docs/okta-oidc-supabase.md](docs/okta-oidc-supabase.md).
- Role and policy baseline as described in [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md).
- Technical architecture details and suggested APIs in [docs/projects-feature.md](docs/projects-feature.md).

18. Acceptance criteria summary
- Delivery partners only see assigned projects and can add contacts, engagements, and attachments on those projects.
- Deployment specialists only see their assigned projects (as indicated by the synced Deployment Specialist field and materialized membership).
- Relationship managers only see projects assigned to them (as indicated by the synced Relationship Manager field and materialized membership); they can create user-generated content on those projects.
- Imported fields are read only for delivery partners and cannot be modified through the app.
- User generated content is never overwritten by imports and remains associated to its project.
- Attachments are only accessible to authorized members and are stored in a private bucket.
- Deep link to a Stage Application navigates to the correct Project Detail.
- Overall Project Status is computed per section 8.3 using a Monday–Friday business-day calendar (no public holidays in MVP).
- Status dynamically recomputes on import; EFSCD changes can transition a project between Overdue and not Overdue with no sticky states.
- Filters include Overall Project Status; multi-select returns projects matching any selected status values.
- Late App classification is derived as Stage Application Created less than 70 business days before EFSCD.
- PCC waiver is applied for Late Apps: PCC achieved within 20 business days of Issued to Delivery Partner; if Issued to Delivery Partner is missing, the standard rule applies (PCC at least 20 business days before EFSCD).
- Display rules: When Delivery Partner is blank, the UI shows Not Yet Assigned; Developer Class values are normalized (Class 1=Key Strategic, Class 2=Managed, Class 3/4=Inbound).

19. Change log
- v0.6 Added assignment normalization and UI rules: Delivery Partner blank → Not Yet Assigned (no ORG membership); Developer Class normalization Class 1=Key Strategic, Class 2=Managed, Class 3/4=Inbound; added Relationship Manager role as assigned-only and included in membership materialization.
- v0.5 Added Overall Project Status derived field and rules (Late App, PCC waiver, business-day assumptions, dynamic recomputation on EFSCD changes). Extended filters, reporting, and acceptance criteria accordingly.
- v0.4 Added clarifications: DS vs Relationship Manager presentation (Overview emphasizes Relationship Manager; DS appears in header and cards), declared date-like fields for Delivery Partner PC Sub and In Service, added EFSCD as a milestone and filterable/sortable date, specified attachment constraints (any file type, max 25 MB per file), location is link-only (no mini map), renamed longtitude to longitude, added deep linking approval and default sorting guidance (see UI spec).
- v0.3 Clarified assignment and tenancy model: Delivery Partner and Deployment Specialist are authoritative assignment keys used to derive membership and visibility; telco as main tenant owning canonical projects; delivery partner tenants gain scoped access via membership.
- v0.2 Defined unique identifier as Stage Application (Application Number; 14 chars, starts with STG-). Added the exact list of spreadsheet-synced fields and noted that not all will appear in the UI.
- v0.1 Initial high level PRD draft created.