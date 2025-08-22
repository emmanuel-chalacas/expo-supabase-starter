/* eslint-disable prettier/prettier */
import React, { useState } from "react";
import { View } from "react-native";
import { useRouter } from "expo-router";

import { Image } from "@/components/image";
import { SafeAreaView } from "@/components/safe-area-view";
import { Button } from "@/components/ui/button";
import { Text } from "@/components/ui/text";
import { H1, Muted } from "@/components/ui/typography";
import { useColorScheme } from "@/lib/useColorScheme";
import { oktaSignIn } from "@/context/supabase-provider";

const isOktaEnabled =
	(process.env.EXPO_PUBLIC_ENABLE_OKTA_AUTH || "false").toLowerCase() === "true";

export default function WelcomeScreen() {
	return isOktaEnabled ? <OktaWelcome /> : <LegacyWelcome />;
}

function OktaWelcome() {
	const [loading, setLoading] = useState(false);

	return (
		<SafeAreaView className="flex flex-1 bg-background p-6">
			<View className="flex flex-1 items-center justify-center gap-y-4 web:m-4">
				<H1 className="text-center">Welcome to Omnivia</H1>
			</View>
			<View className="flex flex-col gap-y-4 web:m-4">
				<Button
					size="lg"
					variant="default"
					haptic="selection"
					accessibilityLabel="Continue with Okta"
					disabled={loading}
					onPress={async () => {
						try {
							setLoading(true);
							await oktaSignIn();
						} catch {
							setLoading(false);
						}
					}}
				>
					<Text>Continue with Okta</Text>
				</Button>
			</View>
		</SafeAreaView>
	);
}

function LegacyWelcome() {
	const router = useRouter();
	const { colorScheme } = useColorScheme();
	const appIcon =
		colorScheme === "dark"
			? require("@/assets/icon.png")
			: require("@/assets/icon-dark.png");

	return (
		<SafeAreaView className="flex flex-1 bg-background p-6">
			<View className="flex flex-1 items-center justify-center gap-y-4 web:m-4">
				<Image source={appIcon} className="w-16 h-16 rounded-xl" />
				<H1 className="text-center">Welcome to Expo Supabase Starter</H1>
				<Muted className="text-center">
					A comprehensive starter project for developing React Native and Expo
					applications with Supabase as the backend.
				</Muted>
			</View>
			<View className="flex flex-col gap-y-4 web:m-4">
				<Button
					size="default"
					variant="default"
					haptic="selection"
					onPress={() => {
						router.push("/sign-up");
					}}
				>
					<Text>Sign Up</Text>
				</Button>
				<Button
					size="default"
					variant="secondary"
					haptic="selection"
					onPress={() => {
						router.push("/sign-in");
					}}
				>
					<Text>Sign In</Text>
				</Button>
			</View>
		</SafeAreaView>
	);
}
