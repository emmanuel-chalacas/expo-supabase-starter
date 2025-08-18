# Identity negative tests — local ID token claims verifier

Purpose
- Exercise the optional client-side claims verifier to ensure clock-skew and claim mismatch handling behaves as documented.
- The verifier is claims-only (no signature crypto); server-side verification (Supabase) remains the source of truth.
- References: [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:1), [typescript.verifyIdTokenClaims()](auth/okta.ts:306), call sites in [context/supabase-provider.tsx](context/supabase-provider.tsx:1).

Prerequisites
- Build/dev run with environment flag enabled:
  - EXPO_PUBLIC_ENABLE_LOCAL_ID_VERIFY=true
- A valid Okta sign-in flow already working via [typescript.oktaSignIn()](context/supabase-provider.tsx:32).
- Do not log or paste ID tokens into external tools. Use in-memory variables only.

What the local verifier does
- Decodes JWT header+payload (no signature verification).
- Validates:
  - iss equals the expected issuer (opts.issuer or EXPO_PUBLIC_OKTA_ISSUER).
  - aud equals provided audience if supplied (string or array).
  - exp, nbf, iat timestamps with default skewSec=300 seconds.
  - Optional nonce when provided via opts.
- Emits concise, machine-parseable error codes:
  - IDV_CLAIMS_JWT_MALFORMED
  - IDV_CLAIMS_DECODE
  - IDV_CLAIMS_ISS_MISMATCH
  - IDV_CLAIMS_AUD
  - IDV_CLAIMS_EXPIRED
  - IDV_CLAIMS_NBF
  - IDV_CLAIMS_IAT_FUTURE
  - IDV_CLAIMS_NONCE

How to observe failures
- With EXPO_PUBLIC_ENABLE_LOCAL_ID_VERIFY=true, the provider invokes the verifier after sign-in and on token refresh with a small debounce and throttle (at most 1x/min), see [context/supabase-provider.tsx](context/supabase-provider.tsx:324).
- In development (__DEV__), failures are redacted and logged to console like:
  - [auth][local-id-verify] signin claims check failed: IDV_CLAIMS_ISS_MISMATCH
  - [auth][local-id-verify] refresh claims check failed: IDV_CLAIMS_EXPIRED
- Supabase session handling remains authoritative; the app does not sign the user out based on local verifier errors.

Obtaining the ID token safely for ad-hoc tests (dev only)
- The last ID token is stored only for Okta end-session as OKTA_ID_TOKEN_HINT_KEY via [auth/secure-storage.ts](auth/secure-storage.ts:1). In a development console or a temporary debug action:
  1) Obtain the token (do not log it):
     - const tok = await secureAuthStorage.getItem("OKTA_ID_TOKEN_HINT_KEY");
  2) Use tok directly in [typescript.verifyIdTokenClaims()](auth/okta.ts:306) calls and immediately discard the reference.

Negative test cases

1) Wrong issuer (iss mismatch) → expect IDV_CLAIMS_ISS_MISMATCH
- Steps:
  - Sign in normally to obtain an ID token (tok).
  - In a dev console, call:
    - verifyIdTokenClaims(tok, { issuer: "https://wrong-issuer.example.com", skewSec: 300 });
- Expected:
  - The call throws Error with message starting "IDV_CLAIMS_ISS_MISMATCH".
  - App flow remains unaffected; Supabase session is still valid.

2) Expired token (exp in past beyond skew) → expect IDV_CLAIMS_EXPIRED
- Steps:
  - Decode payload timestamp to pick a now beyond exp + 300:
    - const p = ((): any => { try { return JSON.parse(atob(tok.split(".")[1].replace(/-/g,"+").replace(/_/g,"/"))); } catch { return {}; } })();
  - Call:
    - verifyIdTokenClaims(tok, { issuer: process.env.EXPO_PUBLIC_OKTA_ISSUER, now: (p.exp || Math.floor(Date.now()/1000)) + 301 });
- Expected:
  - The call throws "IDV_CLAIMS_EXPIRED".

3) Not-before in future (nbf beyond skew) → expect IDV_CLAIMS_NBF
- Steps:
  - Many ID tokens include nbf; if absent, skip to Test 3b below.
  - const p = (decode as above).
  - If p.nbf is present, call with now well before nbf - 300:
    - verifyIdTokenClaims(tok, { issuer: process.env.EXPO_PUBLIC_OKTA_ISSUER, now: (p.nbf - 301) });
- Expected:
  - The call throws "IDV_CLAIMS_NBF".
- Test 3b (fabricated token if your ID token lacks nbf):
  - Create a minimal unsigned JWT string: base64url({"alg":"none","typ":"JWT"}).base64url({"iss": process.env.EXPO_PUBLIC_OKTA_ISSUER, "nbf": Math.floor(Date.now()/1000)+1200, "exp": Math.floor(Date.now()/1000)+3600, "sub":"x"}) .
  - Pass signature segment as a single character (e.g., ".x") — signature is not verified locally.
  - Call verifyIdTokenClaims(fake, { issuer: process.env.EXPO_PUBLIC_OKTA_ISSUER, now: Math.floor(Date.now()/1000) });
  - Expect "IDV_CLAIMS_NBF".

4) Audience mismatch (when audience is supplied) → expect IDV_CLAIMS_AUD
- Steps:
  - Call:
    - verifyIdTokenClaims(tok, { issuer: process.env.EXPO_PUBLIC_OKTA_ISSUER, audience: "wrong-client-id" });
- Expected:
  - The call throws "IDV_CLAIMS_AUD".
- Note:
  - The provider’s default call sites omit audience to avoid false positives unless you have a stable expected value. See [context/supabase-provider.tsx](context/supabase-provider.tsx:50).

5) Missing/incorrect nonce when provided → expect IDV_CLAIMS_NONCE
- Steps:
  - Call with a nonce that is unlikely to match payload.nonce:
    - verifyIdTokenClaims(tok, { issuer: process.env.EXPO_PUBLIC_OKTA_ISSUER, nonce: "not-the-real-nonce" } as any);
- Expected:
  - The call throws "IDV_CLAIMS_NONCE" when payload.nonce differs or is missing.

6) Issued-at in the future → expect IDV_CLAIMS_IAT_FUTURE
- Steps:
  - const p = (decode as above).
  - If p.iat exists, call:
    - verifyIdTokenClaims(tok, { issuer: process.env.EXPO_PUBLIC_OKTA_ISSUER, now: (p.iat - 301) });
- Expected:
  - The call throws "IDV_CLAIMS_IAT_FUTURE".

Operational guidance
- Keep EXPO_PUBLIC_ENABLE_LOCAL_ID_VERIFY=false in production to avoid any behavioral change or overhead; the code path is fully gated.
- Default skewSec is 300 seconds. Only increase temporarily for diagnostics if devices show consistent clock drift.
- The local verifier is a guardrail for development/testing and early detection. Final authority on token validity is Supabase (server-side checks).

Appendix — references
- Verifier implementation: [typescript.verifyIdTokenClaims()](auth/okta.ts:306)
- Provider call sites (signin + refresh): [context/supabase-provider.tsx](context/supabase-provider.tsx:1)
- Skew documentation: [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:316)