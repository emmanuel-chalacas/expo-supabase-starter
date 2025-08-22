// Ambient module declarations to satisfy TypeScript when using dynamic imports.
// These packages are optional at runtime (Expo-managed vs bare), so we keep the types loose.

declare module "expo-haptics" {
	const mod: any;
	export = mod;
}

declare module "react-native-haptic-feedback" {
	const mod: any;
	export = mod;
}
