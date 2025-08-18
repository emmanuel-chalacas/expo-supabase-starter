// @ts-nocheck
/* eslint-disable */
/**
 * Omnivia — Anomalies Edge Function (Critical item 5)
 * Routes:
 *  - GET  /functions/v1/anomalies
 *      Query params:
 *        - windowHours: int (default 24)
 *        - tenant: string (optional)
 *        - severity: comma-list of error|warning|info (optional)
 *        - stats: boolean (if true, returns stats instead of raw rows)
 *      Behavior:
 *        - Reads Authorization (user JWT) and forwards it to Supabase client (anon key) so RLS/auth applies.
 *        - Invokes public.fn_anomalies_for_operator(...) or public.fn_anomalies_stats(...).
 *  - POST /functions/v1/anomalies/alerts
 *      Env (Function Secrets):
 *        - ANOMALIES_ALERT_WEBHOOK: URL (optional)
 *        - ANOMALIES_ALERT_WINDOW_HOURS: int (default 1)
 *        - ANOMALIES_ALERT_MIN_COUNT: int (default 1)
 *      Behavior:
 *        - Computes last-N-hours stats server-side (service role) without exposing raw payloads.
 *        - If total >= threshold and webhook configured, POSTs { window_hours, total, by_severity, by_category, generated_at }.
 *
 * Safety:
 *  - No committed secrets; only env lookups via Deno.env.get.
 *  - Minimal logs; never log user data or secrets.
 *  - Returns 401/403 for unauthorized calls; 200 with JSON for success; alerts endpoint 204 when no-op.
 *
 * Verification (manual), Critical item 5:
 *  - GET with valid operator JWT:
 *      curl -H "Authorization: Bearer <user_jwt>" "<functions-url>/anomalies?windowHours=24"
 *      curl -H "Authorization: Bearer <user_jwt>" "<functions-url>/anomalies?stats=true&windowHours=24"
 *    Expect 200 JSON. With non-operator, expect 403 from RPC.
 *  - GET without Authorization: expect 401.
 *  - POST /alerts with no webhook configured: expect 204.
 *  - POST /alerts with webhook set (e.g., https://httpbin.org/post) and >= threshold: expect 202 and webhook receives payload.
 */

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

type Json = Record<string, unknown>;

type AnomalyRow = {
  id: string;
  created_at: string;
  tenant_id: string;
  staging_id: string;
  batch_id: string;
  row_index: number;
  anomaly_type: string;
  field: string;
  input_value: string | null;
  reason: string;
  match_type: string | null;
  project_key: string | null;
  correlation_id: string;
  source: string | null;
  payload_excerpt: string | null;
  severity: 'error' | 'warning' | 'info';
};

type StatRow = {
  tenant_id: string;
  category: string;
  severity: 'error' | 'warning' | 'info';
  count: number;
  most_recent: string;
};

const env = (globalThis as any).Deno?.env ?? { get: (_: string) => undefined };

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8' };

/* Utilities */

function ok(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function error(status: number, message: string, extra?: Record<string, unknown>): Response {
  return new Response(JSON.stringify({ error: message, ...(extra ?? {}) }), {
    status,
    headers: jsonHeaders,
  });
}

function toIntOrDefault(v: string | null, d: number): number {
  if (!v) return d;
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? n : d;
}

function parseBool(v: string | null): boolean {
  const s = (v || '').trim().toLowerCase();
  return s === '1' || s === 'true' || s === 'yes';
}

function parseSeverityList(v: string | null): Array<'error' | 'warning' | 'info'> | null {
  if (!v) return null;
  const parts = v
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean) as Array<'error' | 'warning' | 'info'>;
  const allowed = new Set(['error', 'warning', 'info']);
  const filtered = parts.filter((p) => allowed.has(p));
  return filtered.length ? (filtered as Array<'error' | 'warning' | 'info'>) : null;
}

/* Supabase clients */

function getAnonClientWithUserAuth(authHeader: string | null): SupabaseClient {
  const supabaseUrl = env.get('SUPABASE_URL') || '';
  const anonKey = env.get('SUPABASE_ANON_KEY') || '';
  if (!supabaseUrl || !anonKey) {
    throw new Error('Server misconfigured: missing SUPABASE_URL or SUPABASE_ANON_KEY');
  }
  return createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      headers: {
        ...(authHeader ? { Authorization: authHeader } : {}),
        'X-Client-Info': 'omnivia-anomalies/1.0',
      },
    },
  });
}

function getServiceClient(): SupabaseClient {
  const supabaseUrl = env.get('SUPABASE_URL') || '';
  const serviceKey = env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!supabaseUrl || !serviceKey) {
    throw new Error('Server misconfigured: missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  }
  return createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { 'X-Client-Info': 'omnivia-anomalies/1.0' } },
  });
}

/* Handlers */

async function handleGet(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const authHeader = req.headers.get('authorization');
  if (!authHeader) return error(401, 'Missing Authorization header');

  const windowHours = toIntOrDefault(url.searchParams.get('windowHours'), 24);
  const tenant = (url.searchParams.get('tenant') || '').trim() || null;
  const severityList = parseSeverityList(url.searchParams.get('severity'));
  const wantStats = parseBool(url.searchParams.get('stats'));

  let supabase: SupabaseClient;
  try {
    supabase = getAnonClientWithUserAuth(authHeader);
  } catch {
    return error(500, 'Server misconfigured');
  }

  if (wantStats) {
    const { data, error: rpcErr } = await supabase.rpc('fn_anomalies_stats', {
      p_window_hours: windowHours,
    });
    if (rpcErr) {
      const msg = (rpcErr as any)?.message || String(rpcErr);
      if (/insufficient_privilege/i.test(msg)) return error(403, 'Forbidden');
      return error(500, 'RPC error (stats)', { reason: msg });
    }
    return ok({ window_hours: windowHours, stats: (data || []) as StatRow[] });
  }

  const { data, error: rpcErr } = await supabase.rpc('fn_anomalies_for_operator', {
    p_window_hours: windowHours,
    p_tenant: tenant,
    p_severity: severityList,
  });

  if (rpcErr) {
    const msg = (rpcErr as any)?.message || String(rpcErr);
    if (/insufficient_privilege/i.test(msg)) return error(403, 'Forbidden');
    return error(500, 'RPC error (rows)', { reason: msg });
  }

  const rows = (Array.isArray(data) ? data : []) as AnomalyRow[];
  return ok({ window_hours: windowHours, count: rows.length, rows });
}

function severityForType(anomalyType: string): 'error' | 'warning' | 'info' {
  switch (anomalyType) {
    case 'UNKNOWN_DS':
    case 'UNKNOWN_RM':
      return 'error';
    case 'UNKNOWN_DELIVERY_PARTNER':
      return 'warning';
    default:
      return 'info';
  }
}

async function handlePostAlerts(_req: Request): Promise<Response> {
  const hookUrl = env.get('ANOMALIES_ALERT_WEBHOOK') || '';
  const windowHours = Number.isFinite(Number.parseInt(env.get('ANOMALIES_ALERT_WINDOW_HOURS') || '', 10))
    ? Number.parseInt(env.get('ANOMALIES_ALERT_WINDOW_HOURS') || '1', 10)
    : 1;
  const minCount = Number.isFinite(Number.parseInt(env.get('ANOMALIES_ALERT_MIN_COUNT') || '', 10))
    ? Number.parseInt(env.get('ANOMALIES_ALERT_MIN_COUNT') || '1', 10)
    : 1;

  // If no webhook configured, no-op
  if (!hookUrl) return new Response(null, { status: 204 });

  let supabase: SupabaseClient;
  try {
    supabase = getServiceClient();
  } catch {
    // Treat as configuration error; but and avoid leaking details
    return error(500, 'Server misconfigured');
  }

  // Compute window ISO timestamp
  const since = new Date(Date.now() - windowHours * 60 * 60 * 1000).toISOString();

  // Fetch minimal fields; aggregate in-memory (no raw payloads)
  const { data, error: selErr } = await supabase
    .from('import_anomalies')
    .select('tenant_id, anomaly_type, created_at')
    .gte('created_at', since);

  if (selErr) {
    return error(500, 'Query failed', { reason: selErr.message || String(selErr) });
  }

  type Totals = {
    total: number;
    bySeverity: Record<'error' | 'warning' | 'info', number>;
    byCategory: Record<string, number>;
  };

  const totals: Totals = {
    total: 0,
    bySeverity: { error: 0, warning: 0, info: 0 },
    byCategory: {},
  };

  for (const r of data || []) {
    const sev = severityForType((r as any).anomaly_type || '');
    totals.total += 1;
    totals.bySeverity[sev] += 1;
    const cat = String((r as any).anomaly_type || 'UNKNOWN');
    totals.byCategory[cat] = (totals.byCategory[cat] || 0) + 1;
  }

  if (totals.total < Math.max(0, minCount)) {
    return ok({ window_hours: windowHours, total: totals.total, delivered: false }, 200);
  }

  const payload = {
    window_hours: windowHours,
    total: totals.total,
    by_severity: totals.bySeverity,
    by_category: totals.byCategory,
    generated_at: new Date().toISOString(),
  };

  // POST to webhook (no secrets; minimal headers)
  try {
    const resp = await fetch(hookUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });
    // Return acceptance regardless of remote status to avoid leaking details
    return ok({ delivered: true, status: resp.status }, 202);
  } catch {
    // Network error — do not leak details; return 202 (best-effort)
    return ok({ delivered: false, status: 0 }, 202);
  }
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  if (req.method === 'GET') {
    return handleGet(req);
  }

  if (req.method === 'POST' && /\/anomalies\/alerts\/?$/.test(path)) {
    return handlePostAlerts(req);
  }

  return new Response('Method Not Allowed', {
    status: 405,
    headers: { allow: 'GET, POST' },
  });
}

/* Deno/Edge entrypoint */
const denoServe = (globalThis as any).Deno?.serve;
if (typeof denoServe === 'function') {
  (denoServe as any)((req: Request) => handler(req));
} else {
  addEventListener('fetch', (event: any) => {
    event.respondWith(handler(event.request));
  });
}

// Named export for tracking anchors
export async function handleAnomalies(req: Request): Promise<Response> {
  return handler(req);
}