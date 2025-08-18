-- Omnivia — Stage 5 Migration (Critical item 2): Post-login profile/roles sync RPC
-- Ref: [docs/product/projects-okta-rbac-stage1-4-audit.md](docs/product/projects-okta-rbac-stage1-4-audit.md:23)
-- Purpose: Define an idempotent SECURITY DEFINER RPC to mirror Okta user profile and roles into public.user_profiles and public.user_roles.
-- Notes:
--  - SECURITY DEFINER with search_path=public
--  - Uses auth.uid(); raises if null
--  - Upserts to public.user_profiles for current user; preserves created_at (and updated_at if present)
--  - Reconciles public.user_roles to exactly match provided roles (delete absent, insert missing)
--  - Grant EXECUTE to authenticated; not to anon
--  - Idempotent and safe for repeated invocation

create or replace function public.fn_sync_profile_and_roles(p_profile jsonb, p_roles text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_okta_sub text;
  v_okta_user_id text;
  v_tenant_id text;
  v_partner_org_id uuid;
  v_sub_partner_org_id uuid;
begin
  -- Enforce authenticated context; avoid anon execution
  if v_user_id is null then
    raise exception 'fn_sync_profile_and_roles: auth.uid() is null; must be authenticated';
  end if;

  -- Extract profile fields (tolerant to missing optional fields)
  v_okta_sub := nullif(p_profile->>'sub','');
  if v_okta_sub is null then
    -- Required for integrity: do not insert invalid mirror rows
    raise exception 'fn_sync_profile_and_roles: profile.sub is required';
  end if;

  v_okta_user_id := coalesce(nullif(p_profile->>'preferred_username',''), nullif(p_profile->>'email',''), v_okta_sub);
  v_tenant_id := nullif(p_profile->>'tenant_id','');

  -- Optional org context; safe UUID casts
  begin
    v_partner_org_id := nullif(p_profile->>'partner_org_id','')::uuid;
  exception when others then
    v_partner_org_id := null;
  end;

  begin
    v_sub_partner_org_id := nullif(p_profile->>'sub_partner_org_id','')::uuid;
  exception when others then
    v_sub_partner_org_id := null;
  end;

  -- Idempotent profile upsert. Preserve created_at; update mirror fields.
  insert into public.user_profiles as up (user_id, okta_sub, okta_user_id, tenant_id, partner_org_id, sub_partner_org_id)
  values (v_user_id, v_okta_sub, v_okta_user_id, v_tenant_id, v_partner_org_id, v_sub_partner_org_id)
  on conflict (user_id) do update
    set okta_sub = excluded.okta_sub,
        okta_user_id = excluded.okta_user_id,
        tenant_id = coalesce(excluded.tenant_id, up.tenant_id),
        partner_org_id = excluded.partner_org_id,
        sub_partner_org_id = excluded.sub_partner_org_id;

  -- Roles reconciliation: delete-then-insert to match provided set exactly.
  -- Normalize to lowercase trimmed tokens; empty/null ignored.
  with desired as (
    select distinct lower(btrim(x)) as role
    from unnest(coalesce(p_roles, '{}'::text[])) as x
    where coalesce(btrim(x), '') <> ''
  )
  delete from public.user_roles ur
  where ur.user_id = v_user_id
    and not exists (select 1 from desired d where d.role = ur.role);

  insert into public.user_roles(user_id, role)
  select v_user_id, d.role
  from (
    select distinct lower(btrim(x)) as role
    from unnest(coalesce(p_roles, '{}'::text[])) as x
    where coalesce(btrim(x), '') <> ''
  ) d
  on conflict (user_id, role) do nothing;

end;
$$;

-- Privileges: allow only authenticated, not anon, to execute the RPC
revoke all on function public.fn_sync_profile_and_roles(jsonb, text[]) from public;
grant execute on function public.fn_sync_profile_and_roles(jsonb, text[]) to authenticated;

-- Verification steps (manual, dev only):
-- 1) In psql with an authenticated context (auth.uid() resolves), run:
--    select public.fn_sync_profile_and_roles('{"sub":"oktasub-123","preferred_username":"user42","email":"u@example.com"}', array['vendor_admin','telco_pm']);
-- 2) Expect:
--    - Row exists in public.user_profiles keyed by your auth.uid() with okta_sub='oktasub-123' and okta_user_id='user42'
--    - public.user_roles for your auth.uid() contains exactly {'vendor_admin','telco_pm'}
-- Idempotency: Re-running with the same inputs yields no changes.