/* eslint-disable prettier/prettier */
import React from "react";
import { View } from "react-native";
import { router } from "expo-router";

import { SafeAreaView } from "@/components/safe-area-view";
import { Button } from "@/components/ui/button";
import { Text } from "@/components/ui/text";
import { H1 } from "@/components/ui/typography";

/**
 * signout route
 * - Idempotent landing page for post-logout return (omnivia://signout).
 * - Part of Critical item 3: dedicated return path improves reliability across iOS/Android.
 *
 * Manual verification (see provider comments for full list):
 * - After sign-out, app should navigate here immediately even if network is offline.
 * - Tapping the button takes user to the Sign In screen.
 */
export default function SignOutScreen() {
	return (
		<SafeAreaView className="flex-1 bg-background p-4" edges={["bottom"]}>
			<View className="flex-1 gap-4 web:m-4">
				<H1 className="self-start">Signed out</H1>
				<Text className="opacity-80">
					You have been signed out. You can sign in again to continue.
				</Text>
			</View>
			<Button
				size="lg"
				variant="default"
				accessibilityLabel="Go to Sign In"
				onPress={() => {
					try {
						router.replace("/sign-in");
					} catch {
						/* noop */
					}
				}}
				className="web:m-4"
			>
				<Text>Go to Sign In</Text>
			</Button>
		</SafeAreaView>
	);
}