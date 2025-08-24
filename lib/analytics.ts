/**
 * Analytics surface — Stage 6
 * Transport stub for Stage 7: currently logs to console.debug with event name and safe props.
 *
 * Events (constants):
 * - list_viewed
 * - search_submitted
 * - filter_applied
 * - project_opened
 * - engagement_added
 * - attachment_uploaded
 * - contact_added
 *
 * Dimensions guidance (see PRD/UI spec anchors):
 * - [docs/product/projects-feature-ui-ux.md §9 Analytics](docs/product/projects-feature-ui-ux.md:441)
 */

export const AnalyticsEvents = {
	list_viewed: "list_viewed",
	search_submitted: "search_submitted",
	filter_applied: "filter_applied",
	project_opened: "project_opened",
	engagement_added: "engagement_added",
	attachment_uploaded: "attachment_uploaded",
	contact_added: "contact_added",
} as const;

/**
 * Phase 7 — UI taxonomy events and helpers
 */
export const UIEvents = {
	ui_project_detail_viewed: "ui_project_detail_viewed",
	ui_section_expanded: "ui_section_expanded",
	ui_section_collapsed: "ui_section_collapsed",
	ui_jump_to_section: "ui_jump_to_section",
	ui_engagement_add_started: "ui_engagement_add_started",
	ui_engagement_added: "ui_engagement_added",
	ui_contact_add_started: "ui_contact_add_started",
	ui_contact_added: "ui_contact_added",
	ui_attachment_upload_started: "ui_attachment_upload_started",
	ui_attachment_uploaded: "ui_attachment_uploaded",
} as const;

export type UIEvent = (typeof UIEvents)[keyof typeof UIEvents];

/**
 * Allowed UI context dimensions for analytics (sanitized aggressively; no PII).
 */
export interface UIContextDims {
	role?: string; // normalized/enum-like; no emails/usernames
	delivery_partner_org?: string; // short code/slug, not display name if possible
	deployment_specialist_user?: boolean; // boolean flag instead of identity
	stage_application?: string;
	section_name?: "overview" | "timeline" | "contacts" | "engagements" | "attachments";
	filters_applied?: string; // e.g., "kind:site_visit|sort:newest"
	sort_option?: string; // e.g., "newest" | "oldest"
	source?: "chip" | "deeplink" | "button";
}

/**
 * Sanitize UI dims:
 * - Drop undefined/null
 * - Reject values that look like emails/phone numbers
 * - Trim strings to 64 chars
 * - Only keep keys defined by UIContextDims
 */
function sanitizeUIContextDims(
	dims?: UIContextDims,
): Partial<UIContextDims> | undefined {
	if (!dims) return undefined;

	const allowedKeys: Array<keyof UIContextDims> = [
		"role",
		"delivery_partner_org",
		"deployment_specialist_user",
		"stage_application",
		"section_name",
		"filters_applied",
		"sort_option",
		"source",
	];

	const out: Partial<UIContextDims> = {};
	const emailRe = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i;
	const phoneRe = /^\+?[0-9\s().-]{6,}$/;

	for (const k of allowedKeys) {
		const v = (dims as Record<string, unknown>)[k as string];
		if (v === undefined || v === null) continue;

		if (typeof v === "string") {
			let s = v.trim();
			if (!s) continue;
			// Reject email/phone looking values
			if (emailRe.test(s) || phoneRe.test(s)) continue;
			// Compact whitespace and enforce limit
			s = s.replace(/\s+/g, " ");
			if (s.length > 64) s = s.slice(0, 64);
			(out as Record<string, unknown>)[k as string] = s;
		} else if (typeof v === "boolean") {
			(out as Record<string, unknown>)[k as string] = v;
		} else {
			// Ignore non-string/boolean values
		}
	}

	return Object.keys(out).length ? out : undefined;
}

/**
 * [typescript.trackUI(event: UIEvent, dims?: UIContextDims)](lib/analytics.ts:1)
 * Wrapper over [typescript.track()](lib/analytics.ts:50) that enforces Phase 7 UI taxonomy and sanitization.
 */
export function trackUI(event: UIEvent, dims?: UIContextDims): void {
	try {
		const safe = sanitizeUIContextDims(dims);
		track(event as AnalyticsEventName, safe as Record<string, unknown> | undefined);
	} catch {
		// Never throw from telemetry
	}
}

export type AnalyticsEventName = keyof typeof AnalyticsEvents | string;

type AnalyticsProps = Record<string, unknown> | undefined;

function sanitizeProps(
	props?: Record<string, unknown>,
): Record<string, unknown> | undefined {
	if (!props) return undefined;
	// Minimal redaction: drop obvious PII-ish keys (client-side; server will enforce stricter rules in Stage 7)
	const REDACT_KEYS = new Set(["email", "phone", "name", "body", "payload"]);
	const out: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(props)) {
		if (REDACT_KEYS.has(k)) continue;
		out[k] = v;
	}
	return out;
}

/**
 * [typescript.track(event: string, props?: Record<string, any>)](lib/analytics.ts:1)
 * Logs an analytics event to console.debug for now. No network transport yet (Stage 7).
 */
export function track(event: AnalyticsEventName, props?: AnalyticsProps): void {
	try {
		const safe = sanitizeProps(props as any);

		console.debug(
			"[analytics]",
			String(event),
			safe ? JSON.stringify(safe) : "",
		);
	} catch {
		// Avoid throwing from telemetry
	}
}
