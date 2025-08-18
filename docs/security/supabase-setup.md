# Supabase Setup Guide — Omnivia Projects + Okta + RBAC/RLS

Purpose: get your Supabase project ready for the app with schema, RLS, storage and auth settings.

Prerequisites
- You created a Supabase project and can access the Dashboard.
- You have your Project URL and anon public key added to [.env](.env).
- Optional: If testing email/password first, enable Email provider.

Step 1 — Create the Storage bucket
- In Supabase Dashboard → Storage → Create new bucket.
- Name: attachments
- Visibility: Private
- Create bucket.

Step 2 — Apply the Bootstrap SQL migration
- Go to Dashboard → SQL Editor.
- Open a new query and paste the contents of [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1).
- Run the script. It will:
  - Create core tables (projects, project_membership, contacts, engagements, attachments_meta, directories, partner_org, user_profiles, user_roles, features, staging_imports).
  - Enable Row Level Security and add policies (projects, UGC tables, features).
  - Add the using_rls_for_project(uuid) helper used by multiple policies.
  - Add storage policies for the attachments bucket.

Notes about order
- If you run the SQL before creating the bucket, that is OK. The storage policies will apply once the bucket exists.
- If you created the bucket after running the SQL, re-run the “Storage policies” section from the SQL file.

Step 3 — Configure Authentication (choose one path)
A) Legacy email/password for quick smoke tests
- Dashboard → Authentication → Providers → enable Email.
- Use the Sign Up/Sign In screens in the app.
B) Okta with ID token exchange (recommended)
- Ensure your Supabase plan supports signInWithIdToken with provider "oidc" or "okta".
- Follow [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:1) to configure Okta (issuer, client ID, redirect URIs) and verify login.

Step 4 — Quick validation checks
- App logs should show “[Supabase] URL valid: true” from [config/supabase.ts](config/supabase.ts:1).
- After logging in, verify:
  - You can navigate to protected tabs.
  - Creating a Contact or Engagement on a project succeeds.
  - Uploads only work when a matching attachments_meta row exists (private bucket).

Step 5 — Next steps for Projects feature
- Implement the import pipeline and membership materialization (Stage 4 in the tracker).
- Compute and persist derived project status (Stage 5).
- Build the Projects UI (Stage 6) and keep relying on RLS for enforcement.

Troubleshooting
- Invalid URL error: ensure [.env](.env) values are real, no quotes, no trailing slash.
- Permission denied on select/insert: confirm your user has membership via project_membership and correct role in user_roles.
- Storage upload fails: ensure attachments_meta row exists for the object and that you’re a member on the project.

Appendix A — What the SQL migration creates
Tables
- user_profiles, user_roles
- partner_org, partner_normalization
- ds_directory, rm_directory
- projects, project_membership
- contacts, engagements, attachments_meta
- features
- staging_imports
Policies and helpers
- using_rls_for_project(uuid) helper function
- RLS policies on projects, UGC tables, features
Storage
- Policies on storage.objects for bucket attachments (select/insert/delete)

Appendix B — Where to find the SQL
- File: [docs/sql/omni-bootstrap.sql](docs/sql/omni-bootstrap.sql:1)
- Open it, copy all, and paste into the SQL Editor.