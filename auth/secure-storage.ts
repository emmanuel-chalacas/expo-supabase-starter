import * as SecureStore from "expo-secure-store";

export interface SecureAuthStorage {
	getItem(key: string): Promise<string | null>;
	setItem(key: string, value: string): Promise<void>;
	removeItem(key: string): Promise<void>;
}

export const OKTA_ID_TOKEN_HINT_KEY = "omni_okta_id_token_hint";

const memoryStore = new Map<string, string>();

let availabilityPromise: Promise<boolean> | null = null;
const isSecureStoreAvailable = (): Promise<boolean> => {
	if (!availabilityPromise) {
		availabilityPromise = SecureStore.isAvailableAsync()
			.then(Boolean)
			.catch(() => false);
	}
	return availabilityPromise;
};

export const secureAuthStorage: SecureAuthStorage = {
	async getItem(key: string): Promise<string | null> {
		const available = await isSecureStoreAvailable();
		if (available) {
			const value = await SecureStore.getItemAsync(key);
			return value ?? null;
		}
		return memoryStore.has(key) ? memoryStore.get(key)! : null;
	},
	async setItem(key: string, value: string): Promise<void> {
		const available = await isSecureStoreAvailable();
		if (available) {
			await SecureStore.setItemAsync(key, value);
			return;
		}
		memoryStore.set(key, value);
	},
	async removeItem(key: string): Promise<void> {
		const available = await isSecureStoreAvailable();
		if (available) {
			await SecureStore.deleteItemAsync(key);
			return;
		}
		memoryStore.delete(key);
	},
};
