# Supabase Imports Runbook — Projects Import (Stage 4)

Owner: Backend/Ops
Last updated: 2025-08-18

Purpose
- Operate and support the Projects import pipeline implemented in Stage 4.
- Provide scheduling, throttling, retry, logging, and anomaly remediation guidance for operators.
- Reference authoritative contract and endpoints.

Authoritative references
- Import contract: [docs/product/projects-import-contract.md](../product/projects-import-contract.md:1)
- Edge Function (endpoint): [supabase/functions/import-projects/index.ts](../../supabase/functions/import-projects/index.ts:1)
- Merge RPC and schema: [supabase/migrations/20250817231500_stage4_import.sql](../../supabase/migrations/20250817231500_stage4_import.sql:1)
- Verification: [docs/sql/stage4-verify.sql](../sql/stage4-verify.sql:1)
- Smoke tests: [docs/sql/stage4-smoke-tests.sql](../sql/stage4-smoke-tests.sql:1)

Secrets and deployment
- Function secrets (set in Supabase Dashboard → Functions → import-projects):
  - PROJECTS_IMPORT_BEARER: per-tenant Bearer secret for HTTPS POST authorization
  - SUPABASE_SERVICE_ROLE_KEY: service role key used by the function to call the RPC and write to staging
- Never commit real secrets to the repo. Configure these as Supabase Function Secrets; no placeholders are kept in the repository.
- Typical deployment (CLI):
  - supabase functions deploy import-projects
  - supabase functions secrets set PROJECTS_IMPORT_BEARER=... SUPABASE_SERVICE_ROLE_KEY=...

Endpoint and payload
- HTTPS POST to the Edge Function route configured by Supabase (e.g., https://<project-ref>.functions.supabase.co/import-projects).
- Headers:
  - Authorization: Bearer PROJECTS_IMPORT_BEARER
  - Content-Type: application/json
- Size limits:
  - Max 5 MB body (hard limit)
  - Up to 5000 rows per request (contract limit)
- Payload schema (JSON):
  {
    "tenant_id": "TELCO",
    "source": "projects-import",
    "batch_id": "2025-08-18T17:00:00+0930-batch-001",
    "correlation_id": "7f2a7eed-7b46-49ef-9f77-2a0c6a6ad001",  // optional; generated if omitted
    "rows": [
      {
        "stage_application": "STG-000000000001",
        "delivery_partner": "Fulton Hogan",
        "developer_class": "Class 2",
        "relationship_manager": "First Last",
        "deployment_specialist": "PREFERRED_USERNAME",
        "residential": "45",
        "commercial": "5",
        "essential": "",
        "stage_application_created": "2025-04-01"
      }
      // ...
    ]
  }
- Normalization performed by the function:
  - Trims all strings; numeric counts (residential/commercial/essential/premises_count) blank → 0.
  - Deterministic checksum computed by sorting rows by stage_application and hashing a stable key string.

Idempotency and staging
- Each POST persists a staging row in public.staging_imports with:
  - batch_id (UUID; generated from provided batch_id if not a UUID; original string is memoized in validation.request_batch_id),
  - tenant_id, raw (jsonb), batch_checksum, source, row_count, correlation_id.
- Uniqueness: (tenant_id, batch_checksum) enforced; duplicate batches are ignored safely.
- Merge RPC public.fn_projects_import_merge(tenant_id, source, batch_id, rows jsonb, correlation_id uuid) executes idempotently within a transaction and memoizes metrics under staging_imports.validation->metrics for short-circuit on replays.

Scheduling and rate limits
- Recommended schedule: daily at 17:00 local time for each tenant.
- Concurrency: 1 request per tenant (serial).
- Throttling and retries (exponential backoff):
  - Initial delay 1s, then 2s, 4s, 8s, 16s; stop after 5 total attempts.
  - Do not retry on 4xx validations (400/401/413/422) without operator correction.
  - Retry on transient 429/5xx.

Status codes and handling
- 200: Accepted. The response contains metrics for inserts/updates/memberships/anomalies and staging_id.
- 400: Malformed JSON or invalid structure; correct the flow payload.
- 401: Missing/invalid bearer; verify connection reference and function secrets.
- 413: Payload too large; reduce rows or compress (if using CSV in alternatives).
- 422: Contract violations (types, lengths, row count out-of-bounds); correct data.
- 500: Server error (details include correlation_id). Retry with backoff; escalate if persistent.

Response schema (success)
{
  "batch_id": "<uuid>",
  "correlation_id": "<uuid>",
  "tenant_id": "TELCO",
  "metrics": {
    "inserted_projects": 1200,
    "updated_projects": 3800,
    "org_memberships_upserted": 1200,
    "user_memberships_upserted": 2400,
    "anomalies_count": 10,
    "staging_id": "<uuid>"
  }
}

Logging, tracing, and dashboards
- Correlation:
  - correlation_id propagates from request (or is generated) through staging_imports and anomalies. Include it in logs and incident tickets.
- Metrics to capture:
  - rows received, inserted, updated, org_memberships_upserted, user_memberships_upserted, anomalies_count, latency (parse/merge), bytes processed.
- Retention:
  - Retain Edge logs for ~365 days (cold storage at 90 days). No PII or token contents in logs.
- Dashboards:
  - Create panels for success rate, anomalies by type, membership changes per batch, and latency.

Anomalies and remediation workflow
- Anomalies table: public.import_anomalies records issues per row with anomaly_type:
  - UNKNOWN_DELIVERY_PARTNER when delivery_partner non-blank does not normalize via partner_normalization.
  - UNKNOWN_DS when deployment_specialist does not match an active ds_directory.preferred_username.
  - UNKNOWN_RM when relationship_manager (display_name) or rm_preferred_username does not match active rm_directory.
- Stewardship SLAs:
  - Telco Admin acknowledges within 4 business hours; resolves within 1 business day.
- Remediation steps:
  1. Review anomalies by batch_id and anomaly_type.
  2. Update partner_normalization (for DP) or directories (ds_directory/rm_directory).
  3. Re-run import (same dataset) or execute membership backfill:
     - Yarn helper: yarn db:run:backfill:memberships
     - SQL: select public.fn_projects_membership_backfill();

Operational checklists
- Pre-deployment:
  - Secrets set: PROJECTS_IMPORT_BEARER, SUPABASE_SERVICE_ROLE_KEY.
  - CI passed: Stage 4 verification and smoke tests.
- Post-deployment:
  - Send a small test batch (2–3 rows) to confirm:
    - 200 response and metrics populated,
    - Projects upserted; memberships visible,
    - Anomalies recorded for expected misses.
  - Enable the scheduled flow (1 rps) at 17:00 tenant local time.

Common issues
- 401 Unauthorized: Confirm bearer secret matches the Function secret; verify header "Authorization: Bearer <secret>".
- 413 Payload too large: Split batch into chunks (<=5000 rows and 5 MB).
- 422 Rows out of bounds: Ensure 1..5000 rows; enforce numeric counts non-negative.
- Unknown DP/DS/RM anomalies persist: Update normalization/directories; re-run import or run the backfill function to materialize memberships from canonical fields.

Change control
- Any changes to header semantics or field mappings require a minor contract version and advance notice to operators.
- Maintain idempotency: do not change primary keys or checksum composition without coordinating both function and RPC changes.
## Anomalies stewardship — Critical item 5

Purpose
- Surface import anomalies to operators with protected access, provide lightweight alerting hooks, and document stewardship workflow.

Access
- In-app dashboard (protected): [app/(protected)/anomalies.tsx](../app/(protected)/anomalies.tsx:1)
  - Route: /(protected)/anomalies (Expo Router)
  - Shows last 24h stats and up to 100 most-recent anomalies grouped by severity
  - Privacy: displays payload_excerpt (first 500 chars of the specific row only), never full raw payload
- Edge Function (read anomalies)
  - GET https://&lt;project-ref&gt;.functions.supabase.co/anomalies
  - Query params:
    - windowHours (int, default 24)
    - tenant (string, optional)
    - severity (comma-list error,warning,info; optional)
    - stats=true (if present/true, returns aggregated stats)
  - Auth: Authorization: Bearer &lt;user JWT&gt; (forwarded to Supabase; RLS + role checks apply)
  - Source: [supabase/functions/anomalies/index.ts](../../supabase/functions/anomalies/index.ts:1)
- Edge Function (alerts)
  - POST https://&lt;project-ref&gt;.functions.supabase.co/anomalies/alerts
  - No body required
  - Behavior: Computes last-N-hours stats server-side; if total >= threshold, posts an aggregate JSON to configured webhook (never includes raw payloads)
  - Source: [supabase/functions/anomalies/index.ts](../../supabase/functions/anomalies/index.ts:1)

Database views and RPCs
- Recent-window view (14 days): public.vw_import_anomalies_recent
- 24h stats view: public.vw_import_anomalies_stats_24h
- Secure RPCs (operator/admin only):
  - public.fn_anomalies_for_operator(p_window_hours int default 24, p_tenant text default null, p_severity text[] default null)
  - public.fn_anomalies_stats(p_window_hours int default 24)
- Migration: [supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql](../../supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql:1)

Function secrets and knobs (set in Supabase Dashboard → Functions → anomalies)
- Required for GET route:
  - SUPABASE_URL
  - SUPABASE_ANON_KEY
- Required for POST /alerts:
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE_KEY
- Alert configuration (optional; no secrets committed):
  - ANOMALIES_ALERT_WEBHOOK: HTTPS endpoint to receive aggregate payloads (e.g., https://httpbin.org/post for testing)
  - ANOMALIES_ALERT_WINDOW_HOURS: integer, default 1
  - ANOMALIES_ALERT_MIN_COUNT: integer, default 1

Triage workflow
1) Classify and assess
   - Review last 24h stats in the dashboard and scan recent anomalies.
   - Common categories:
     - UNKNOWN_DELIVERY_PARTNER (warning)
     - UNKNOWN_DS (error)
     - UNKNOWN_RM (error)
2) Correlate to batch and context
   - Use tenant_id, batch_id, row_index, project_key, and correlation_id to locate the source batch in staging_imports.
3) Remediate
   - Delivery Partner: update partner_normalization with canonical mapping.
   - DS: update ds_directory preferred_username mapping.
   - RM: update rm_directory display_name or preferred_username mapping per policy.
4) Re-run or reconcile
   - Re-run the same import batch (idempotent) once mappings are corrected, or
   - Execute membership backfill:
     - SQL: select public.fn_projects_membership_backfill();
     - Yarn helper (if configured): db:run:backfill:memberships
5) Quarantine (if needed)
   - If dataset remains problematic, pause the upstream job and open an incident with correlation_id references.

Escalation and on-call thresholds (examples)
- Alert when anomalies_count in the last hour ≥ 5 total or ≥ 2 errors (UNKNOWN_DS/UNKNOWN_RM)
- Escalate to Vendor Admin on repeated spikes (&gt;= 3 consecutive alert windows) or if DS/RM mapping failures exceed 10 for a tenant in 24h
- On-call rotation per Ops schedule; annotate tickets with correlation_id and batch_id

Privacy and safety
- Do not log raw payloads or PII/token contents.
- UI and GET endpoint only expose payload_excerpt (truncated 500 chars).
- POST /alerts sends counts and categories only; no raw samples.

Verification (manual)
- DB / RPC:
  - As operator/admin: select * from public.fn_anomalies_for_operator(24, null, null) limit 5;
  - As non-operator: expect ERROR: insufficient_privilege
  - Stats windowing: validate totals change with p_window_hours
- Edge function:
  - GET with valid user Authorization: 200 JSON rows; with stats=true returns aggregated rows
  - GET without Authorization: 401
  - POST /alerts with no webhook configured: 204
  - POST /alerts with ANOMALIES_ALERT_WEBHOOK=https://httpbin.org/post and ANOMALIES_ALERT_MIN_COUNT=1: 202; verify receipt in httpbin
- UI:
  - Signed-in operator sees stats and list (most recent 100); non-operator sees Access denied message
## Retention &amp; cleanup — High priority item 9

Summary
- Daily pg_cron job runs at 03:10 UTC to delete old staging/anomaly rows after aggregating counts into [public.import_retention_stats](../../supabase/migrations/20250818043000_stage5_imports_retention.sql:1).
- Defaults (from [sql.fn_cleanup_import_data()](../../supabase/migrations/20250818043000_stage5_imports_retention.sql:1)):
  - staging_imports: 60 days
  - import_anomalies: 90 days
  - schedule: daily at 03:10 UTC (jobname: imports-anomalies-retention)

Override schedule and/or retention
- Rescheduling is done by unscheduling the existing job and creating a new entry. Examples:
  - Change only the time to 02:15 UTC:
    ```sql
    -- Unschedule existing job
    select cron.unschedule(jobid)
    from cron.job
    where jobname = 'imports-anomalies-retention';

    -- Reschedule at 02:15 UTC using defaults (60d, 90d)
    select cron.schedule(
      'imports-anomalies-retention',
      '15 2 * * *',
      'select public.fn_cleanup_import_data();'
    );
    ```
  - Change both schedule and retention (e.g., imports=45d, anomalies=75d):
    ```sql
    -- Unschedule existing job
    select cron.unschedule(jobid)
    from cron.job
    where jobname = 'imports-anomalies-retention';

    -- Reschedule at 02:15 UTC with overrides
    select cron.schedule(
      'imports-anomalies-retention',
      '15 2 * * *',
      'select public.fn_cleanup_import_data(45, 75);'
    );
    ```
- Manual run in a safe (ephemeral) environment only:
  ```sql
  -- DANGER: deletes all rows immediately when using 0,0
  select public.fn_cleanup_import_data(0, 0);
  ```

Observability
- Aggregated retention counters are stored by day in [public.import_retention_stats](../../supabase/migrations/20250818043000_stage5_imports_retention.sql:1) (stat_date is the date key).
  ```sql
  select *
  from public.import_retention_stats
  order by stat_date desc
  limit 14;
  ```
- Verification queries:
  - See [docs/sql/stage5-retention-verify.sql](../sql/stage5-retention-verify.sql:1) to confirm pg_cron installation, scheduled job presence, preview deletion candidates, and recent stats.