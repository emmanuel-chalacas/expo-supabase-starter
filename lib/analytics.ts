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
