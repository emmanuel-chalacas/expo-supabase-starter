// @ts-nocheck
/* eslint-disable */
/**
 * Omnivia — Auth Health Edge Function (High priority item 7)
 *
 * Purpose:
 *  - Lightweight runtime health probe to validate Okta issuer reachability and provider parity.
 *  - Non-destructive, network-only; does NOT initiate any OAuth flow.
 *
 * Usage:
 *  - Deploy as a Supabase Edge Function at GET /functions/v1/auth-health
 *  - Configure Function Secrets (per environment):
 *      - OKTA_ISSUER (required) — same as EXPO_PUBLIC_OKTA_ISSUER
 *      - EXPECTED_PROVIDER (optional) — 'oidc' or 'okta'
 *      - SUPABASE_OIDC_PROVIDER (optional) — 'oidc' or 'okta'
 *      - OKTA_END_SESSION_REDIRECT (optional) — informational only
 *
 * CI/Tracker References:
 *  - Audit: [docs/product/projects-okta-rbac-stage1-4-audit.md](../../../docs/product/projects-okta-rbac-stage1-4-audit.md:1)
 *  - Tracker: [docs/product/projects-okta-rbac-implementation-tracker.md](../../../docs/product/projects-okta-rbac-implementation-tracker.md:1)
 */

type Json = Record<string, unknown>;

const env = (globalThis as any).Deno?.env ?? { get: (_: string) => undefined };
const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8' };

function ok(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function err(status: number, message: string, extra?: Json): Response {
  return ok({ ok: false, error: message, ...(extra ?? {}) }, status);
}

function normalizeIssuer(u: string): string {
  return String(u || '').trim().replace(/\/+$/, '');
}

function isValidProviderValue(p: string): boolean {
  const s = String(p || '').trim().toLowerCase();
  return s === 'oidc' || s === 'okta';
}

async function fetchWithTimeout(url: string, ms: number): Promise<Response> {
  const ctrl = new AbortController();
  const id = setTimeout(() => ctrl.abort(), Math.max(1, ms | 0));
  try {
    return await fetch(url, { signal: ctrl.signal });
  } finally {
    clearTimeout(id);
  }
}

async function handleGet(_req: Request): Promise<Response> {
  const issuerRaw = env.get('OKTA_ISSUER') || '';
  if (!issuerRaw) return err(503, 'missing_issuer');

  const expectedProvider = (env.get('EXPECTED_PROVIDER') || '').trim() || null;
  const configuredProvider = (env.get('SUPABASE_OIDC_PROVIDER') || '').trim() || null;

  if (expectedProvider && configuredProvider) {
    const ep = expectedProvider.toLowerCase();
    const cp = configuredProvider.toLowerCase();
    // Enforce equality ('oidc' or 'okta')
    if (!(isValidProviderValue(ep) && isValidProviderValue(cp) && ep === cp)) {
      return err(503, 'provider_parity_failed', { expected: ep, configured: cp });
    }
  }

  const issuer = normalizeIssuer(issuerRaw);
  const discoveryUrl = `${issuer}/.well-known/openid-configuration`;

  let resp: Response;
  try {
    resp = await fetchWithTimeout(discoveryUrl, 5000);
  } catch (e: any) {
    return err(503, 'discovery_fetch_failed', { reason: e?.message || String(e) });
  }

  if (!resp.ok) {
    return err(503, 'discovery_http_error', { status: resp.status });
  }

  let j: any;
  try {
    j = await resp.json();
  } catch (e: any) {
    return err(503, 'discovery_parse_error', { reason: e?.message || String(e) });
  }

  const jsonIssuer = normalizeIssuer(j?.issuer || '');
  if (!jsonIssuer || jsonIssuer !== issuer) {
    return err(503, 'issuer_mismatch', { issuer, discovered: jsonIssuer || null });
  }
  if (!j?.authorization_endpoint) {
    return err(503, 'authorization_endpoint_missing');
  }
  if (!j?.jwks_uri) {
    return err(503, 'jwks_uri_missing');
  }

  const hasEndSession = Boolean(j?.end_session_endpoint);
  const providerOut = configuredProvider || expectedProvider || null;

  return ok(
    {
      ok: true,
      issuer,
      provider: providerOut,
      hasEndSession: hasEndSession,
    },
    200
  );
}

async function handler(req: Request): Promise<Response> {
  if (req.method === 'GET') {
    return handleGet(req);
  }
  return new Response('Method Not Allowed', {
    status: 405,
    headers: { allow: 'GET' },
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

/* Named export for anchors */
export async function handleAuthHealth(req: Request): Promise<Response> {
  return handler(req);
}