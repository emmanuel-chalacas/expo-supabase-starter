-- Omnivia — Stage 3 Migration (Policies refinement)
-- Purpose: Refine RLS helper to include DP org hierarchy visibility; leave prior policies as-is.
-- Note: Supabase CLI wraps migrations in a transaction. Do not add BEGIN/COMMIT here.

-- Helper: using_rls_for_project(project_id)
-- Updated DP logic:
--   - dp_admin and dp_pm: visible via ORG membership OR any SUB_ORG under their partner_org
--   - dp_cp: visible only via exact SUB_ORG membership
create or replace function public.using_rls_for_project(p_project_id uuid)
returns boolean
language sql
stable
as $$
  with me as (
    select
      u.user_id,
      coalesce(up.tenant_id, 'TELCO') as tenant_id,
      up.partner_org_id,
      up.sub_partner_org_id
    from (select auth.uid() as user_id) u
    left join public.user_profiles up on up.user_id = u.user_id
  )
  select
    -- Vendor Admin: global
    exists (
      select 1 from public.user_roles r
      join me on me.user_id = r.user_id
      where r.role = 'vendor_admin'
    )
    or
    -- Telco Admin/PM: same-tenant visibility
    exists (
      select 1
      from public.user_roles r
      join me on me.user_id = r.user_id
      join public.projects p on p.id = p_project_id
      where r.role in ('telco_admin','telco_pm')
        and p.tenant_id = me.tenant_id
    )
    or
    -- Telco DS/RM: assigned projects via USER membership
    exists (
      select 1
      from public.user_roles r
      join me on me.user_id = r.user_id
      where r.role in ('telco_ds','telco_rm')
        and exists (
          select 1 from public.project_membership m
          where m.project_id = p_project_id
            and m.member_user_id = me.user_id
        )
    )
    or
    -- Delivery Partner Admin/PM: ORG membership or any SUB_ORG under their org
    exists (
      select 1
      from public.user_roles r
      join me on me.user_id = r.user_id
      where r.role in ('dp_admin','dp_pm')
        and (
          exists (
            select 1 from public.project_membership m1
            where m1.project_id = p_project_id
              and m1.member_partner_org_id = me.partner_org_id
          )
          or exists (
            select 1
            from public.project_membership m2
            where m2.project_id = p_project_id
              and m2.member_sub_partner_org_id in (
                select po.id from public.partner_org po
                where po.parent_partner_org_id = me.partner_org_id
              )
          )
        )
    )
    or
    -- Construction Partner: only their exact SUB_ORG membership
    exists (
      select 1
      from public.user_roles r
      join me on me.user_id = r.user_id
      where r.role = 'dp_cp'
        and exists (
          select 1 from public.project_membership m3
          where m3.project_id = p_project_id
            and m3.member_sub_partner_org_id = me.sub_partner_org_id
        )
    )
  ;
$$;