import { View } from "react-native";
import { SafeAreaView } from "@/components/safe-area-view";

import { Button } from "@/components/ui/button";
import { Text } from "@/components/ui/text";
import { H1, Muted } from "@/components/ui/typography";
import { useAuth } from "@/context/supabase-provider";

const isOktaEnabled =
	(process.env.EXPO_PUBLIC_ENABLE_OKTA_AUTH || "false").toLowerCase() === "true";

export default function Settings() {
	const { signOut, oktaSignOut } = useAuth();

	return (
		<SafeAreaView className="flex-1 bg-background p-4" edges={["bottom"]}>
			<View className="flex-1 items-center justify-center gap-y-4">
				<H1 className="text-center">Sign Out</H1>
				<Muted className="text-center">
					Sign out and return to the welcome screen.
				</Muted>
			</View>
			<Button
				className="w-full"
				size="default"
				variant="default"
				haptic="selection"
				onPress={async () => {
					if (isOktaEnabled) {
						await oktaSignOut();
					} else {
						await signOut();
					}
				}}
			>
				<Text>Sign Out</Text>
			</Button>
		</SafeAreaView>
	);
}
