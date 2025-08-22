#!/usr/bin/env node
"use strict";

/**
 * Provider Smoke Test — Okta issuer reachability and provider parity
 * Audit context: see [docs/product/projects-okta-rbac-stage1-4-audit.md](docs/product/projects-okta-rbac-stage1-4-audit.md:1)
 * Tracker context: [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md:1)
 *
 * Behavior:
 *  - Non-destructive, network-only. No OAuth redirects initiated.
 *  - Reads env: EXPECTED_PROVIDER (optional), EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER,
 *    EXPO_PUBLIC_ENABLE_OKTA_AUTH, EXPO_PUBLIC_OKTA_ISSUER, EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT.
 *  - If auth disabled or issuer missing → prints "SKIP: missing issuer or auth disabled" and exits 0.
 *  - Validates provider parity (oidc|okta) and Okta discovery document.
 *  - Outputs JSON summary; exits non-zero on hard failures.
 */

const { env, exit } = process;

function normalizeIssuer(u) {
	return String(u || "")
		.trim()
		.replace(/\/+$/, "");
}

function isValidProviderValue(p) {
	return p === "oidc" || p === "okta";
}

function isDeepLinkOrHttps(u) {
	const s = String(u || "").trim();
	if (!s) return false;
	if (/^https:\/\//i.test(s)) return true;
	// Scheme://path (non-http(s) deep link)
	return /^[a-z][a-z0-9+.-]*:\/\/.+/i.test(s);
}

async function fetchWithTimeout(url, ms) {
	const ctrl = new AbortController();
	const id = setTimeout(() => ctrl.abort(), Math.max(1, ms | 0));
	try {
		const res = await fetch(url, { signal: ctrl.signal });
		return res;
	} finally {
		clearTimeout(id);
	}
}

async function main() {
	const expectedProvider = String(env.EXPECTED_PROVIDER || "").trim() || null;
	const provider =
		String(env.EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER || "").trim() || null;
	const enableAuth =
		String(env.EXPO_PUBLIC_ENABLE_OKTA_AUTH || "")
			.trim()
			.toLowerCase() === "true";
	const issuerRaw = String(env.EXPO_PUBLIC_OKTA_ISSUER || "").trim();
	const endSessionRedirectRaw = String(
		env.EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT || "",
	).trim();

	if (!enableAuth || !issuerRaw) {
		console.log("SKIP: missing issuer or auth disabled");
		return exit(0);
	}

	const summary = {
		ok: false,
		provider,
		expectedProvider,
		issuer: normalizeIssuer(issuerRaw),
		discoveryUrl: null,
		discovery: null,
		endSessionRedirect: null,
		warnings: [],
		errors: [],
	};

	// Provider parity
	if (expectedProvider) {
		if (!isValidProviderValue(expectedProvider)) {
			summary.errors.push("expected_provider_invalid");
		}
		if (expectedProvider !== provider) {
			summary.errors.push("provider_mismatch");
		}
	} else {
		if (!isValidProviderValue(provider)) {
			summary.errors.push("provider_invalid");
		}
	}

	// Discovery fetch
	const issuer = summary.issuer;
	const discoveryUrl = `${issuer}/.well-known/openid-configuration`;
	summary.discoveryUrl = discoveryUrl;

	try {
		const res = await fetchWithTimeout(discoveryUrl, 5000);
		if (!res.ok) {
			summary.errors.push(`discovery_http_${res.status}`);
		} else {
			const j = await res.json();
			summary.discovery = {
				issuer: j.issuer,
				authorization_endpoint: j.authorization_endpoint,
				jwks_uri: j.jwks_uri,
				end_session_endpoint: j.end_session_endpoint || null,
			};
			const jsonIssuer = normalizeIssuer(j.issuer || "");
			if (jsonIssuer !== issuer) {
				summary.errors.push("issuer_mismatch");
			}
			if (!j.authorization_endpoint) {
				summary.errors.push("authorization_endpoint_missing");
			}
			if (!j.jwks_uri) {
				summary.errors.push("jwks_uri_missing");
			}
			if (j.end_session_endpoint) {
				// note only; no validation required
			}
		}
	} catch (err) {
		summary.errors.push("discovery_fetch_failed");
		summary.warnings.push(String(err && err.message ? err.message : err));
	}

	// End-session redirect validation
	const redirect = endSessionRedirectRaw || "omnivia://signout";
	summary.endSessionRedirect = redirect;
	if (!endSessionRedirectRaw) {
		summary.warnings.push(
			"missing EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT — using default omnivia://signout",
		);
	}
	if (!isDeepLinkOrHttps(redirect)) {
		summary.errors.push("end_session_redirect_invalid");
	}

	summary.ok = summary.errors.length === 0;
	console.log(JSON.stringify(summary));
	return exit(summary.ok ? 0 : 1);
}

main();
