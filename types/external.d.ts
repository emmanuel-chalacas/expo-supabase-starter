// Ambient module declarations for optional/native libs used in Stage 6 UI.
// These keep TypeScript happy in environments where types are not available.

declare module "expo-blur" {
	export const BlurView: any;
	export default any;
}

declare module "@gorhom/bottom-sheet" {
	const BottomSheet: any;
	export default BottomSheet;
	export const BottomSheetBackdrop: any;
	export const BottomSheetView: any;
}

declare module "react-native-ios-context-menu" {
	const ContextMenu: any;
	export default ContextMenu;
}

declare module "expo-document-picker" {
	export const getDocumentAsync: any;
	const mod: any;
	export default mod;
}
