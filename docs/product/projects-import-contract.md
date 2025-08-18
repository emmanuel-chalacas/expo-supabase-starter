# Projects Import Contract — CSV over HTTPS

Author: Kilo Code
Status: Draft v0.1
Date: 2025-08-16
References: [docs/product/projects-feature-prd.md](docs/product/projects-feature-prd.md:1), [docs/product/projects-feature-implementation-plan.md](docs/product/projects-feature-implementation-plan.md:1), [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:1)

1. Purpose
- Define a stable CSV contract for the Projects import used by Power Automate.
- Ensure large files up to 5000 rows import reliably with idempotent merge and clear error reporting.
- Normalize key fields (Developer Class, Delivery Partner) and support unassigned Delivery Partner.

2. Transport and security
- Protocol: HTTPS POST to a per-tenant endpoint (Supabase Edge Function/fronted handler), e.g. /imports/projects/telco
- Auth: Authorization: Bearer <per-tenant secret> (stored in a secure connection reference)
- Content types supported
  - Preferred: text/csv; charset=utf-8
  - Optional JSON: application/json (array of row objects) for tenants that prefer pre-parsed payloads
- Compression: Content-Encoding: gzip supported for text/csv
- Size guidance
  - Up to 5000 data rows per file
  - CSV payload typically <= 5–10 MB uncompressed; recommend gzip if available
- Idempotency: Idempotent merge keyed by Stage Application (scoped to the primary Telco tenant); repeated rows with same values will no-op; updates apply to whitelisted fields only

3. File format — CSV
- Encoding: UTF-8 (BOM tolerated but not required)
- Delimiter: Comma
- Header row: Required; must contain exactly the headers below (case-insensitive match; additional columns ignored)
- Quoting: Standard RFC4180; values may be quoted; embedded quotes escaped by double quotes
- Newlines: \r\n (Windows) or \n (Unix) accepted

4. Header list and field definitions
- stage_application
  - Type: string (14 chars, starts with STG-), required, unique key within Telco tenant
  - Trim whitespace; must match canonical key from PRD
- address
  - Type: string, required
- eFscd
  - Label: Expected First Service Connection Date (EFSCD)
  - Type: date (YYYY-MM-DD) or datetime (ISO 8601); normalized to date with timezone neutral handling
- development_type
  - Allowed: Residential, Commercial, Mixed Use (case-insensitive)
- build_type
  - Allowed: SDU, MDU, HMDU, MCU (case-insensitive)
- delivery_partner
  - Type: string; can be blank to denote Unassigned; normalization to canonical partner_org via partner_normalization
  - Allowed canonical labels include: Fulton Hogan, Ventia, UGL, Enerven, Servicestream; blank allowed
- fod_id
  - Type: string (optional)
- premises_count
  - Type: integer (>= 0), optional
- residential
  - Type: integer (>= 0), optional
- commercial
  - Type: integer (>= 0), optional
- essential
  - Type: integer (>= 0), optional
- developer_class
  - Source codes: Class 1, Class 2, Class 3, Class 4
  - Normalization:
    - Class 1 → Key Strategic
    - Class 2 → Managed
    - Class 3 → Inbound
    - Class 4 → Inbound
- latitude
  - Type: decimal (+/- 90), optional
- longitude
  - Type: decimal (+/- 180), optional
- relationship_manager
  - Type: string identifier from source; mapped via rm_directory to Okta user id
- deployment_specialist
  - Type: string identifier from source; mapped via ds_directory to Okta user id
- stage_application_created
  - Type: date (YYYY-MM-DD) or datetime (ISO 8601)
- developer_design_submitted
  - Type: date/datetime
- developer_design_accepted
  - Type: date/datetime
- issued_to_delivery_partner
  - Type: date/datetime
- practical_completion_certified
  - Type: date/datetime
- delivery_partner_pc_sub
  - Type: date/datetime
- in_service
  - Type: date/datetime

Notes
- Case-insensitivity for headers and code values (Developer Class, Delivery Partner labels) is applied; whitespace is trimmed for all textual fields.
- Additional columns are ignored but will be reported back as warnings to aid cleanup.

5. Sample CSV (first rows)
```
stage_application,address,eFscd,development_type,build_type,delivery_partner,fod_id,premises_count,residential,commercial,essential,developer_class,latitude,longitude,relationship_manager,deployment_specialist,stage_application_created,developer_design_submitted,developer_design_accepted,issued_to_delivery_partner,practical_completion_certified,delivery_partner_pc_sub,in_service
STG-000000000001,12 Main St,2025-10-01,Residential,SDU,UGL,FOD-123,50,45,5,0,Class 1,-34.9285,138.6007,RM_JSMITH,DS_AJONES,2025-04-01,2025-04-10,2025-04-15,2025-05-01,2025-08-15,2025-08-01,2025-09-28
STG-000000000002,34 Park Ave,2025-11-15,Commercial,MDU,,FOD-124,100,0,100,0,Class 3,,,RM_JDOE,DS_BLEE,2025-05-01,2025-05-12,2025-05-20,,2025-10-20,, 
```

6. Server-side normalization and validation
- Normalizations
  - developer_class: Class 1/2/3/4 → Key Strategic/Managed/Inbound (3/4)
  - delivery_partner: map via partner_normalization; blank → Unassigned (no ORG membership)
  - Trim and uppercase stage_application check; trim name-like identifiers for mapping tables
- Validations
  - stage_application required and format enforced (STG- prefix and length)
  - Dates parsed with strict ISO 8601; if time present, converted to date for date-only fields
  - Integers validated non-negative
  - Unknown development_type/build_type values rejected with per-row error
- Mapping
  - ds_directory: deployment_specialist → Okta user id; unknown values produce anomaly
  - rm_directory: relationship_manager → Okta user id; unknown values produce anomaly
  - partner_normalization: delivery_partner → partner_org id; blank allowed; unknown non-blank label produces anomaly

7. Response schema (HTTP 200 for partial success with per-row errors)
- application/json
```
{
  "batch_id": "2025-08-16T02:30:00Z-tenant-abc-001",
  "tenant_id": "TELCO",
  "counts": {
    "received_rows": 5000,
    "inserted": 1200,
    "updated": 3800,
    "rejected": 10,
    "membership_upserts": 4100
  },
  "metrics": {
    "bytes_processed": 7340032,
    "parse_ms": 820,
    "merge_ms": 1420
  },
  "errors": [
    {
      "row_number": 42,
      "stage_application": "STG-000000000042",
      "code": "UNKNOWN_DELIVERY_PARTNER",
      "message": "Delivery Partner label did not normalize to a canonical partner_org",
      "field": "delivery_partner",
      "value": "Fulton-Hogan??"
    },
    {
      "row_number": 77,
      "stage_application": "STG-000000000077",
      "code": "INVALID_DATE",
      "message": "Invalid date format for EFSCD",
      "field": "eFscd",
      "value": "15/11/2025"
    }
  ]
}
```
- HTTP status codes
  - 200: Request accepted; see counts and per-row errors
  - 400: Request invalid (e.g., missing header row, malformed CSV)
  - 401/403: Auth failure
  - 413: Payload too large (advise chunking or gzip)
  - 429/5xx: Backoff and retry per flow policy

8. Operational guidance (Power Automate)
- Preferred pattern: Upload the CSV as text/csv (gzip if available) directly to the import endpoint (Pattern B). Avoid per-row HTTP calls.
- Chunking (if using JSON Pattern A): Split into chunks of up to ~1000 rows or ~2–3 MB payloads; send sequentially; aggregate responses.
- Logging in Flow: Capture response counts and errors array; persist to a SharePoint list or Dataverse table for audit.
- Retries: Use exponential backoff on non-2xx; do not retry 400-class validation errors without correction.
- Time window: Schedule daily at 17:00 local time; optionally allow manual triggers for catch-up.

9. Membership materialization and visibility (summary)
- Delivery Partner = blank → Unassigned: no ORG membership created; UI displays Delivery Partner as Not Yet Assigned
- Delivery Partner label → partner_org via partner_normalization → ORG membership
- Deployment Specialist → ds_directory → USER membership
- Relationship Manager → rm_directory → USER membership
- See enforcement templates in [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:130)

10. Versioning and change control
- Changes to headers or field semantics require a minor version bump and an advance notice period.
- This contract is referenced by:
  - [docs/product/projects-feature-implementation-plan.md](docs/product/projects-feature-implementation-plan.md:22) Power Automate integration and Stage 0 deliverables
  - [docs/product/projects-feature-prd.md](docs/product/projects-feature-prd.md:106) Data ownership and Integrations
  - [docs/security/rbac-rls-review.md](docs/security/rbac-rls-review.md:111) Assignment and mapping rules

11. Rate limiting and backoff
- Purpose: protect downstream database and RPCs against bursts while preserving throughput under normal load.
- Signal: HTTP 429 indicates temporary backpressure. Treat as retryable.
- Response details on 429
  - Headers: Retry-After: integer seconds (ceil of server guidance)
  - Body (application/json):
    {
      "error": "rate_limited",
      "tenant": "&lt;resolved-tenant&gt;",
      "retry_after_ms": &lt;milliseconds&gt;
    }
  - Both Retry-After and retry_after_ms represent the minimum time to wait before retrying the same request. Clients should use the max of server guidance and their local backoff calculation.

- Default thresholds (subject to change via deployment configuration)
  - Per-tenant rate: 1 request per second (RPS), with a small burst allowance of 5.
  - Per-tenant concurrent requests: 2.
  - Global concurrent requests across all tenants: 6.
  - These values may be tuned operationally without notice; clients must implement adaptive backoff using server signals.

- Backoff strategy (recommended)
  - Exponential backoff with full jitter.
  - Initial randomized delay: 500–1500 ms.
  - Double the base after each retry; clamp to a maximum of 60 seconds.
  - Respect Retry-After header (seconds) and retry_after_ms (milliseconds) — wait at least that long.
  - Give up after N attempts (for example, 6–8) or a maximum elapsed time of 5 minutes, whichever comes first.
  - Do not retry 4xx validation errors other than 429.

- Pseudocode (language-agnostic)
  ```
  attempt = 0
  start = now()
  baseMin = 500     // ms
  baseMax = 1500    // ms
  maxDelay = 60_000 // ms
  maxElapsed = 300_000 // ms (5 minutes)

  while true:
    resp = POST(importEndpoint, payload, headers)

    if resp.status == 200:
      return resp

    retryAfterMs = 0
    if resp.status == 429:
      // Prefer body hint if present, else header (seconds → ms)
      retryAfterMs = resp.json?.retry_after_ms or secondsToMs(resp.headers["Retry-After"])
    else if resp.status in [500, 502, 503, 504]:
      // transient server errors: backoff without server hint
      retryAfterMs = 0
    else:
      // Non-retryable client errors (e.g., 400/401/413/422)
      raise resp

    // Exponential backoff with jitter
    jitter = rand(baseMin, baseMax)
    backoff = min(maxDelay, (2 ** attempt) * jitter)

    waitMs = max(retryAfterMs or 0, backoff)

    if (now() - start + waitMs) > maxElapsed or attempt >= 8:
      raise "Import retry window exceeded"

    sleep(waitMs)
    attempt += 1
  ```
Change log
- v0.1 Initial CSV contract with header list, normalization rules, sample, response schema, and operational guidance.