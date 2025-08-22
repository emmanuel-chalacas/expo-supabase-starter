// @ts-nocheck
/* eslint-disable */
/**
 * Omnivia — Stage 4 Import Edge Function
 * HTTPS POST endpoint to ingest Projects import batches, persist to staging_imports,
 * and invoke merge membership materialization via RPC.
 *
 * Auth: Authorization: Bearer PROJECTS_IMPORT_BEARER
 * Env:  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PROJECTS_IMPORT_BEARER
 *
 * References:
 * - Migration + RPC: [sql.fn_projects_import_merge(text,text,text,jsonb,uuid)](../../migrations/20250817231500_stage4_import.sql:1)
 * - Contract: [docs/product/projects-import-contract.md](../../../docs/product/projects-import-contract.md:1)
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

type Json = Record<string, unknown>;
type Row = Record<string, unknown>;

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB
const ROWS_MIN = 1;
const ROWS_MAX = 5000;

const REQUIRED_TOP_LEVEL_KEYS = ['tenant_id', 'source', 'batch_id', 'rows'] as const;
/**
 * Stage 6 ROW_KEYS ordering:
 * - Mirrors SQL helper ordering in [supabase/migrations/20250817231500_stage4_import.sql](supabase/migrations/20250817231500_stage4_import.sql:243)
 * - Inserted suburb,state immediately after address (address group)
 * - Inserted practical_completion_notified immediately before practical_completion_certified (milestone group)
 * - Removed deprecated fields: development_type, rm_preferred_username
 * Keeping importer and SQL in sync until Task 4 replaces the SQL helper.
 */
const ROW_KEYS = [
  'stage_application',
  'address',
  'suburb',
  'state',
  'eFscd',
  'build_type',
  'delivery_partner',
  'fod_id',
  'premises_count',
  'residential',
  'commercial',
  'essential',
  'developer_class',
  'latitude',
  'longitude',
  'relationship_manager',
  'deployment_specialist',
  'stage_application_created',
  'developer_design_submitted',
  'developer_design_accepted',
  'issued_to_delivery_partner',
  'practical_completion_notified',
  'practical_completion_certified',
  'delivery_partner_pc_sub',
  'in_service',
] as const;

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8' };

const env = (globalThis as any).Deno?.env ?? { get: (_: string) => undefined };

// Critical item 4 — Lightweight, in-memory rate limiting and backpressure
// Module-scope best-effort state. No external dependencies. Per-instance only.
const RATE_RPS = Number.parseFloat(env.get('IMPORT_RATE_LIMIT_RPS') || '') || 1;
const BURST = Number.parseInt(env.get('IMPORT_RATE_LIMIT_BURST') || '', 10) || 5;
const GLOBAL_CONCURRENCY = Number.parseInt(env.get('IMPORT_GLOBAL_CONCURRENCY') || '', 10) || 6;
const TENANT_CONCURRENCY = Number.parseInt(env.get('IMPORT_TENANT_CONCURRENCY') || '', 10) || 2;
const WINDOW_MS = Number.parseInt(env.get('IMPORT_WINDOW_MS') || '', 10) || 1000;

type Bucket = { tokens: number; lastRefill: number };
const buckets = new Map<string, Bucket>();
let globalInFlight = 0;
const tenantInFlight = new Map<string, number>();

function nowMs(): number { return Date.now(); }

function refillAndGetBucket(tenant: string, now = nowMs()): Bucket {
  let b = buckets.get(tenant);
  if (!b) {
    b = { tokens: BURST, lastRefill: now };
    buckets.set(tenant, b);
    return b;
  }
  const elapsed = now - b.lastRefill;
  if (elapsed > 0) {
    // Token-bucket refill at RATE_RPS tokens/sec with capacity BURST
    const add = (elapsed / 1000) * RATE_RPS;
    b.tokens = Math.min(BURST, b.tokens + add);
    b.lastRefill = now;
  }
  return b;
}

function consumeTokenOrDelay(tenant: string): { allowed: boolean; retryAfterMs: number } {
  const b = refillAndGetBucket(tenant);
  if (b.tokens >= 1) {
    b.tokens -= 1;
    return { allowed: true, retryAfterMs: 0 };
  }
  const deficit = 1 - b.tokens;
  const ms = Math.ceil((deficit / (RATE_RPS || 1)) * 1000);
  // Ensure a minimal wait; WINDOW_MS can be used as a coarse window hint
  const retry = Math.max(ms, Math.min(WINDOW_MS, 1000));
  return { allowed: false, retryAfterMs: retry };
}

function resolveTenantKeyFromBody(body: any): string {
  try {
    const candidates = ['tenant_id', 'tenantId', 'tenant', 'partner_org_id', 'org_id'];
    for (const k of candidates) {
      const v = body?.[k];
      if (typeof v === 'string') {
        const s = v.trim();
        if (s) return s;
      }
    }
  } catch {
    // ignore
  }
  return 'global';
}

function estimateConcurrencyRetryMs(): number {
  // Guiding value: ~1 second at 1 rps; clients should still apply exponential backoff with jitter.
  return Math.max(500, Math.ceil(1000 / (RATE_RPS || 1)));
}

function rateLimitResponse(tenant: string, retryAfterMs: number): Response {
  const headers = { ...jsonHeaders, 'Retry-After': String(Math.max(1, Math.ceil(retryAfterMs / 1000))) };
  return new Response(JSON.stringify({ error: 'rate_limited', tenant, retry_after_ms: retryAfterMs }), {
    status: 429,
    headers,
  });
}

/*
Verification notes (manual), per Critical item 4:
- Send >5 requests within ~1s for the same tenant → expect 429 with Retry-After and retry_after_ms.
- Send >2 concurrent requests for the same tenant → expect 429.
- Send >6 concurrent mixed-tenant requests → expect 429.
- After waiting at least Retry-After, a subsequent request should succeed.
Caveat: In-memory state is per-instance and resets on cold start or scale events (best-effort guard).
*/

function isUuid(v: string | null | undefined): v is string {
  return !!v && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/.test(v);
}

function trimStr(v: unknown): string {
  return typeof v === 'string' ? v.trim() : (v == null ? '' : String(v).trim());
}

function toIntOrZero(v: unknown): number {
  const s = trimStr(v);
  if (!s) return 0;
  const n = Number.parseInt(s, 10);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

function toFloatOrNull(v: unknown): number | null {
  const s = trimStr(v);
  if (!s) return null;
  const n = Number.parseFloat(s);
  return Number.isFinite(n) ? n : null;
}

/**
 * String normalization to nullable: trim; blanks -> null
 * Spec ref: Strings in Task 3 — address, suburb, state, build_type, fod_id, relationship_manager, deployment_specialist
 *   [docs/product/projects-data-field-inventory.md](../../../docs/product/projects-data-field-inventory.md:468)
 */
function toNullableTrim(v: unknown): string | null {
  const s = trimStr(v);
  return s ? s : null;
}

/**
 * Parse to ISO date (YYYY-MM-DD), discarding timezone info if present.
 * Strategy:
 *  - Prefer a direct YYYY[-/.]MM[-/.]DD capture from the input string (no timezone conversion)
 *  - Fallback to Date parsing and format as UTC YYYY-MM-DD
 * Spec ref: practical_completion_notified normalization in Task 3
 *   [docs/product/projects-data-field-inventory.md](../../../docs/product/projects-data-field-inventory.md:468)
 */
function toIsoDateOrNull(v: unknown): string | null {
  const s = trimStr(v);
  if (!s) return null;
  // Prefer direct capture to avoid TZ shifts (e.g., '2025-08-20T00:30:00+10:00' -> '2025-08-20')
  const m = s.match(/^(\d{4})[-\/.](\d{2})[-\/.](\d{2})/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 10);
}

function normalizeRow(input: Row): Row {
  /**
   * Stage 6 normalization (Task 3):
   * - Integers: premises_count, residential, commercial, essential -> non-negative ints; blanks/invalid -> 0
   * - Floats: latitude, longitude -> float; blanks/invalid -> null
   * - Strings (trim; blanks -> null): address, suburb, state, build_type, fod_id, relationship_manager, deployment_specialist
   * - Date: practical_completion_notified -> ISO 'YYYY-MM-DD' (timezone info discarded); blanks/invalid -> null
   * - Deprecated: development_type, rm_preferred_username omitted from payload and checksum
   * Spec anchors:
   *   - Keys/order & checksum: [supabase/migrations/20250817231500_stage4_import.sql](../../migrations/20250817231500_stage4_import.sql:243)
   *   - Normalization bullets: [docs/product/projects-data-field-inventory.md](../../../docs/product/projects-data-field-inventory.md:468)
   */
  const out: Row = {};
  for (const k of ROW_KEYS) {
    switch (k) {
      // Integers
      case 'premises_count':
      case 'residential':
      case 'commercial':
      case 'essential':
        out[k] = toIntOrZero(input[k]);
        break;

      // Floats
      case 'latitude':
      case 'longitude':
        out[k] = toFloatOrNull(input[k]);
        break;

      // Date: normalize to YYYY-MM-DD
      case 'practical_completion_notified':
        out[k] = toIsoDateOrNull(input[k]);
        break;

      // Strings with blanks -> null
      case 'address':
      case 'suburb':
      case 'state':
      case 'build_type':
      case 'fod_id':
      case 'relationship_manager':
      case 'deployment_specialist':
        out[k] = toNullableTrim(input[k]);
        break;

      // Default: trim to string (keeps prior behavior for keys like stage_application, eFscd, developer_class, etc.)
      default:
        out[k] = trimStr(input[k]);
        break;
    }
  }
  return out;
}

function stableChecksumString(rows: Row[]): string {
  // Deterministic: sort by stage_application asc; stable key order; normalized values
  const sorted = [...rows].sort((a, b) => {
    const ak = String(a.stage_application ?? '');
    const bk = String(b.stage_application ?? '');
    return ak.localeCompare(bk);
  });
  const parts: string[] = [];
  for (const r of sorted) {
    const kv = ROW_KEYS.map((k) => {
      const v = (r as any)[k];
      return `${k}=${v == null ? '' : String(v)}`;
    }).join('|');
    parts.push(kv);
  }
  // Join with \n to delineate rows
  return parts.join('\n');
}

async function sha256Hex(s: string): Promise<string> {
  const data = new TextEncoder().encode(s);
  const digest = await crypto.subtle.digest('SHA-256', data);
  const bytes = new Uint8Array(digest);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function error(status: number, message: string, extra?: Record<string, unknown>): Response {
  return new Response(JSON.stringify({ error: message, ...extra ?? {} }), { status, headers: jsonHeaders });
}

function ok(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function pick<T extends Record<string, any>>(obj: T, keys: readonly string[]): Partial<T> {
  const out: Partial<T> = {};
  for (const k of keys) out[k as keyof T] = obj[k as keyof T];
  return out;
}

async function handlePost(req: Request): Promise<Response> {
  // Auth
  const auth = req.headers.get('authorization') || '';
  const expectedBearer = env.get('PROJECTS_IMPORT_BEARER') || '';
  if (!expectedBearer) {
    return error(500, 'Server misconfigured: missing PROJECTS_IMPORT_BEARER');
  }
  if (!auth.startsWith('Bearer ')) {
    return error(401, 'Missing bearer token');
  }
  const presented = auth.substring('Bearer '.length).trim();
  if (presented !== expectedBearer) {
    return error(401, 'Invalid bearer token');
  }

  // Critical item 4: lightweight throttle — check global concurrency up front
  if (globalInFlight >= GLOBAL_CONCURRENCY) {
    return rateLimitResponse('global', estimateConcurrencyRetryMs());
  }
  globalInFlight++;

  let tenantKey = 'global';
  let tenantConcurrencyAcquired = false;

  try {
    // Size checks
    const clHeader = req.headers.get('content-length');
    if (clHeader) {
      const cl = Number.parseInt(clHeader, 10);
      if (Number.isFinite(cl) && cl > MAX_BYTES) {
        return error(413, 'Payload too large (gt 5 MB)');
      }
    }

    // Parse JSON body with an additional size guard
    const buf = await req.arrayBuffer();
    if (buf.byteLength > MAX_BYTES) {
      return error(413, 'Payload too large (gt 5 MB)');
    }

    let body: any;
    try {
      body = JSON.parse(new TextDecoder().decode(buf));
    } catch {
      return error(400, 'Malformed JSON');
    }

    // Top-level validation
    if (typeof body !== 'object' || body === null) {
      return error(400, 'Body must be a JSON object');
    }
    for (const k of REQUIRED_TOP_LEVEL_KEYS) {
      if (!(k in body)) return error(422, `Missing required field: ${k}`);
    }
    const tenant_id = trimStr(body.tenant_id);
    const source = trimStr(body.source);
    const batch_id_raw = trimStr(body.batch_id);
    const correlation_id_raw = trimStr(body.correlation_id || '');
    if (!tenant_id) return error(422, 'tenant_id must be a non-empty string');
    if (!source) return error(422, 'source must be a non-empty string');

    // Rate limiting — resolve tenant key and enforce per-tenant caps
    tenantKey = resolveTenantKeyFromBody(body) || tenant_id;

    // Per-tenant concurrency cap
    const inFlightForTenant = tenantInFlight.get(tenantKey) || 0;
    if (inFlightForTenant >= TENANT_CONCURRENCY) {
      return rateLimitResponse(tenantKey, estimateConcurrencyRetryMs());
    }
    tenantInFlight.set(tenantKey, inFlightForTenant + 1);
    tenantConcurrencyAcquired = true;

    // Per-tenant token-bucket (1 rps default, burst 5)
    const tokenCheck = consumeTokenOrDelay(tenantKey);
    if (!tokenCheck.allowed) {
      return rateLimitResponse(tenantKey, tokenCheck.retryAfterMs);
    }

    const rowsInput = Array.isArray(body.rows) ? body.rows : null;
    if (!rowsInput) return error(422, 'rows must be an array');
    if (rowsInput.length < ROWS_MIN || rowsInput.length > ROWS_MAX) {
      return error(422, `rows length must be between ${ROWS_MIN} and ${ROWS_MAX}`);
    }

    // Normalize rows (trim strings; coerce numeric counts; keep optional blanks as empty strings)
    const normalizedRows: Row[] = rowsInput.map((r: Row) => normalizeRow(r));

    // Deterministic checksum
    const checksum = await sha256Hex(stableChecksumString(normalizedRows));

    // Assign correlation_id
    const correlation_id = isUuid(correlation_id_raw) ? correlation_id_raw : crypto.randomUUID();

    // Prepare batch_id (UUID). If not UUID, generate and memoize original in validation
    const batch_id_uuid = isUuid(batch_id_raw) ? batch_id_raw : crypto.randomUUID();
    const validation: Json = isUuid(batch_id_raw) ? {} : { request_batch_id: batch_id_raw };

    // Supabase client (service role)
    const supabaseUrl = env.get('SUPABASE_URL') || '';
    const supabaseKey = env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!supabaseUrl || !supabaseKey) {
      return error(500, 'Server misconfigured: missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
    }
    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { 'X-Client-Info': 'omnivia-imports/1.0' } },
    });

    // Insert staging record (idempotent on tenant_id + batch_checksum)
    const stagingPayload = {
      tenant_id,
      batch_id: batch_id_uuid,
      raw: normalizedRows,
      batch_checksum: checksum,
      checksum, // legacy NOT NULL compatibility
      source,
      row_count: normalizedRows.length,
      correlation_id,
      validation,
    };

    // Try insert with onConflict do nothing
    {
      const { error: insErr } = await supabase
        .from('staging_imports')
        .upsert(stagingPayload as any, { onConflict: 'tenant_id,batch_checksum', ignoreDuplicates: true });if (insErr && insErr.code !== 'P0001') {
        // PostgREST emits conflict differently in some versions; ignore duplicates explicitly above
        // Any other error is fatal
        return error(500, 'Failed to insert staging_imports', {
          correlation_id,
          reason: insErr.message || String(insErr),
        });
      }
    }

    // Fetch the staging row id (for response parity, RPC will also return it)
    const { data: stagingRow, error: selErr } = await supabase
      .from('staging_imports')
      .select('id')
      .eq('tenant_id', tenant_id)
      .eq('batch_checksum', checksum)
      .order('imported_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (selErr || !stagingRow) {
      return error(500, 'Failed to resolve staging_imports row', {
        correlation_id,
        reason: selErr?.message || 'not found',
      });
    }

    // Invoke merge RPC (transaction lives inside the function)
    const { data: mergeRes, error: rpcErr } = await supabase.rpc('fn_projects_import_merge', {
      p_tenant_id: tenant_id,
      p_source: source,
      p_batch_id: batch_id_uuid,
      p_rows: normalizedRows as any,
      p_correlation_id: correlation_id,
    });

    if (rpcErr) {
      return error(500, 'Merge failed', {
        correlation_id,
        reason: rpcErr.message || String(rpcErr),
      });
    }

    // mergeRes is of composite type projects_import_merge_result
    const metrics = {
      inserted_projects: (mergeRes as any)?.inserted_projects ?? 0,
      updated_projects: (mergeRes as any)?.updated_projects ?? 0,
      org_memberships_upserted: (mergeRes as any)?.org_memberships_upserted ?? 0,
      user_memberships_upserted: (mergeRes as any)?.user_memberships_upserted ?? 0,
      anomalies_count: (mergeRes as any)?.anomalies_count ?? 0,
      staging_id: (mergeRes as any)?.staging_id ?? stagingRow.id,
    };

    return ok({
      batch_id: batch_id_uuid,
      correlation_id,
      tenant_id,
      metrics,
    });
  } finally {
    // Ensure in-flight counters are decremented even on early returns or errors
    if (tenantConcurrencyAcquired) {
      const cur = (tenantInFlight.get(tenantKey) || 1) - 1;
      if (cur <= 0) tenantInFlight.delete(tenantKey);
      else tenantInFlight.set(tenantKey, cur);
    }
    globalInFlight = Math.max(0, globalInFlight - 1);
  }
}

async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', {
      status: 405,
      headers: { allow: 'POST' },
    });
  }
  try {
    return await handlePost(req);
  } catch (err: any) {
    // Best-effort correlation_id echo if present in body
    let correlation_id: string | undefined;
    try {
      const j = await req.clone().json();
      if (j && typeof j.correlation_id === 'string') correlation_id = j.correlation_id;
    } catch {
      // ignore
    }
    return error(500, 'Unhandled error', {
      correlation_id,
      reason: err?.message || String(err),
    });
  }
}

// Deno and edge runtime entrypoint
const denoServe = (globalThis as any).Deno?.serve;
if (typeof denoServe === 'function') {
  (denoServe as any)((req: Request) => handler(req));
} else {
  // Fallback for local emulation
  addEventListener('fetch', (event: any) => {
    event.respondWith(handler(event.request));
  });
}
// Named export for tracker anchor and potential reuse
export async function handleImportProjects(req: Request): Promise<Response> {
  return await (handler as any)(req);
}