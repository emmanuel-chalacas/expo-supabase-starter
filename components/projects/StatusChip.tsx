import React from "react";
import { Pressable, View } from "react-native";
import { Text } from "@/components/ui/text";

/**
 * StatusChip — maps derived_status values to semantic token styles.
 * Tokens only; no hard-coded colors.
 *
 * Known statuses (Stage 5):
 * - In Progress
 * - In Progress - Overdue
 * - Complete
 * - Complete Overdue
 * - Complete Overdue Late App
 */
export type StatusValue =
	| "In Progress"
	| "In Progress - Overdue"
	| "Complete"
	| "Complete Overdue"
	| "Complete Overdue Late App"
	| string;

export function StatusChip(props: {
	status: StatusValue;
	selected?: boolean;
	onPress?: () => void;
	testID?: string;
}) {
	const { status, selected, onPress, testID } = props;

	const variantClass = getVariantClass(status, !!selected);

	return (
		<Pressable
			onPress={onPress}
			accessibilityRole="button"
			accessibilityLabel={`Filter by status ${status}`}
			testID={testID}
			className={[
				"px-3 py-2 rounded-full border",
				"min-h-8 items-center justify-center",
				variantClass.container,
			].join(" ")}
		>
			<View className="flex-row items-center">
				<Text className={["text-sm font-medium", variantClass.text].join(" ")}>
					{status}
				</Text>
			</View>
		</Pressable>
	);
}

function getVariantClass(status: StatusValue, selected: boolean) {
	// Semantic mapping to design tokens.
	// - Overdue variants -> destructive
	// - Complete* -> primary
	// - In Progress -> secondary
	const isOverdue =
		/overdue/i.test(status) ||
		/destructive/i.test(status) ||
		status === "destructive";
	const isComplete = /^complete/i.test(status);

	if (selected) {
		if (isOverdue) {
			return {
				container: "bg-destructive border-destructive",
				text: "text-destructive-foreground",
			};
		}
		if (isComplete) {
			return {
				container: "bg-primary border-primary",
				text: "text-primary-foreground",
			};
		}
		return {
			container: "bg-secondary border-secondary",
			text: "text-secondary-foreground",
		};
	}

	// Unselected state: outline/ghost styles
	if (isOverdue) {
		return {
			container: "bg-background border-destructive/60",
			text: "text-destructive",
		};
	}
	if (isComplete) {
		return {
			container: "bg-background border-primary/60",
			text: "text-primary",
		};
	}
	return {
		container: "bg-background border-border",
		text: "text-foreground",
	};
}
