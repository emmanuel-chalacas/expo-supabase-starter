import "react-native-get-random-values";
import "react-native-url-polyfill/auto";
import { AppState } from "react-native";

import { secureAuthStorage } from "../auth/secure-storage";
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL as string;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY as string;

// Safe validation logs (dev only). Do not log secrets.
if (__DEV__) {
	const urlLooksValid = /^https:\/\/.*\.supabase\.co$/i.test(
		String(supabaseUrl),
	);

	console.log("[Supabase] URL valid:", urlLooksValid);
}

if (!supabaseUrl) {
	throw new Error("Missing EXPO_PUBLIC_SUPABASE_URL environment variable");
}
if (!supabaseAnonKey) {
	throw new Error("Missing EXPO_PUBLIC_SUPABASE_ANON_KEY environment variable");
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
	auth: {
		storage: secureAuthStorage,
		autoRefreshToken: true,
		persistSession: true,
		detectSessionInUrl: false,
	},
});

AppState.addEventListener("change", (state) => {
	if (state === "active") {
		supabase.auth.startAutoRefresh();
	} else {
		supabase.auth.stopAutoRefresh();
	}
});
