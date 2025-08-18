/* eslint-disable prettier/prettier */
import {
	createContext,
	PropsWithChildren,
	useContext,
	useEffect,
	useRef,
	useState,
} from "react";

import { Session } from "@supabase/supabase-js";

import { router } from "expo-router";
import {
	oktaAuthorize,
	fetchOktaUserInfo,
	buildEndSessionUrl,
	callEndSessionWithTimeout,
	verifyIdTokenClaims,
} from "../auth/okta";
import {
	secureAuthStorage,
	OKTA_ID_TOKEN_HINT_KEY,
} from "../auth/secure-storage";
import { supabase } from "../config/supabase";

// In-memory cache of the most recent Okta access token for userinfo sync; not persisted.
let OKTA_ACCESS_TOKEN_CACHE: string | undefined;
// In-memory cache of the most recent Okta ID token for optional local claims verification; not persisted.
let OKTA_ID_TOKEN_CACHE: string | undefined;

export async function oktaSignIn(): Promise<void> {
	const provider = (process.env.EXPO_PUBLIC_SUPABASE_OIDC_PROVIDER || "oidc") as
		| "oidc"
		| "okta";
	const { idToken, accessToken } = await oktaAuthorize();
 
	await supabase.auth.signInWithIdToken({
		provider,
		token: idToken,
	});
 
	// Store id_token only for Okta end-session (sign-out); never log tokens.
	await secureAuthStorage.setItem(OKTA_ID_TOKEN_HINT_KEY, idToken).catch(() => {});
 
	// Cache Okta tokens in-memory for subsequent operations; not persisted.
	OKTA_ACCESS_TOKEN_CACHE = accessToken;
	OKTA_ID_TOKEN_CACHE = idToken;
 
	// Optional local ID token claims verification (dev/test guardrail; non-destructive)
	if ((process.env.EXPO_PUBLIC_ENABLE_LOCAL_ID_VERIFY || "false").toLowerCase() === "true") {
		try {
			verifyIdTokenClaims(idToken, {
				issuer: process.env.EXPO_PUBLIC_OKTA_ISSUER,
				skewSec: 300,
			});
		} catch (e: any) {
			// Dev-only redacted log; do not include token contents.
			if (typeof __DEV__ !== "undefined" && __DEV__) {
				const code = String(e?.message || "IDV_CLAIMS_ERROR").split(":")[0];
				// eslint-disable-next-line no-console
				console.warn(`[auth][local-id-verify] signin claims check failed: ${code}`);
			}
			// Non-destructive path: do not sign the user out; Supabase remains source of truth.
		}
	}
 
	// Critical item 2: Post-login profile/roles sync (fire-and-forget; do not block UI)
	(async () => {
		try {
			const info = await fetchOktaUserInfo(accessToken);
			if (!info) return;
			await supabase.rpc("fn_sync_profile_and_roles", {
				p_profile: info.profileJson,
				p_roles: info.roles,
			});
			if (typeof __DEV__ !== "undefined" && __DEV__) {
				console.debug("[auth] post-login sync invoked (signin)");
			}
		} catch {
			if (typeof __DEV__ !== "undefined" && __DEV__) {
				console.debug("[auth] post-login sync error (signin)");
			}
		}
	})();
}

export async function oktaSignOut(): Promise<void> {
	/**
	 * Critical item 3: Harden logout flow
	 * - Best-effort Okta end-session via background fetch with 6s timeout and single retry.
	 * - Guaranteed local session clear via supabase.auth.signOut().
	 * - Dedicated return path "/signout" for consistent post-logout landing (also deep link omnivia://signout).
	 *
	 * Verification (manual):
	 * - Trigger sign-out -> immediate navigation to /signout and local session cleared.
	 * - With ID token present, end-session URL includes id_token_hint and post_logout_redirect_uri.
	 * - Offline: retry once then give up silently; UI remains responsive.
	 * - iOS/Android: landing on /signout then navigating to Sign In works consistently.
	 */
	// Read last known Okta id_token (fast local read; may be absent).
	let idTokenHint: string | null = null;
	try {
		idTokenHint = await secureAuthStorage
			.getItem(OKTA_ID_TOKEN_HINT_KEY)
			.catch(() => null);
	} catch {
		idTokenHint = null;
	}
 
	// Fire-and-forget: build URL (discovery) and call end-session without blocking UI.
	if (idTokenHint) {
		(void (async () => {
			try {
				const url = await buildEndSessionUrl({ idToken: idTokenHint as string });
				if (url) {
					const { ok } = await callEndSessionWithTimeout(url);
					if (typeof __DEV__ !== "undefined" && __DEV__) {
						console.debug("[auth] end-session attempt:", ok ? "ok" : "failed");
					}
				} else {
					if (typeof __DEV__ !== "undefined" && __DEV__) {
						console.debug("[auth] end-session skipped (no endpoint)");
					}
				}
			} catch {
				if (typeof __DEV__ !== "undefined" && __DEV__) {
					console.debug("[auth] end-session skipped/error");
				}
			}
		})());
	} else {
		if (typeof __DEV__ !== "undefined" && __DEV__) {
			console.debug("[auth] end-session skipped (no id_token_hint)");
		}
	}
 
	// Always clear local session reliably
	try {
		await supabase.auth.signOut();
	} catch {
		/* noop */
	}
 
	// Forget cached id token hint
	await secureAuthStorage.removeItem(OKTA_ID_TOKEN_HINT_KEY).catch(() => {});
 
	// Navigate to dedicated post-logout route; cast to any to avoid typed-routes lag during codegen.
	try {
		router.replace("/signout" as any);
	} catch {
		/* noop */
	}
}

type AuthState = {
	initialized: boolean;
	session: Session | null;
	signUp: (email: string, password: string) => Promise<void>;
	signIn: (email: string, password: string) => Promise<void>;
	signOut: () => Promise<void>;
	oktaSignIn: () => Promise<void>;
	oktaSignOut: () => Promise<void>;
};

export const AuthContext = createContext<AuthState>({
	initialized: false,
	session: null,
	signUp: async () => {},
	signIn: async () => {},
	signOut: async () => {},
	oktaSignIn: async () => {},
	oktaSignOut: async () => {},
});

export const useAuth = () => useContext(AuthContext);

export function AuthProvider({ children }: PropsWithChildren) {
	const [initialized, setInitialized] = useState(false);
	const [session, setSession] = useState<Session | null>(null);


	// Debounce timer for post-login sync to avoid excessive calls
	const syncTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

	// Debounce/throttle for optional local ID token claims verification
	const verifyTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	const lastVerifyAtRef = useRef<number>(0);

	// Schedule a local claims verify with small debounce and 60s throttle window
	const scheduleLocalClaimsVerify = (delayMs = 1000) => {
		try {
			if ((process.env.EXPO_PUBLIC_ENABLE_LOCAL_ID_VERIFY || "false").toLowerCase() !== "true") {
				return;
			}
			const now = Date.now();
			// Throttle: at most once per 60s
			if (now - lastVerifyAtRef.current < 60000) return;

			if (verifyTimerRef.current) clearTimeout(verifyTimerRef.current);
			verifyTimerRef.current = setTimeout(async () => {
				verifyTimerRef.current = null;
				lastVerifyAtRef.current = Date.now();

				// Prefer in-memory cache; fall back to secure storage if necessary
				let token: string | null | undefined = OKTA_ID_TOKEN_CACHE;
				if (!token) {
					try {
						token = await secureAuthStorage.getItem(OKTA_ID_TOKEN_HINT_KEY);
					} catch {
						token = null;
					}
				}
				if (!token || typeof token !== "string") return;
				try {
					verifyIdTokenClaims(token, {
						issuer: process.env.EXPO_PUBLIC_OKTA_ISSUER,
						skewSec: 300,
					});
				} catch (e: any) {
					if (typeof __DEV__ !== "undefined" && __DEV__) {
						const code = String(e?.message || "IDV_CLAIMS_ERROR").split(":")[0];
						// eslint-disable-next-line no-console
						console.warn(`[auth][local-id-verify] refresh claims check failed: ${code}`);
					}
					// Non-destructive path by design
				}
			}, delayMs);
		} catch {
			/* noop */
		}
	};

	// Invoke RPC to sync profile and roles. Safe and idempotent server-side.
	const runPostLoginSync = async (accessToken?: string) => {
		try {
			const info = await fetchOktaUserInfo(accessToken);
			if (!info) return; // No userinfo available; skip without error.
			await supabase.rpc("fn_sync_profile_and_roles", {
				p_profile: info.profileJson,
				p_roles: info.roles,
			});
			// Dev-only: minimal signal, no PII or secrets
			if (typeof __DEV__ !== "undefined" && __DEV__) {
				console.debug("[auth] post-login sync invoked");
			}
		} catch {
			if (typeof __DEV__ !== "undefined" && __DEV__) {
				console.debug("[auth] post-login sync error");
			}
		}
	};

	// Debounced scheduler (default 10s window)
	const scheduleSync = (accessToken?: string, delayMs = 10000) => {
		try {
			if (syncTimerRef.current) clearTimeout(syncTimerRef.current);
			syncTimerRef.current = setTimeout(() => {
				void runPostLoginSync(accessToken);
			}, delayMs);
		} catch {
			/* noop */
		}
	};

	const signUp = async (email: string, password: string) => {
		const { data, error } = await supabase.auth.signUp({
			email,
			password,
		});

		if (error) {
			console.error("Error signing up:", error);
			return;
		}

		if (data.session) {
			setSession(data.session);
			console.log("User signed up:", data.user);
		} else {
			console.log("No user returned from sign up");
		}
	};

	const signIn = async (email: string, password: string) => {
		const { data, error } = await supabase.auth.signInWithPassword({
			email,
			password,
		});

		if (error) {
			console.error("Error signing in:", error);
			return;
		}

		if (data.session) {
			setSession(data.session);
			console.log("User signed in:", data.user);
		} else {
			console.log("No user returned from sign in");
		}
	};

	const signOut = async () => {
		const { error } = await supabase.auth.signOut();

		if (error) {
			console.error("Error signing out:", error);
			return;
		} else {
			console.log("User signed out");
		}
	};

	useEffect(() => {
		let isMounted = true;

		// Initialize current session
		supabase.auth.getSession().then(({ data: { session } }) => {
			if (!isMounted) return;
			setSession(session);
		});

		// Critical item 2: re-run sync on SIGNED_IN and TOKEN_REFRESHED with debounce.
		const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
			setSession(session);
	
			if (event === "SIGNED_IN" || event === "TOKEN_REFRESHED") {
				// Debounced 10s window to avoid multiple rapid calls
				scheduleSync(OKTA_ACCESS_TOKEN_CACHE, 10000);
				// Optional local claims verification (guarded and throttled)
				scheduleLocalClaimsVerify(1500);
			}
	
			if (event === "SIGNED_OUT") {
				// Clear any pending sync and forget tokens
				OKTA_ACCESS_TOKEN_CACHE = undefined;
				OKTA_ID_TOKEN_CACHE = undefined;
				if (syncTimerRef.current) {
					clearTimeout(syncTimerRef.current);
					syncTimerRef.current = null;
				}
				if (verifyTimerRef.current) {
					clearTimeout(verifyTimerRef.current);
					verifyTimerRef.current = null;
				}
			}
		});

		setInitialized(true);

		// Cleanup
		return () => {
			isMounted = false;
			try {
				subscription?.unsubscribe();
			} catch {
				/* noop */
			}
			if (syncTimerRef.current) {
				clearTimeout(syncTimerRef.current);
				syncTimerRef.current = null;
			}
			if (verifyTimerRef.current) {
				clearTimeout(verifyTimerRef.current);
				verifyTimerRef.current = null;
			}
		};
	}, []);

	return (
		<AuthContext.Provider
			value={{
				initialized,
				session,
				signUp,
				signIn,
				signOut,
				oktaSignIn,
				oktaSignOut,
			}}
		>
			{children}
		</AuthContext.Provider>
	);
}
