# Okta Setup Worksheet — Omnivia Mobile (OIDC Native + Passwordless TOTP)
Version: 1.0 — This worksheet guides Security to configure and record tenant-specific values required by the app.

References
- Identity flow and artifacts: [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:50)
- Client PKCE helper: [typescript.oktaAuthorize()](auth/okta.ts:36)
- Supabase token exchange: [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:176)
- App deep link scheme and logout return: [app.json](app.json:1), [context/supabase-provider.tsx](context/supabase-provider.tsx:1)

Owner and dates
- Tenant/Org name: ____________
- Prepared by (Security): ____________
- Date: ____________

1. Tenant identifiers (from OIDC discovery)
- Issuer (EXPO_PUBLIC_OKTA_ISSUER): ______________________
- Authorization endpoint: ______________________
- Token endpoint: ______________________
- JWKS URI: ______________________
- End session endpoint (logout): ______________________

2. OIDC Native App configuration (Okta Admin Console)
- [ ] App type: OIDC — Native Application
- [ ] Grant type: Authorization Code with PKCE
- [ ] Scopes: openid, profile, email
- [ ] Redirect URIs:
  - omnivia://oauthredirect
- [ ] Post Logout Redirect URIs:
  - omnivia://signout
- [ ] Client ID (EXPO_PUBLIC_OKTA_CLIENT_ID): ______________________
- [ ] Assignments: add pilot users/groups for canary

3. Passwordless policy (TOTP-only for this app)
- [ ] Create/Select a Sign-on Policy for the application
- [ ] Require passwordless via Okta Verify TOTP or Google Authenticator
- [ ] Enforce for targeted user/group population (canary first)
- [ ] Backup factors and recovery codes enabled per org policy
- [ ] Verify that first-time users are guided to enroll an authenticator during [typescript.oktaAuthorize()](auth/okta.ts:36)

4. ID token claims and roles
- [ ] Preferred roles claim: app_roles included in ID token per mapping rules
- [ ] Optional groups claim not used for authorization by default
- [ ] Ensure identifiers (sub/preferred_username) align with downstream mirrors [user_profiles](docs/security/okta-oidc-supabase.md:197) and [user_roles](docs/security/okta-oidc-supabase.md:204)
- Notes: The client mirrors roles post-login; server-side RLS uses mirrored tables.

5. Values to copy into the app environment
- EXPO_PUBLIC_OKTA_ISSUER = (from Section 1)
- EXPO_PUBLIC_OKTA_CLIENT_ID = (from Section 2)
- EXPO_PUBLIC_OKTA_END_SESSION_REDIRECT = omnivia://signout
- EXPO_PUBLIC_ENABLE_OKTA_AUTH = true (enable once ready to test)
- EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER = oidc (default; switch to okta only if required)

6. Validation checklist (device or simulator)
- [ ] Launch app and tap “Continue with Okta” on a public screen
- [ ] Okta prompts enrollment/TOTP per policy; upon success, app exchanges code for ID token via [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:176)
- [ ] Protected tabs render; session persisted via [config/supabase.ts](config/supabase.ts:1)
- [ ] Sign out from Settings triggers RP-initiated logout and returns to omnivia://signout via [context/supabase-provider.tsx](context/supabase-provider.tsx:1)
- [ ] Negative test: cancel logout browser flow — app remains signed out locally

7. Recorded artifacts (attach or paste below)
- Screenshot: Okta app settings (General)
- Screenshot: Sign-on Policy with passwordless enforcement
- Discovery document JSON (redacted): issuer, authorization_endpoint, token_endpoint, end_session_endpoint
- Client ID string

8. Sign-off
- Security approver: ______________________
- Date: ______________________
- Notes: ______________________

Appendix — Pointers
- Client helper source: [typescript.oktaAuthorize()](auth/okta.ts:36)
- Auth storage: [config/supabase.ts](config/supabase.ts:1), [auth/secure-storage.ts](auth/secure-storage.ts:1)
- Tracker context and exit tests: [docs/projects-okta-rbac-implementation-tracker.md](docs/projects-okta-rbac-implementation-tracker.md:228


Yes — the app is built to let you keep Supabase sign-up/login now and switch to Okta later via a feature flag.

How it works

Runtime gate (no code change needed):
Keep EXPO_PUBLIC_ENABLE_OKTA_AUTH=false in .env to use the existing Supabase public screens and their legacy flows on:
app/(public)/welcome.tsx
app/(public)/sign-in.tsx
app/(public)/sign-up.tsx
Flip EXPO_PUBLIC_ENABLE_OKTA_AUTH=true when ready; those same screens show a single “Continue with Okta” button and route through Okta PKCE and token exchange via:
typescript.oktaSignIn()
supabase.auth.signInWithIdToken()
What users see

Flag OFF (today): legacy Supabase forms render as before on the three public screens; nothing in Stage 1 removed them.
Flag ON (later): the public screens render only the brand-compliant “Continue with Okta” CTA; successful auth lands in protected tabs; logout triggers Okta end-session via typescript.oktaSignOut().
Provider selection (under the hood)

The Okta path uses Supabase’s ID token exchange with the provider from env (EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER default “oidc”), read inside typescript.oktaSignIn(). This is independent of the UI gate, so you can keep the default and only change it if your Supabase plan requires “okta”.
Readiness notes before switching ON

Complete Okta tenant setup and record values in docs/security/okta-setup-worksheet.md.
Populate EXPO_PUBLIC_OKTA_ISSUER and EXPO_PUBLIC_OKTA_CLIENT_ID in .env, and ensure “omnivia” scheme is in [app.json](app.json:1).
Then set EXPO_PUBLIC_ENABLE_OKTA_AUTH=true to enable the Okta CTA in the UI.
Current status

With EXPO_PUBLIC_ENABLE_OKTA_AUTH=false, Supabase sign-up/login remains active via the legacy public screens. Switching to Okta later is a controlled, flag-only change with no additional code required.