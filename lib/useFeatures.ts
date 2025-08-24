import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/config/supabase";

/**
 * Features flags hook
 *
 * - Reads env overrides:
 *    - EXPO_PUBLIC_ENABLE_PROJECTS
 *    - EXPO_PUBLIC_ENABLE_ATTACHMENTS_UPLOAD
 * - Fetches remote flags from features table for current tenant
 *    - tenant_id derived from user_profiles for current auth user
 * - Returns { ENABLE_PROJECTS, ENABLE_ATTACHMENTS_UPLOAD, loading }
 * - Fallback to env if remote fetch fails (do not throw)
 *
 * Source references:
 * - [docs/security/okta-oidc-supabase.md](docs/security/okta-oidc-supabase.md:197)
 * - features table seeded per Stage 2 in [docs/sql/stage2-apply.sql](docs/sql/stage2-apply.sql:167)
 */

type FeaturesState = {
	ENABLE_PROJECTS: boolean;
	ENABLE_ATTACHMENTS_UPLOAD: boolean;
	DETAIL_UNIFIED: boolean;
	loading: boolean;
};

function parseEnvBool(name: string, def: boolean): boolean {
	const v = (process.env as any)?.[name];
	if (typeof v !== "string") return def;
	const s = v.trim().toLowerCase();
	if (s === "true" || s === "1" || s === "yes" || s === "on") return true;
	if (s === "false" || s === "0" || s === "no" || s === "off") return false;
	return def;
}

export function useFeatures(): FeaturesState {
	const rawEnvProjects = (process.env as any)?.EXPO_PUBLIC_ENABLE_PROJECTS as
		| string
		| undefined;
	const rawEnvAttachments = (process.env as any)
		?.EXPO_PUBLIC_ENABLE_ATTACHMENTS_UPLOAD as string | undefined;

	// Phase 1 — Unified detail flag: env default only (remote overrides when present)
	const rawEnvDetailUnified = (process.env as any)
		?.EXPO_PUBLIC_DETAIL_UNIFIED as string | undefined;
	const envDetailUnifiedDefault =
		typeof rawEnvDetailUnified === "string"
			? (() => {
					const s = rawEnvDetailUnified.trim().toLowerCase();
					return s === "true" || s === "1";
				})()
			: false;

	// Only treat env values as overrides when they are explicitly provided.
	const envProjectsOverride =
		typeof rawEnvProjects === "string"
			? parseEnvBool("EXPO_PUBLIC_ENABLE_PROJECTS", false)
			: null;
	const envAttachmentsOverride =
		typeof rawEnvAttachments === "string"
			? parseEnvBool("EXPO_PUBLIC_ENABLE_ATTACHMENTS_UPLOAD", false)
			: null;

	const [tenantId, setTenantId] = useState<string | null>(null);
	const [remote, setRemote] = useState<Record<string, boolean> | null>(null);
	const [loading, setLoading] = useState<boolean>(true);

	// Resolve tenant_id for the current user (owner-only; RLS ensures own row)
	useEffect(() => {
		let mounted = true;

		(async () => {
			try {
				const { data: auth } = await supabase.auth.getUser();
				const uid = auth?.user?.id;
				if (!uid) {
					if (mounted) {
						setTenantId(null);
						setRemote(null);
						setLoading(false);
					}
					return;
				}

				const { data: profile, error: profErr } = await supabase
					.from("user_profiles")
					.select("tenant_id")
					.eq("user_id", uid)
					.maybeSingle();

				if (profErr) {
					if (mounted) {
						// Cannot read tenant — fall back to env only
						setTenantId(null);
						setRemote(null);
						setLoading(false);
					}
					return;
				}

				const tid = profile?.tenant_id ?? "TELCO";
				if (mounted) {
					setTenantId(tid);
				}

				// Fetch remote flags for tenant
				const { data: flags, error: flagsErr } = await supabase
					.from("features")
					.select("name,enabled")
					.eq("tenant_id", tid);

				if (flagsErr || !Array.isArray(flags)) {
					if (mounted) {
						// Remote failure — use env only
						setRemote(null);
						setLoading(false);
					}
					return;
				}

				const map: Record<string, boolean> = Object.create(null);
				for (const row of flags) {
					const name = String(row?.name || "");
					if (!name) continue;
					map[name] = !!row?.enabled;
				}

				if (mounted) {
					setRemote(map);
					setLoading(false);
				}
			} catch {
				if (mounted) {
					setTenantId(null);
					setRemote(null);
					setLoading(false);
				}
			}
		})();

		return () => {
			mounted = false;
		};
	}, []);

	// Combine env overrides with remote values.
	// Policy: If an env value is explicitly set, it takes precedence as an override.
	// Otherwise, use remote value; if remote missing or failed, fall back to env default.
	const value = useMemo<FeaturesState>(() => {
		const remoteProjects = remote?.ENABLE_PROJECTS ?? false;
		const remoteAttachments = remote?.ENABLE_ATTACHMENTS_UPLOAD ?? false;
		const remoteDetailUnified = remote?.DETAIL_UNIFIED;

		const ENABLE_PROJECTS =
			envProjectsOverride !== null ? envProjectsOverride : remoteProjects;
		const ENABLE_ATTACHMENTS_UPLOAD =
			envAttachmentsOverride !== null ? envAttachmentsOverride : remoteAttachments;

		// Phase 1 policy for DETAIL_UNIFIED:
		// Fallback order: remote (if present) -> env default -> false
		const DETAIL_UNIFIED =
			typeof remoteDetailUnified === "boolean" ? remoteDetailUnified : envDetailUnifiedDefault;

		return {
			ENABLE_PROJECTS,
			ENABLE_ATTACHMENTS_UPLOAD,
			DETAIL_UNIFIED,
			loading,
		};
	}, [remote, envProjectsOverride, envAttachmentsOverride, envDetailUnifiedDefault, loading, tenantId]);

	return value;
}
