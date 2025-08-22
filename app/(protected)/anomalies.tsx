import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Platform, ScrollView, Share, View } from "react-native";
import { SafeAreaView } from "@/components/safe-area-view";
// iOS-only context menu

// @ts-ignore -- optional native lib present per Stage 6 deps
import { ContextMenuButton } from "react-native-ios-context-menu";

import { supabase } from "@/config/supabase";
import { Button } from "@/components/ui/button";
import { Text } from "@/components/ui/text";
import { H2, Muted, P, Small } from "@/components/ui/typography";
import * as Haptics from "@/lib/haptics";

/**
 * Minimal Anomalies Dashboard (Critical item 5)
 * - Guards by location: this screen lives under the protected stack.
 * - Server-side guard: RPCs enforce operator/admin role checks.
 * - Data privacy: never render raw payloads; only payload_excerpt from the RPC/view (max 500 chars).
 *
 * Verification (manual), Critical item 5:
 * - Signed-in operator/admin:
 *   - Should see counts under "Stats (last 24h)" and a list of recent anomalies grouped by severity.
 * - Non-operator:
 *   - Should see an "Access denied or insufficient role" message.
 */

type AnomalyRow = {
	id: string;
	created_at: string;
	tenant_id: string;
	staging_id: string;
	batch_id: string;
	row_index: number;
	anomaly_type: string; // category
	field: string;
	input_value: string | null;
	reason: string;
	match_type: string | null;
	project_key: string | null;
	correlation_id: string;
	source: string | null;
	payload_excerpt: string | null;
	severity: "error" | "warning" | "info";
};

type StatRow = {
	tenant_id: string;
	category: string;
	severity: "error" | "warning" | "info";
	count: number;
	most_recent: string;
};

const SEVERITY_ORDER: AnomalyRow["severity"][] = ["error", "warning", "info"];

function formatTs(ts: string) {
	try {
		const d = new Date(ts);
		return d.toISOString().replace("T", " ").replace("Z", " UTC");
	} catch {
		return ts;
	}
}

function buildShareSummary(r: AnomalyRow): string {
	const parts = [
		`Anomaly (${r.severity}) — ${r.anomaly_type}`,
		r.project_key ? `Project: ${r.project_key}` : null,
		`Tenant: ${r.tenant_id}`,
		`When: ${formatTs(r.created_at)}`,
		r.field ? `Field: ${r.field}` : null,
		r.input_value ? `Value: ${r.input_value}` : null,
		`Reason: ${r.reason}`,
		`Correlation: ${r.correlation_id}`,
		r.source ? `Source: ${r.source}` : null,
	].filter(Boolean);
	return parts.join("\n");
}

export default function AnomaliesScreen() {
	const [loading, setLoading] = useState(false);
	const [errMsg, setErrMsg] = useState<string | null>(null);
	const [rows, setRows] = useState<AnomalyRow[]>([]);
	const [stats, setStats] = useState<StatRow[]>([]);

	const refresh = useCallback(async () => {
		setLoading(true);
		setErrMsg(null);
		try {
			// Recent anomalies (last 24h) — RPC enforces operator/admin role
			const { data: rowsData, error: rowsErr } = await supabase.rpc(
				"fn_anomalies_for_operator",
				{
					p_window_hours: 24,
					p_tenant: null,
					p_severity: null,
				},
			);

			if (rowsErr) {
				const msg = (rowsErr as any)?.message || String(rowsErr);
				// Detect privilege error (from SECURITY DEFINER guard)
				if (/insufficient_privilege/i.test(msg)) {
					setErrMsg("Access denied or insufficient role");
				} else {
					setErrMsg("Failed to load anomalies");
				}
				setRows([]);
			} else {
				const list = (Array.isArray(rowsData) ? rowsData : []) as AnomalyRow[];
				// Most recent 100 only, preserve order (RPC returns desc by created_at)
				setRows(list.slice(0, 100));
			}

			// Stats summary for last 24h
			const { data: statsData, error: statsErr } = await supabase.rpc(
				"fn_anomalies_stats",
				{
					p_window_hours: 24,
				},
			);
			if (statsErr) {
				// Non-fatal — leave stats empty if forbidden
				setStats([]);
			} else {
				setStats((Array.isArray(statsData) ? statsData : []) as StatRow[]);
			}
		} finally {
			setLoading(false);
		}
	}, []);

	useEffect(() => {
		void refresh();
	}, [refresh]);

	const grouped = useMemo(() => {
		const g: Record<AnomalyRow["severity"], AnomalyRow[]> = {
			error: [],
			warning: [],
			info: [],
		};
		for (const r of rows) {
			const sev = (r.severity || "info") as AnomalyRow["severity"];
			g[sev]?.push(r);
		}
		return g;
	}, [rows]);

	const statsTotals = useMemo(() => {
		let total = 0;
		const bySeverity: Record<AnomalyRow["severity"], number> = {
			error: 0,
			warning: 0,
			info: 0,
		};
		for (const s of stats) {
			total += s.count || 0;
			bySeverity[s.severity] = (bySeverity[s.severity] || 0) + (s.count || 0);
		}
		return { total, bySeverity };
	}, [stats]);

	return (
		<SafeAreaView className="flex-1 bg-background" edges={["bottom"]}>
			<ScrollView className="flex-1 p-4">
				<View className="mb-4 flex-row items-center justify-between">
					<H2>Anomalies</H2>
					<Button
						variant="default"
						size="sm"
						haptic="selection"
						onPress={() => void refresh()}
						disabled={loading}
					>
						<Text>{loading ? "Refreshing..." : "Refresh"}</Text>
					</Button>
				</View>

				<View className="mb-4">
					<Small className="text-muted-foreground">
						Last 24h stats (server-side). Only operators/admins can access.
					</Small>
					<View className="mt-2 rounded-md border border-border p-3">
						<P className="mb-1">
							Total: <Text className="font-semibold">{statsTotals.total}</Text>
						</P>
						<View className="flex-row gap-x-4">
							<Muted>
								error:{" "}
								<Text className="text-destructive font-medium">
									{statsTotals.bySeverity.error}
								</Text>
							</Muted>
							<Muted>
								warning:{" "}
								<Text className="text-foreground font-medium">
									{statsTotals.bySeverity.warning}
								</Text>
							</Muted>
							<Muted>
								info:{" "}
								<Text className="text-foreground font-medium">
									{statsTotals.bySeverity.info}
								</Text>
							</Muted>
						</View>
					</View>
				</View>

				{errMsg ? (
					<View className="rounded-md border border-border bg-muted/20 p-3">
						<Text className="text-destructive">{errMsg}</Text>
					</View>
				) : (
					SEVERITY_ORDER.map((sev) => {
						const list = grouped[sev] || [];
						if (!list.length) return null;
						return (
							<View key={sev} className="mb-6">
								<P className="mb-2 font-semibold capitalize">
									{sev} <Muted>({list.length})</Muted>
								</P>
								<View className="rounded-md border border-border">
									{list.map((r, idx) => {
										const RowInner = (
											<View
												key={r.id}
												className={[
													"p-3",
													idx < list.length - 1 ? "border-b border-border" : "",
												].join(" ")}
											>
												<View className="mb-1 flex-row justify-between">
													<Small className="text-muted-foreground">
														{formatTs(r.created_at)}
													</Small>
													<Small
														className={
															sev === "error"
																? "text-destructive"
																: sev === "warning"
																	? "text-foreground"
																	: "text-foreground"
														}
													>
														{sev}
													</Small>
												</View>
												<P className="mb-1">
													<Text className="font-semibold">
														{r.anomaly_type}
													</Text>{" "}
													<Muted>tenant</Muted>{" "}
													<Text className="font-medium">{r.tenant_id}</Text>{" "}
													<Muted>row</Muted>{" "}
													<Text className="font-medium">{r.row_index}</Text>{" "}
													{r.project_key ? (
														<>
															<Muted>project</Muted>{" "}
															<Text className="font-medium">
																{r.project_key}
															</Text>{" "}
														</>
													) : null}
												</P>
												<Muted className="mb-1">
													{r.field}: {r.input_value ?? ""}
													{r.match_type ? ` (${r.match_type})` : ""}
												</Muted>
												<P className="text-muted-foreground">{r.reason}</P>
												{r.payload_excerpt ? (
													<View className="mt-2 rounded bg-muted p-2">
														<Small className="text-muted-foreground">
															{r.payload_excerpt}
														</Small>
													</View>
												) : null}
											</View>
										);

										if (Platform.OS === "ios") {
											return (
												<ContextMenuButton
													key={r.id}
													isMenuPrimaryAction={false}
													menuConfig={{
														menuTitle: "Row actions",
														menuItems: [
															{
																actionKey: "share",
																actionTitle: "Share summary",
															},
														],
													}}
													onPressMenuItem={async (e: {
														nativeEvent: { actionKey: string };
													}) => {
														const { nativeEvent } = e;
														try {
															if (nativeEvent.actionKey === "share") {
																await Share.share({
																	message: buildShareSummary(r),
																});
																Haptics.success();
															} else {
																Haptics.selection();
															}
														} catch {
															Haptics.error();
														}
													}}
												>
													{RowInner}
												</ContextMenuButton>
											);
										}
										return RowInner;
									})}
								</View>
							</View>
						);
					})
				)}

				{!errMsg && rows.length === 0 ? (
					<Muted className="mt-8 text-center">
						No anomalies in the last 24 hours.
					</Muted>
				) : null}

				{/* References and anchors for audit */}
				<Muted className="mt-8">
					RPC: fn_anomalies_for_operator / fn_anomalies_stats; see{" "}
					<Text className="underline">
						[sql.vw_import_anomalies_recent](supabase/migrations/20250818024500_stage5_anomalies_views_policies.sql:1)
					</Text>
				</Muted>
			</ScrollView>
		</SafeAreaView>
	);
}
