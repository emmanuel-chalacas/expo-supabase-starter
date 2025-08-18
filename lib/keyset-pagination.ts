/**
 * Keyset pagination helper for Projects list.
 *
 * Always orders by:
 *   1) stage_application ASC
 *   2) stage_application_created DESC
 *   3) id DESC
 *
 * Note: For complex values and/or additional filters, the recommended production
 * approach is a server RPC-based list endpoint that encapsulates the keyset
 * predicate in SQL. This helper is intentionally conservative and provides a
 * client-only starting point.
 */

export type ProjectsCursor = { stage_application: string; created_at: string; id: string };

// Base64URL helpers with environment fallbacks (browser/Node/React Native)
function base64UrlEncode(input: string): string {
  // Try global btoa first (browser/Expo)
  if (typeof (globalThis as any).btoa === 'function') {
    const b64 = (globalThis as any).btoa(input);
    return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }
  // Fallback to Buffer (Node)
  if (typeof (globalThis as any).Buffer !== 'undefined') {
    const b64 = (globalThis as any).Buffer.from(input, 'utf8').toString('base64');
    return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }
  throw new Error('No base64 encoder available in this environment');
}

function base64UrlDecode(input: string): string {
  const b64 = input.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(input.length / 4) * 4, '=');
  if (typeof (globalThis as any).atob === 'function') {
    return (globalThis as any).atob(b64);
  }
  if (typeof (globalThis as any).Buffer !== 'undefined') {
    return (globalThis as any).Buffer.from(b64, 'base64').toString('utf8');
  }
  throw new Error('No base64 decoder available in this environment');
}

export function encodeProjectsCursor(cursor: ProjectsCursor): string {
  return base64UrlEncode(JSON.stringify(cursor));
}

export function decodeProjectsCursor(s: string): ProjectsCursor {
  const raw = base64UrlDecode(s);
  let obj: any;
  try {
    obj = JSON.parse(raw);
  } catch {
    throw new Error('Invalid cursor: not valid JSON');
  }
  if (
    !obj ||
    typeof obj.stage_application !== 'string' ||
    typeof obj.created_at !== 'string' ||
    typeof obj.id !== 'string'
  ) {
    throw new Error('Invalid cursor: expected { stage_application, created_at, id } as strings');
  }
  return { stage_application: obj.stage_application, created_at: obj.created_at, id: obj.id };
}

// PostgREST filter value quoting for special characters.
// If a value contains characters that conflict with PostgREST's operator grammar
// (comma, parentheses, quotes, whitespace), we wrap it in double quotes and
// escape internal quotes by doubling them, e.g. foo"bar -> "foo""bar".
// This is conservative; values with other edge cases may still require a server RPC.
function quoteForPostgrestValue(v: string): string {
  const needsQuotes = /[(),\s"]/g.test(v);
  if (!needsQuotes) return v;
  return `"${v.replace(/"/g, '""')}"`;
}

/**
 * Build a PostgREST or-filter expression that encodes the lexicographic triple:
 *   stage_application ASC, stage_application_created DESC, id DESC
 *
 * Equivalent logical form for rows strictly after the cursor:
 *   stage_application > :sa
 *   OR (stage_application = :sa AND stage_application_created < :created)
 *   OR (stage_application = :sa AND stage_application_created = :created AND id < :id)
 */
export function buildProjectsOrFilter(cursor: ProjectsCursor): string {
  const sa = quoteForPostgrestValue(cursor.stage_application);
  const created = quoteForPostgrestValue(cursor.created_at);
  const id = quoteForPostgrestValue(cursor.id);

  // Using PostgREST expression grammar for .or():
  // - Comma between top-level terms is OR
  // - and(a,b,...) groups AND terms
  const term1 = `stage_application.gt.${sa}`;
  const term2 = `and(stage_application.eq.${sa},stage_application_created.lt.${created})`;
  const term3 = `and(stage_application.eq.${sa},stage_application_created.eq.${created},id.lt.${id})`;
  return [term1, term2, term3].join(',');
}

/**
 * Apply Projects keyset ordering and predicate (when provided) to a Supabase builder.
 * The builder is expected to be the result of supabase.from('projects').select(...)
 */
export function applyProjectsKeyset(builder: any, pageSize: number, cursor?: ProjectsCursor): any {
  let q = builder
    .order('stage_application', { ascending: true, nullsFirst: false })
    .order('stage_application_created', { ascending: false, nullsFirst: false })
    .order('id', { ascending: false, nullsFirst: false })
    .limit(pageSize);

  if (cursor) {
    q = q.or(buildProjectsOrFilter(cursor));
  }
  return q;
}

// Example (not executed):
// const next = applyProjectsKeyset(
//   supabase.from('projects').select('id,stage_application,stage_application_created'),
//   50,
//   { stage_application: 'apply', created_at: '2025-08-18T04:00:00Z', id: '123' }
// );
// console.log(next.url);