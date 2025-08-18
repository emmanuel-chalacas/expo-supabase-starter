// @ts-nocheck
/* eslint-disable */
/**
 * Omnivia — Storage Preview (High priority item 10)
 *
 * Route:
 *  - GET /functions/v1/storage-preview?bucket=&path=&redirect=true|false&disposition=inline|attachment
 *
 * Behavior:
 *  - Requires Authorization: Bearer <user_jwt>.
 *  - Performs a user-scoped probe by fetching the first 8 KiB via Range from Storage:
 *      ${SUPABASE_URL}/storage/v1/object/${bucket}/${path}
 *    with headers: Authorization (user JWT), apikey (SUPABASE_ANON_KEY), Range: bytes=0-8191.
 *  - If probe status != 200/206 → 403 { ok:false, error:'forbidden' }.
 *  - Sniffs header bytes with [typescript.detectMimeFromHeader()](supabase/functions/storage-preview/index.ts:1)
 *    allowing only: image/png, image/jpeg, image/gif, image/webp, application/pdf.
 *    SVG is NOT allowed by default; set ALLOW_SVG=true to optionally allow image/svg+xml
 *    only when the first non-whitespace characters are exactly "<svg".
 *  - On allowed types → create 60s signed URL via service-role and either:
 *      - 302 Location: <signed_url> (default when redirect=true)
 *      - 200 JSON { ok:true, url, mime, expiresIn:60 } (when redirect=false)
 *  - On disallowed types → 415 { ok:false, error:'unsupported_mime', detected:'...' }.
 *
 * Required Function Secrets:
 *  - SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
 *  - ALLOW_SVG (optional, default false)
 *
 * Notes:
 *  - Import style and serve pattern align with [supabase/functions/anomalies/index.ts](supabase/functions/anomalies/index.ts:1).
 *  - This implements Tracker High Priority 10 per [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md:1).
 */

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const env = (globalThis as any).Deno?.env ?? { get: (_: string) => undefined };

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8' };

function ok(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function error(status: number, message: string, extra?: Record<string, unknown>): Response {
  return new Response(JSON.stringify({ ok: false, error: message, ...(extra ?? {}) }), {
    status,
    headers: jsonHeaders,
  });
}

function parseBool(v: string | null): boolean {
  const s = (v || '').trim().toLowerCase();
  return s === '1' || s === 'true' || s === 'yes';
}

function basename(p: string): string {
  if (!p) return 'file';
  const i = p.lastIndexOf('/');
  return i >= 0 ? p.slice(i + 1) : p;
}

function getServiceClient(): SupabaseClient {
  const supabaseUrl = env.get('SUPABASE_URL') || '';
  const serviceKey = env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!supabaseUrl || !serviceKey) {
    throw new Error('Server misconfigured: missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  }
  return createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { 'X-Client-Info': 'omnivia-storage-preview/1.0' } },
  });
}

function u8eq(a: Uint8Array, b: number[], offset = 0): boolean {
  if (a.length < offset + b.length) return false;
  for (let i = 0; i < b.length; i++) if (a[offset + i] !== b[i]) return false;
  return true;
}

function asciiAt(u8: Uint8Array, offset: number, text: string): boolean {
  if (u8.length < offset + text.length) return false;
  for (let i = 0; i < text.length; i++) if (u8[offset + i] !== text.charCodeAt(i)) return false;
  return true;
}

export function detectMimeFromHeader(bytes: Uint8Array, allowSvg: boolean): string | null {
  if (!bytes || !bytes.length) return null;
  // PNG
  if (u8eq(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0)) return 'image/png';
  // JPEG
  if (u8eq(bytes, [0xff, 0xd8, 0xff], 0)) return 'image/jpeg';
  // GIF87a / GIF89a
  if (asciiAt(bytes, 0, 'GIF87a') || asciiAt(bytes, 0, 'GIF89a')) return 'image/gif';
  // WEBP (RIFF....WEBP)
  if (asciiAt(bytes, 0, 'RIFF') && asciiAt(bytes, 8, 'WEBP')) return 'image/webp';
  // PDF
  if (asciiAt(bytes, 0, '%PDF-')) return 'application/pdf';
  // Optional SVG (strict): first non-whitespace must be "<svg"
  if (allowSvg) {
    const dec = new TextDecoder('utf-8', { fatal: false });
    const head = dec.decode(bytes.slice(0, Math.min(bytes.length, 2048)));
    const s = head.replace(/^\uFEFF?/, '').trimStart();
    if (s.startsWith('<svg')) return 'image/svg+xml';
  }
  return null;
}

async function userScopedProbe(
  authHeader: string,
  bucket: string,
  path: string
): Promise<Uint8Array | null> {
  const supabaseUrl = env.get('SUPABASE_URL') || '';
  const anonKey = env.get('SUPABASE_ANON_KEY') || '';
  if (!supabaseUrl || !anonKey) {
    throw new Error('Server misconfigured: missing SUPABASE_URL or SUPABASE_ANON_KEY');
  }
  const encodedPath = path
    .split('/')
    .map((seg) => encodeURIComponent(seg))
    .join('/');
  const url = `${supabaseUrl}/storage/v1/object/${encodeURIComponent(bucket)}/${encodedPath}`;
  const resp = await fetch(url, {
    method: 'GET',
    headers: {
      Authorization: authHeader,
      apikey: anonKey,
      Range: 'bytes=0-8191',
    },
  });
  if (resp.status !== 200 && resp.status !== 206) return null;
  const buf = new Uint8Array(await resp.arrayBuffer());
  return buf;
}

async function handleGet(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const authHeader = req.headers.get('authorization');
  if (!authHeader) return error(401, 'unauthorized');

  const bucket = (url.searchParams.get('bucket') || '').trim();
  const path = (url.searchParams.get('path') || '').trim();
  if (!bucket || !path) return error(400, 'missing_params', { required: ['bucket', 'path'] });

  const redirect = parseBool(url.searchParams.get('redirect') ?? 'true');
  const dispositionRaw = (url.searchParams.get('disposition') || 'inline').toLowerCase();
  const disposition = dispositionRaw === 'attachment' ? 'attachment' : 'inline';

  let probeBytes: Uint8Array | null = null;
  try {
    probeBytes = await userScopedProbe(authHeader, bucket, path);
  } catch {
    return error(500, 'server_misconfigured');
  }
  if (!probeBytes) return error(403, 'forbidden');

  const allowSvg = parseBool(env.get('ALLOW_SVG') || '');
  const detected = detectMimeFromHeader(probeBytes, allowSvg);
  const allowed = new Set([
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'application/pdf',
    ...(allowSvg ? (['image/svg+xml'] as string[]) : []),
  ]);
  if (!detected || !allowed.has(detected)) {
    return error(415, 'unsupported_mime', { detected: detected || 'unknown' });
  }

  let supabase: SupabaseClient;
  try {
    supabase = getServiceClient();
  } catch {
    return error(500, 'server_misconfigured');
  }

  const { data, error: signErr } = await supabase.storage
    .from(bucket)
    .createSignedUrl(path, 60, {
      download: disposition === 'attachment' ? basename(path) : undefined,
    });

  if (signErr || !data || !data.signedUrl) {
    return error(500, 'signing_failed');
  }

  if (redirect) {
    return new Response(null, {
      status: 302,
      headers: { Location: data.signedUrl },
    });
  }

  return ok({ ok: true, url: data.signedUrl, mime: detected, expiresIn: 60 }, 200);
}

async function handler(req: Request): Promise<Response> {
  if (req.method !== 'GET') {
    return new Response('Method Not Allowed', {
      status: 405,
      headers: { allow: 'GET' },
    });
  }
  return handleGet(req);
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
export async function handleStoragePreview(req: Request): Promise<Response> {
  return handler(req);
}