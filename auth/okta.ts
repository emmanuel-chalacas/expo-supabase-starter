import * as AuthSession from "expo-auth-session";

// Ensure the in-app browser closes on redirect back to the app (if available)
const _maybeComplete = (AuthSession as any).maybeCompleteAuthSession as
	| undefined
	| (() => void);
if (typeof _maybeComplete === "function") _maybeComplete();

// Deep link configuration
const scheme = "omnivia";
const redirectPath = "oauthredirect";

// Read required environment variables (throws when missing)
function getEnv(name: string): string {
	const value = process.env?.[name];
	if (!value) throw new Error(`Missing required environment variable: ${name}`);
	return value;
}

export function getRedirectUri(): string {
	return AuthSession.makeRedirectUri({ scheme, path: redirectPath });
}

export async function getOktaDiscovery(): Promise<AuthSession.DiscoveryDocument> {
	const issuer = getEnv("EXPO_PUBLIC_OKTA_ISSUER");
	return AuthSession.fetchDiscoveryAsync(issuer);
}

export interface OktaAuthResult {
	idToken: string;
	accessToken?: string;
	discovery: AuthSession.DiscoveryDocument;
	redirectUri: string;
	nonce?: string;
}

export async function oktaAuthorize(): Promise<OktaAuthResult> {
	const issuer = getEnv("EXPO_PUBLIC_OKTA_ISSUER");
	const clientId = getEnv("EXPO_PUBLIC_OKTA_CLIENT_ID");
	const redirectUri = getRedirectUri();

	const nonce =
		typeof (AuthSession as any).generateRandom === "function"
			? (AuthSession as any).generateRandom(16)
			: Math.random().toString(36).slice(2);
	const discovery = await AuthSession.fetchDiscoveryAsync(issuer);

	const request = new AuthSession.AuthRequest({
		responseType: AuthSession.ResponseType.Code,
		clientId,
		redirectUri,
		// Include 'groups' when available so Okta can return groups in userinfo.
		// Critical item 2: we will derive roles from groups/app_roles and mirror to DB.
		scopes: ["openid", "profile", "email", "groups"],
		extraParams: { nonce },
	});

	const result = await request.promptAsync(discovery);

	if (result.type !== "success") {
		if (result.type === "dismiss" || result.type === "cancel") {
			throw new Error("Okta authorization was cancelled by the user.");
		}
		throw new Error(`Okta authorization failed with type="${result.type}".`);
	}

	const code = result.params.code as string | undefined;
	if (!code) {
		throw new Error("Okta authorization response missing authorization code.");
	}
	if (!request.codeVerifier) {
		throw new Error("Missing PKCE code_verifier for token exchange.");
	}

	const tokenResponse = await AuthSession.exchangeCodeAsync(
		{
			clientId,
			code,
			redirectUri,
			extraParams: {
				code_verifier: request.codeVerifier,
			},
		},
		discovery,
	);

	const idToken =
		(tokenResponse as any).idToken ??
		(tokenResponse as any).id_token ??
		undefined;
	const accessToken =
		(tokenResponse as any).accessToken ??
		(tokenResponse as any).access_token ??
		undefined;

	if (!idToken) {
		throw new Error("Okta token exchange did not return an id_token.");
	}

	return {
		idToken,
		accessToken,
		discovery,
		redirectUri,
		nonce,
	};
}

/**
 * Critical item 2 (Stage 5): Fetch Okta userinfo and normalize for post-login sync.
 * - Returns profileJson with key OIDC claims and all raw claims spread in (no secrets logged).
 * - Returns roles derived from 'groups' or 'app_roles' claims (normalized, deduped, lowercased).
 * - Safe to call repeatedly; if no access token or fetch failure, returns null.
 * Idempotency note: the downstream RPC upserts profile and reconciles roles.
 */
export interface OktaUserInfoResult {
	profileJson: {
		sub: string;
		email?: string;
		name?: string;
		preferred_username?: string;
	} & Record<string, any>;
	roles: string[];
}

function normalizeToStringArray(v: unknown): string[] {
	if (Array.isArray(v))
		return v.filter((x) => typeof x === "string") as string[];
	if (typeof v === "string") {
		// Accept comma or space-separated fallbacks
		const parts = v
			.split(/[,\s]+/g)
			.map((s) => s.trim())
			.filter(Boolean);
		return parts;
	}
	return [];
}

function deriveRolesFromClaims(raw: any): string[] {
	const fromGroups = normalizeToStringArray(raw?.groups);
	const fromAppRoles = normalizeToStringArray(raw?.app_roles);
	const all = [...fromGroups, ...fromAppRoles]
		.map((r) => r.trim().toLowerCase())
		.filter((r) => r.length > 0);
	// Deduplicate preserving order
	const seen = new Set<string>();
	const out: string[] = [];
	for (const r of all) {
		if (!seen.has(r)) {
			seen.add(r);
			out.push(r);
		}
	}
	return out;
}

export async function fetchOktaUserInfo(
	accessToken?: string,
): Promise<OktaUserInfoResult | null> {
	if (!accessToken) return null;
	const issuer = getEnv("EXPO_PUBLIC_OKTA_ISSUER");
	const discovery = await AuthSession.fetchDiscoveryAsync(issuer);
	const userInfoEndpoint =
		((discovery as any)?.userInfoEndpoint as string | undefined) ||
		((discovery as any)?.userinfo_endpoint as string | undefined) ||
		`${issuer.replace(/\/+$/, "")}/v1/userinfo`;

	let resp: Response;
	try {
		resp = await fetch(userInfoEndpoint, {
			method: "GET",
			headers: { Authorization: `Bearer ${accessToken}` },
		});
	} catch {
		// Network/transport error – treat as missing userinfo
		return null;
	}
	if (!resp.ok) {
		// Avoid logging tokens or PII; only status in dev builds if needed elsewhere.
		return null;
	}
	let raw: any = null;
	try {
		raw = await resp.json();
	} catch {
		return null;
	}
	if (!raw || typeof raw.sub !== "string" || raw.sub.length === 0) return null;

	const { sub, email, name, preferred_username, ...rest } = raw;
	const roles = deriveRolesFromClaims(raw);

	return {
		profileJson: { sub, email, name, preferred_username, ...rest },
		roles,
	};
}

/**
 * Critical item 3: End-session URL builder and timeout/retry helper.
 * - Builds Okta end_session URL with id_token_hint and post_logout_redirect_uri.
 * - Provides a fetch wrapper with 6s timeout and single retry with jitter.
 * - Dev-only logs are terse and never include secrets.
 */

/**
 * Build the Okta end-session URL from discovery.
 * Returns null when discovery does not expose an end_session endpoint.
 *
 * redirectUri resolution:
 * - Explicit param (highest precedence)
 * - EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT env
 * - Fallback to "omnivia://signout" with a dev-only warn
 */
export async function buildEndSessionUrl(params: {
	idToken: string;
	redirectUri?: string;
}): Promise<string | null> {
	const { idToken } = params;
	if (!idToken || typeof idToken !== "string") return null;

	let effectiveRedirect =
		params.redirectUri ??
		process.env.EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT ??
		`${scheme}://signout`;

	if (
		!params.redirectUri &&
		!process.env.EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT
	) {
		if (typeof __DEV__ !== "undefined" && __DEV__) {
			// Dev-only: indicate fallback is being used (no secrets).
			console.warn(
				"[auth] end-session redirect not configured; defaulting to omnivia://signout",
			);
		}
	}

	let discovery: AuthSession.DiscoveryDocument | null = null;
	try {
		discovery = await getOktaDiscovery();
	} catch {
		discovery = null;
	}
	const endSessionEndpoint =
		((discovery as any)?.end_session_endpoint as string | undefined) ||
		((discovery as any)?.endSessionEndpoint as string | undefined) ||
		null;

	if (!endSessionEndpoint) return null;

	const url =
		`${endSessionEndpoint}` +
		`?id_token_hint=${encodeURIComponent(idToken)}` +
		`&post_logout_redirect_uri=${encodeURIComponent(effectiveRedirect)}`;

	return url;
}

/**
 * Call the end-session URL with a 6s timeout and a single retry with jitter.
 * - Uses AbortController for timeout.
 * - Retries once on network failure or timeout with 250–750ms jitter.
 * - Returns { ok, url } where ok reflects the best-effort HTTP success (resp.ok).
 *
 * Note: This is best-effort; cookie-based server sessions may not be fully cleared
 * from a background fetch on native. UI must not block on this call.
 */
export async function callEndSessionWithTimeout(
	url: string,
): Promise<{ ok: boolean; url: string }> {
	const timeoutMs = 6000;

	const attempt = async (): Promise<boolean> => {
		const controller = new AbortController();
		const timer = setTimeout(() => controller.abort(), timeoutMs);
		try {
			const resp = await fetch(url, {
				method: "GET",
				redirect: "follow" as RequestRedirect,
				signal: controller.signal,
			});
			return !!resp.ok;
		} catch {
			return false;
		} finally {
			clearTimeout(timer);
		}
	};

	let ok = await attempt();
	if (!ok) {
		// jitter 250–750ms
		const jitter = 250 + Math.floor(Math.random() * 501);
		await new Promise((r) => setTimeout(r, jitter));
		ok = await attempt();
	}

	return { ok, url };
}

/**
 * Optional local ID token claims verifier (claims-only; no signature verification).
 *
 * References:
 * - [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:1)
 * - [docs/security/identity-negative-tests.md](docs/security/identity-negative-tests.md:1)
 *
 * Export: [typescript.verifyIdTokenClaims()](auth/okta.ts:1)
 *
 * Behavior
 * - If EXPO_PUBLIC_ENABLE_LOCAL_ID_VERIFY !== "true", this is a no-op that attempts to decode the payload for diagnostics and returns { ok: true, payload } without throwing.
 * - If enabled, decodes JWT header+payload (no signature crypto) and validates:
 *   - iss equals (opts.issuer || process.env.EXPO_PUBLIC_OKTA_ISSUER)
 *   - aud equals provided audience if supplied (string or array)
 *   - exp, nbf, iat with default leeway skewSec=300s; coerce ms -> seconds when needed
 *   - optional nonce when provided via opts (accepted via opts as any to avoid new deps in types)
 * - On failure, throws Error with code prefix:
 *   IDV_CLAIMS_JWT_MALFORMED, IDV_CLAIMS_DECODE, IDV_CLAIMS_ISS_MISMATCH, IDV_CLAIMS_AUD, IDV_CLAIMS_EXPIRED, IDV_CLAIMS_NBF, IDV_CLAIMS_IAT_FUTURE, IDV_CLAIMS_NONCE
 *
 * Notes
 * - Side-effect free; safe for React Native/Expo.
 * - Does not import or use crypto libraries; server-side verification (Supabase) remains the source of truth.
 */
export function verifyIdTokenClaims(
	idToken: string,
	opts?: {
		issuer?: string;
		audience?: string | string[];
		skewSec?: number;
		now?: number;
	},
): { ok: true; payload: any } | never {
	const enabled = process.env.EXPO_PUBLIC_ENABLE_LOCAL_ID_VERIFY === "true";

	// Always attempt to decode payload for diagnostics
	const safeDecodePayload = (): any => {
		try {
			const parts = String(idToken || "").split(".");
			if (parts.length < 2) return {};
			return _decodeJwtSegment(parts[1]);
		} catch {
			return {};
		}
	};

	if (!enabled) {
		const payload = safeDecodePayload();
		return { ok: true, payload };
	}

	// Strict decode and structure checks when enabled
	const segments = String(idToken || "").split(".");
	if (segments.length !== 3) {
		throw new Error("IDV_CLAIMS_JWT_MALFORMED: expected 3 segments");
	}
	let header: any;
	let payload: any;
	try {
		header = _decodeJwtSegment(segments[0]);
		payload = _decodeJwtSegment(segments[1]);
		// eslint-disable-next-line @typescript-eslint/no-unused-vars
		const _alg = header?.alg; // Not used, but decoding header validates base64 and JSON
	} catch (e: any) {
		throw new Error("IDV_CLAIMS_DECODE: failed to decode JWT header/payload");
	}

	const expectedIssuer = opts?.issuer || process.env.EXPO_PUBLIC_OKTA_ISSUER;
	if (expectedIssuer && String(payload?.iss) !== String(expectedIssuer)) {
		throw new Error("IDV_CLAIMS_ISS_MISMATCH: issuer does not match");
	}

	// Audience (only when provided)
	if (opts?.audience !== undefined) {
		const expectedList = Array.isArray(opts.audience)
			? (opts.audience as string[])
			: typeof opts.audience === "string"
				? [opts.audience]
				: [];
		const audClaim = payload?.aud;
		let matches = false;
		if (typeof audClaim === "string") {
			matches = expectedList.includes(audClaim);
		} else if (Array.isArray(audClaim)) {
			matches = audClaim.some((a) => expectedList.includes(String(a)));
		}
		if (!matches) {
			throw new Error("IDV_CLAIMS_AUD: audience mismatch");
		}
	}

	const skewSec =
		typeof opts?.skewSec === "number"
			? Math.max(0, Math.floor(opts.skewSec))
			: 300;
	const nowSec =
		typeof opts?.now === "number"
			? Math.floor(opts.now)
			: Math.floor(Date.now() / 1000);

	const normSec = (v: any): number | null => {
		if (v === undefined || v === null) return null;
		let n = Number(v);
		if (!isFinite(n)) return null;
		// Coerce ms -> s if it looks like milliseconds
		if (n > 1_000_000_000_000) n = Math.floor(n / 1000);
		return Math.floor(n);
	};

	const exp = normSec(payload?.exp);
	const nbf = normSec(payload?.nbf);
	const iat = normSec(payload?.iat);

	if (exp !== null && nowSec > exp + skewSec) {
		throw new Error("IDV_CLAIMS_EXPIRED: token expired");
	}
	if (nbf !== null && nowSec < nbf - skewSec) {
		throw new Error("IDV_CLAIMS_NBF: token not valid yet");
	}
	if (iat !== null && iat - skewSec > nowSec) {
		throw new Error("IDV_CLAIMS_IAT_FUTURE: issued-at is in the future");
	}

	// Optional nonce support (accepted via opts as any to avoid widening the exported type)
	const expectedNonce = (opts as any)?.nonce as string | undefined;
	if (typeof expectedNonce === "string") {
		if (String(payload?.nonce || "") !== expectedNonce) {
			throw new Error("IDV_CLAIMS_NONCE: nonce mismatch");
		}
	}

	return { ok: true, payload };
}

/** Internal: base64url -> JSON object */
function _decodeJwtSegment(seg: string): any {
	const b64 = _b64urlToB64(seg);
	const text = _b64DecodeToString(b64);
	return JSON.parse(text);
}

/** Internal: normalize base64url to base64 padding */
function _b64urlToB64(s: string): string {
	let out = String(s || "")
		.replace(/-/g, "+")
		.replace(/_/g, "/");
	const pad = out.length % 4;
	if (pad === 2) out += "==";
	else if (pad === 3) out += "=";
	else if (pad !== 0) out += "==="; // extremely rare malformed case
	return out;
}

/** Internal: small, dependency-free base64 decoder to ASCII/UTF-8 string (sufficient for JWT JSON) */
function _b64DecodeToString(b64: string): string {
	const alphabet =
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	const table = new Int16Array(256).fill(-1);
	for (let i = 0; i < alphabet.length; i++) table[alphabet.charCodeAt(i)] = i;
	let buffer = 0;
	let bits = 0;
	let out = "";
	for (let i = 0; i < b64.length; i++) {
		const c = b64.charCodeAt(i);
		if (c === 61 /* '=' */) break;
		const v = table[c];
		if (v === -1) continue; // skip whitespace or invalid chars
		buffer = (buffer << 6) | v;
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			const byte = (buffer >> bits) & 0xff;
			out += String.fromCharCode(byte);
		}
	}
	// Best-effort UTF-8 decode
	try {
		// Decode UTF-8 bytes sequence to string

		return decodeURIComponent(
			out.replace(/[%\x80-\xFF]/g, (ch) => {
				const code = ch.charCodeAt(0);
				return "%" + code.toString(16).padStart(2, "0");
			}),
		);
	} catch {
		return out; // fallback (most JWT claims are ASCII)
	}
}
