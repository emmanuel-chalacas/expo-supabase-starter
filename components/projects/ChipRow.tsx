import React from "react";
import { ScrollView, View } from "react-native";
import { Button } from "@/components/ui/button";
import { Text } from "@/components/ui/text";
import * as Haptics from "@/lib/haptics";

export type ChipItem = {
	id: string;
	label: string;
	selected: boolean;
};

export function ChipRow(props: {
	chips: ChipItem[];
	maxPrimary?: number;
	onToggle: (id: string) => void;
	onOpenFilters: () => void;
	testID?: string;
}) {
	const { chips, maxPrimary = 5, onToggle, onOpenFilters, testID } = props;

	const primary = chips.slice(0, maxPrimary);
	const hasOverflow = chips.length > maxPrimary;

	return (
		<ScrollView
			horizontal
			showsHorizontalScrollIndicator={false}
			contentContainerStyle={{ paddingHorizontal: 12, gap: 8 }}
			testID={testID}
		>
			{primary.map((c) => (
				<Button
					key={c.id}
					size="sm"
					variant={c.selected ? "secondary" : "outline"}
					onPress={() => {
						Haptics.selection();
						onToggle(c.id);
					}}
					className="px-3"
					accessibilityLabel={`Toggle filter ${c.label}`}
				>
					<Text>{c.label}</Text>
				</Button>
			))}

			{hasOverflow ? (
				<Button
					size="sm"
					variant="outline"
					onPress={() => {
						Haptics.selection();
						onOpenFilters();
					}}
					className="px-3"
					accessibilityLabel="Open filters"
					testID="chip-overflow-filters"
				>
					<Text>Filters</Text>
				</Button>
			) : null}
		</ScrollView>
	);
}
