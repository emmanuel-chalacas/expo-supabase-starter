/**
 * Haptics wrapper — Stage 6
 * - Prefer Expo Haptics when available via dynamic import
 * - Fallback to react-native-haptic-feedback
 * - Throttle duplicates within a short window to avoid excessive feedback
 *
 * Exports:
 * - [typescript.selection()](lib/haptics.ts:1)
 * - [typescript.success()](lib/haptics.ts:1)
 * - [typescript.warning()](lib/haptics.ts:1)
 * - [typescript.error()](lib/haptics.ts:1)
 * - [typescript.destructive()](lib/haptics.ts:1)
 */

type HapticKind = "selection" | "success" | "warning" | "error" | "destructive";

let expoHaptics: any | null = null;
let nativeFallback: any | null = null;

const lastFire: Record<string, number> = Object.create(null);
const WINDOW_MS = 350; // throttle window

function shouldFire(key: HapticKind): boolean {
	const now = Date.now();
	const last = lastFire[key] || 0;
	if (now - last < WINDOW_MS) return false;
	lastFire[key] = now;
	return true;
}

async function ensureLoaded(): Promise<void> {
	if (expoHaptics || nativeFallback) return;
	try {
		// Dynamic import Expo Haptics when available (managed workflow friendly)
		expoHaptics = await import("expo-haptics");
	} catch {
		expoHaptics = null;
	}
	if (!expoHaptics) {
		try {
			// Fallback: react-native-haptic-feedback
			nativeFallback = await import("react-native-haptic-feedback");
		} catch {
			nativeFallback = null;
		}
	}
}

async function fire(kind: HapticKind): Promise<void> {
	if (!shouldFire(kind)) return;
	try {
		await ensureLoaded();

		if (expoHaptics) {
			switch (kind) {
				case "selection":
					await expoHaptics.selectionAsync();
					return;
				case "success":
					await expoHaptics.notificationAsync(
						expoHaptics.NotificationFeedbackType.Success,
					);
					return;
				case "warning":
					await expoHaptics.notificationAsync(
						expoHaptics.NotificationFeedbackType.Warning,
					);
					return;
				case "error":
				case "destructive":
					await expoHaptics.notificationAsync(
						expoHaptics.NotificationFeedbackType.Error,
					);
					return;
			}
		}

		if (nativeFallback) {
			const opts = {
				enableVibrateFallback: true,
				ignoreAndroidSystemSettings: false,
			};
			switch (kind) {
				case "selection":
					nativeFallback.default?.trigger?.("selection", opts);
					return;
				case "success":
					nativeFallback.default?.trigger?.("notificationSuccess", opts);
					return;
				case "warning":
					nativeFallback.default?.trigger?.("notificationWarning", opts);
					return;
				case "error":
				case "destructive":
					nativeFallback.default?.trigger?.("notificationError", opts);
					return;
			}
		}
	} catch {
		// Swallow to avoid impacting UX
	}
}

export function selection(): void {
	void fire("selection");
}
export function success(): void {
	void fire("success");
}
export function warning(): void {
	void fire("warning");
}
export function error(): void {
	void fire("error");
}
export function destructive(): void {
	void fire("destructive");
}
