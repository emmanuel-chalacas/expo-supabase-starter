/**
 * Authorization helpers for Projects module UI gating.
 * UI gates only; database RLS enforces actual access scope.
 *
 * Roles source:
 * - Read from public.user_roles (owner-only) per docs/security/okta-oidc-supabase.md
 * - Do NOT broaden RLS on client.
 *
 * Exports:
 * - [typescript.canViewProjects(userRoles: string[], features: Record<string, boolean>)](lib/authz.ts:1)
 * - [typescript.canCreateUGC(userRoles: string[])](lib/authz.ts:1)
 * - [typescript.canAssign(userRoles: string[])](lib/authz.ts:1)
 */

const VIEW_ROLES = new Set([
	"vendor_admin",
	"telco_admin",
	"telco_pm",
	"telco_ds",
	"telco_rm",
	"dp_admin",
	"dp_pm",
	"dp_cp",
]);

const UGC_ROLES = new Set([
	"vendor_admin",
	"telco_admin",
	"telco_pm",
	"telco_ds",
	"telco_rm",
	"dp_admin",
	"dp_pm",
	"dp_cp",
]);

// Assignment capabilities — Delivery Partner admins and PMs; Telco roles if business rules allow.
// Per MVP, keep UI hidden for Telco even if this returns true.
const ASSIGN_ROLES = new Set([
	"dp_admin",
	"dp_pm",
	// Telco roles included to reflect potential capability; keep UI hidden for Telco in MVP.
	"telco_admin",
	"telco_pm",
]);

function hasAnyRole(
	userRoles: readonly string[] | string[] | null | undefined,
	allow: Set<string>,
): boolean {
	if (!Array.isArray(userRoles) || userRoles.length === 0) return false;
	for (const r of userRoles) {
		const k = String(r || "")
			.toLowerCase()
			.trim();
		if (k && allow.has(k)) return true;
	}
	return false;
}

/**
 * UI gate for exposing Projects module entry points (tab, routes).
 * Returns true only when the Projects feature flag is enabled AND the user has a permitted role.
 *
 * features: expects a boolean property ENABLE_PROJECTS
 */
export function canViewProjects(
	userRoles: readonly string[] | string[] | null | undefined,
	features: Record<string, boolean> | null | undefined,
): boolean {
	const enabled = !!features?.ENABLE_PROJECTS;
	if (!enabled) return false;
	return hasAnyRole(userRoles, VIEW_ROLES);
}

/**
 * UI gate for UGC (Contacts, Engagements, Attachments upload).
 * Actual enforcement is via RLS (creator-bound or membership-bound).
 */
export function canCreateUGC(
	userRoles: readonly string[] | string[] | null | undefined,
): boolean {
	return hasAnyRole(userRoles, UGC_ROLES);
}

/**
 * UI gate for assignment actions (e.g., allocate Delivery Partner/SUB_ORG).
 * Per MVP: limit visible UI to DP Admin/PM; Telco roles may be allowed by business rules but keep hidden for now.
 */
export function canAssign(
	userRoles: readonly string[] | string[] | null | undefined,
): boolean {
	return hasAnyRole(userRoles, ASSIGN_ROLES);
}
