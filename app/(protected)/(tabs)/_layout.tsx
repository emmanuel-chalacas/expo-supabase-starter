import React from "react";
import { Platform } from "react-native";
import { Tabs } from "expo-router";
import Ionicons from "@expo/vector-icons/Ionicons";

import { useColorScheme } from "@/lib/useColorScheme";
import { colors } from "@/constants/colors";
import { useFeatures } from "@/lib/useFeatures";

export default function TabsLayout() {
	const { colorScheme } = useColorScheme();
	const { ENABLE_PROJECTS } = useFeatures();

	return (
		<Tabs
			screenOptions={{
				headerShown: true,

				// Large titles are configured per-screen via Stack.Screen inside routes (e.g., Projects list).
				tabBarStyle: {
					backgroundColor:
						colorScheme === "dark"
							? colors.dark.background
							: colors.light.background,
				},
				tabBarActiveTintColor:
					colorScheme === "dark"
						? colors.dark.foreground
						: colors.light.foreground,
				tabBarShowLabel: false,
			}}
		>
			<Tabs.Screen
				name="index"
				options={{
					title: "Home",

					tabBarIcon: ({ color, size }) => (
						<Ionicons
							name={Platform.OS === "ios" ? "home-outline" : "home"}
							color={color}
							size={size ?? 24}
						/>
					),
				}}
			/>
			{ENABLE_PROJECTS ? (
				<Tabs.Screen
					name="projects"
					options={{
						title: "Projects",

						tabBarIcon: ({ color, size }) => (
							<Ionicons
								name={Platform.OS === "ios" ? "albums-outline" : "albums"}
								color={color}
								size={size ?? 24}
							/>
						),
					}}
				/>
			) : null}
			<Tabs.Screen
				name="settings"
				options={{
					title: "Settings",

					tabBarIcon: ({ color, size }) => (
						<Ionicons
							name={Platform.OS === "ios" ? "settings-outline" : "settings"}
							color={color}
							size={size ?? 24}
						/>
					),
				}}
			/>
		</Tabs>
	);
}
