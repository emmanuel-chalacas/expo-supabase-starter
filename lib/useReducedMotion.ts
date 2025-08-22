import { useEffect, useState } from "react";
import { AccessibilityInfo, Platform } from "react-native";

/**
 * useReducedMotion — respects OS setting and updates reactively.
 * Returns true when user prefers reduced motion.
 *
 * iOS/Android parity: AccessibilityInfo.getReduceMotionEnabled is supported on both.
 */
export function useReducedMotion(): boolean {
	const [reduced, setReduced] = useState<boolean>(false);

	useEffect(() => {
		let mounted = true;

		// Initial fetch
		AccessibilityInfo.isReduceMotionEnabled()
			.then((enabled) => {
				if (mounted) setReduced(!!enabled);
			})
			.catch(() => {
				// Fallback for older platforms
				if (mounted) setReduced(Platform.OS === "ios" ? false : false);
			});

		// Subscribe to changes
		const sub = AccessibilityInfo.addEventListener?.(
			// RN 0.72+: event name "reduceMotionChanged"; older RN used "reduceMotionChanged" as well
			"reduceMotionChanged" as any,
			(enabled: boolean) => {
				if (mounted) setReduced(!!enabled);
			},
		);

		return () => {
			mounted = false;
			try {
				// RN 0.72+: subscription returns { remove() }, or removeEventListener fallback
				// @ts-ignore
				sub?.remove?.();
				// @ts-ignore
				AccessibilityInfo.removeEventListener?.(
					"reduceMotionChanged",
					() => {},
				);
			} catch {
				/* noop */
			}
		};
	}, []);

	return reduced;
}
