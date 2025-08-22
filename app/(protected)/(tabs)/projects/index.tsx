import React, {
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
} from "react";
import {
	ActivityIndicator,
	FlatList,
	Platform,
	Pressable,
	Share,
	View,
} from "react-native";
import { Stack, router } from "expo-router";
import { BlurView } from "expo-blur";
import BottomSheet, {
	BottomSheetBackdrop,
	BottomSheetView,
} from "@gorhom/bottom-sheet";
import Ionicons from "@expo/vector-icons/Ionicons";

import { supabase } from "@/config/supabase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Text } from "@/components/ui/text";
import { H2, Muted, Small } from "@/components/ui/typography";
import { Image } from "@/components/image";
import { useFeatures } from "@/lib/useFeatures";
import { canViewProjects } from "@/lib/authz";
import { useReducedMotion } from "@/lib/useReducedMotion";
import * as Haptics from "@/lib/haptics";
import { AnalyticsEvents, track } from "@/lib/analytics";
import { type ProjectsCursor } from "@/lib/keyset-pagination";
import { StatusChip } from "@/components/projects/StatusChip";
import { ChipRow, type ChipItem } from "@/components/projects/ChipRow";
// iOS context menu (Expo Go: unsupported native module removed)
// import ContextMenu from "react-native-ios-context-menu"; // removed for Expo Go

/**
 * Stage 6 — Projects List
 * - Feature-gated by ENABLE_PROJECTS (remote flags with env override)
 * - Authorization-gated by roles via canViewProjects(); RLS enforces record scope
 * - Keyset pagination using helper (see [lib/keyset-pagination.ts](lib/keyset-pagination.ts:1))
 * - Chips overflow policy (max 5 + Filters bottom sheet)
 * - iOS large title; context menu on long-press; Android overflow parity (basic)
 * - Analytics: list_viewed, search_submitted, filter_applied, project_opened
 *
 * Index and order reference:
 * - Use keyset triple: stage_application ASC, stage_application_created DESC, id DESC
 * - See [docs/sql/stage6-keyset-verify.sql](docs/sql/stage6-keyset-verify.sql:1)
 */

type ProjectRow = {
	id: string;
	stage_application: string;
	stage_application_created: string;
	derived_status: string | null;
	developer_class: string | null;
	partner_org: { name: string | null } | null;
	// Task 5 — additional fields for UI filtering and display
	// See [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:541)
	address: string | null;
	suburb: string | null;
	state: string | null;
	development_type: string | null;
	build_type: string | null;
};

const PAGE_SIZE = 25;

type RpcCursor = {
	sort_ts: string;
	id: string;
};

const KNOWN_STATUSES: string[] = [
	"In Progress",
	"In Progress - Overdue",
	"Complete",
	"Complete Overdue",
	"Complete Overdue Late App",
];

export default function ProjectsListScreen() {
	const reduced = useReducedMotion();

	// 1) Feature flags and role-gated exposure
	const { ENABLE_PROJECTS, loading: flagsLoading } = useFeatures();

	const [roles, setRoles] = useState<string[]>([]);
	const [tenantId, setTenantId] = useState<string | null>(null);
	const [authLoading, setAuthLoading] = useState<boolean>(true);

	// 2) Local list state (preserved on back via router stack)
	const [search, setSearch] = useState<string>("");
	const [pendingSearch, setPendingSearch] = useState<string>("");
	const [sort, setSort] = useState<"newest" | "oldest">("newest");
	const [statusFilter, setStatusFilter] = useState<string[]>([]);
	// Task 5 filters: Development Type and Build Type (multi-select)
	// See [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:541)
	const [devTypeFilter, setDevTypeFilter] = useState<string[]>([]);
	const [buildTypeFilter, setBuildTypeFilter] = useState<string[]>([]);
	const [items, setItems] = useState<ProjectRow[]>([]);
	const [cursor, setCursor] = useState<ProjectsCursor | RpcCursor | null>(null);
	const [hasMore, setHasMore] = useState<boolean>(true);
	const [loading, setLoading] = useState<boolean>(false);

	// Bottom sheet for filters
	const sheetRef = useRef<any>(null);
	const [sheetOpen, setSheetOpen] = useState<boolean>(false);
	const snapPoints = useMemo(() => ["50%", "90%"], []);

	// Compute authZ
	const canSee = useMemo(
		() => canViewProjects(roles, { ENABLE_PROJECTS }),
		[roles, ENABLE_PROJECTS],
	);

	// Initial auth context (tenant and roles)
	useEffect(() => {
		let mounted = true;
		(async () => {
			setAuthLoading(true);
			try {
				const { data: auth } = await supabase.auth.getUser();
				const uid = auth?.user?.id;
				if (!uid) {
					if (mounted) {
						setRoles([]);
						setTenantId(null);
					}
					return;
				}

				const [{ data: prof }, { data: rs }] = await Promise.all([
					supabase
						.from("user_profiles")
						.select("tenant_id")
						.eq("user_id", uid)
						.maybeSingle(),
					supabase.from("user_roles").select("role"),
				]);

				if (mounted) {
					setTenantId(prof?.tenant_id ?? "TELCO");
					setRoles(
						Array.isArray(rs)
							? rs.map((r: any) => String(r.role || "").toLowerCase())
							: [],
					);
				}
			} finally {
				if (mounted) setAuthLoading(false);
			}
		})();
		return () => {
			mounted = false;
		};
	}, []);

	// Analytics: list_viewed (once when visible and authorized)
	const didTrackRef = useRef(false);
	useEffect(() => {
		if (
			!flagsLoading &&
			!authLoading &&
			ENABLE_PROJECTS &&
			canSee &&
			!didTrackRef.current
		) {
			didTrackRef.current = true;
			track(AnalyticsEvents.list_viewed, {
				sort,
				statusCount: statusFilter.length,
			});
		}
	}, [
		flagsLoading,
		authLoading,
		ENABLE_PROJECTS,
		canSee,
		sort,
		statusFilter.length,
	]);

	// Derived chips for primary row
	const chipItems: ChipItem[] = useMemo(() => {
		return KNOWN_STATUSES.map((label) => ({
			id: label,
			label,
			selected: statusFilter.includes(label),
		}));
	}, [statusFilter]);

	// Task 5: Development Type and Build Type chips
	// See [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:541)
	const DEV_TYPES = ["Residential", "Commercial", "Mixed Use"] as const;
	const BUILD_TYPES = ["SDU", "MDU", "HMDU", "MCU"] as const;

	const devTypeChips: ChipItem[] = useMemo(
		() =>
			DEV_TYPES.map((label) => ({
				id: label,
				label,
				selected: devTypeFilter.includes(label),
			})),
		[devTypeFilter],
	);
	const buildTypeChips: ChipItem[] = useMemo(
		() =>
			BUILD_TYPES.map((label) => ({
				id: label,
				label,
				selected: buildTypeFilter.includes(label),
			})),
		[buildTypeFilter],
	);
	
	// Load page helper
	const loadPage = useCallback(
		async (reset = false) => {
			if (!tenantId) return;
			if (loading) return;

			setLoading(true);
			try {
				if (sort === "newest") {
					const { data, error } = await supabase.rpc("rpc_projects_list", {
						p_search: search || null,
						p_status: statusFilter?.length ? statusFilter : null,
						p_dev_types: devTypeFilter?.length ? devTypeFilter : null,
						p_build_types: buildTypeFilter?.length ? buildTypeFilter : null,
						p_cursor_sort_ts:
							cursor && "sort_ts" in (cursor as any)
								? (cursor as any).sort_ts
								: null,
						p_cursor_id:
							cursor && "sort_ts" in (cursor as any) ? (cursor as any).id : null,
						p_limit: PAGE_SIZE,
					});
					if (error) throw error;

					const raw = (Array.isArray(data) ? data : []) as any[];

					const list: ProjectRow[] = raw.map((d: any) => ({
						id: String(d.id),
						stage_application: String(d.stage_application),
						stage_application_created: String(d.stage_application_created),
						derived_status: d?.derived_status ?? null,
						developer_class: d?.developer_class ?? null,
						partner_org:
							"partner_org_name" in d
								? { name: d?.partner_org_name ?? null }
								: null,
						address: d?.address ?? null,
						suburb: d?.suburb ?? null,
						state: d?.state ?? null,
						development_type: d?.development_type ?? null,
						build_type: d?.build_type ?? null,
					}));

					if (reset) {
						setItems(list);
					} else {
						setItems((prev) => [...prev, ...list]);
					}

					if (raw.length < PAGE_SIZE) {
						setHasMore(false);
						setCursor(null);
					} else {
						const lastRaw = raw[raw.length - 1] as any;
						setHasMore(true);
						setCursor({
							sort_ts: String(lastRaw.sort_ts),
							id: String(lastRaw.id),
						} as RpcCursor);
					}
				} else {
					let builder = supabase
						.from("projects")
						.select(
							// Task 5: extend projection with address/suburb/state and classification fields
							// See [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:541)
							"id,stage_application,stage_application_created,derived_status,developer_class,partner_org:partner_org_id(name),address,suburb,state,development_type,build_type",
						)
						.not("derived_status", "is", null);

					if (search.trim().length > 0) {
						builder = builder.ilike(
							"stage_application",
							`%${search.trim()}%`,
						);
					}
					if (statusFilter.length > 0) {
						builder = builder.in("derived_status", statusFilter);
					}
					// Task 5 filters: leverage indexes from Task 1 (projects_devtype_idx, projects_build_type_idx)
					// See [supabase/migrations/20250820100000_stage6_projects_field_alignment.sql](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1)
					if (devTypeFilter.length > 0) {
						builder = builder.in("development_type", devTypeFilter);
					}
					if (buildTypeFilter.length > 0) {
						builder = builder.in("build_type", buildTypeFilter);
					}

					const q = builder
						// Oldest: invert created ordering; keep stage_application ASC for stability
						.order("stage_application", { ascending: true, nullsFirst: false })
						.order("stage_application_created", {
							ascending: true,
							nullsFirst: false,
						})
						.order("id", { ascending: true, nullsFirst: false })
						.limit(PAGE_SIZE);

					const { data, error } = await q;
					if (error) throw error;

					const raw = (Array.isArray(data) ? data : []) as any[];
					const list: ProjectRow[] = raw.map((d: any) => ({
						id: String(d.id),
						stage_application: String(d.stage_application),
						stage_application_created: String(d.stage_application_created),
						derived_status: d?.derived_status ?? null,
						developer_class: d?.developer_class ?? null,
						partner_org: d?.partner_org
							? { name: d.partner_org?.name ?? null }
							: null,
						// Task 5 fields
						address: d?.address ?? null,
						suburb: d?.suburb ?? null,
						state: d?.state ?? null,
						development_type: d?.development_type ?? null,
						build_type: d?.build_type ?? null,
					}));

					if (reset) {
						setItems(list);
					} else {
						setItems((prev) => [...prev, ...list]);
					}

					if (list.length < PAGE_SIZE) {
						setHasMore(false);
						setCursor(null);
					} else {
						const last = list[list.length - 1];
						setHasMore(true);
						setCursor({
							stage_application: String(last.stage_application),
							created_at: String(last.stage_application_created),
							id: String(last.id),
						} as ProjectsCursor);
					}
				}
			} finally {
				setLoading(false);
			}
		},
		[
			tenantId,
			search,
			statusFilter,
			devTypeFilter,
			buildTypeFilter,
			sort,
			cursor,
			loading,
		],
	);

	// Reload when filters/search/sort change
	useEffect(() => {
		if (!tenantId || !canSee) return;
		setHasMore(true);
		setCursor(null);
		void loadPage(true);
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [
		tenantId,
		canSee,
		search,
		statusFilter.join("|"),
		devTypeFilter.join("|"),
		buildTypeFilter.join("|"),
		sort,
	]);

	const onToggleStatus = useCallback((id: string) => {
		setStatusFilter((prev) => {
			const next = prev.includes(id)
				? prev.filter((v) => v !== id)
				: [...prev, id];
			Haptics.selection();
			track(AnalyticsEvents.filter_applied, { statusCount: next.length });
			return next;
		});
	}, []);

	const onToggleDevType = useCallback((id: string) => {
		setDevTypeFilter((prev) =>
			prev.includes(id) ? prev.filter((v) => v !== id) : [...prev, id],
		);
		Haptics.selection();
	}, []);

	const onToggleBuildType = useCallback((id: string) => {
		setBuildTypeFilter((prev) =>
			prev.includes(id) ? prev.filter((v) => v !== id) : [...prev, id],
		);
		Haptics.selection();
	}, []);

	const onApplyFilters = useCallback(() => {
		sheetRef.current?.close();
	}, []);

	const onClearFilters = useCallback(() => {
		setStatusFilter([]);
		setDevTypeFilter([]);
		setBuildTypeFilter([]);
	}, []);

	if (flagsLoading || authLoading) {
		return (
			<View className="flex-1 bg-background items-center justify-center">
				<Muted>Loading…</Muted>
			</View>
		);
	}

	if (!ENABLE_PROJECTS || !canSee) {
		return (
			<View className="flex-1 bg-background items-center justify-center p-4">
				<Stack.Screen
					options={{
						headerShown: true,
						headerLargeTitle: Platform.OS === "ios",
						title: "Projects",
						animation: reduced ? "none" : "default",
						gestureEnabled: !sheetOpen,
					}}
				/>
				<H2 className="mb-2">Projects</H2>
				<Muted>Projects module is not available for your account.</Muted>
			</View>
		);
	}

	return (
		<View className="flex-1 bg-background">
			<Stack.Screen
				options={{
					headerShown: true,
					headerLargeTitle: Platform.OS === "ios",
					title: "Projects",
					gestureEnabled: !sheetOpen,
					animation: reduced ? "none" : "default",
					headerRight: () => (
						<View className="flex-row items-center">
							<Pressable
								accessibilityRole="button"
								accessibilityLabel="Toggle sort order"
								accessibilityHint="Switch between newest and oldest sorting"
								onPress={() => {
									setSort((s) => (s === "newest" ? "oldest" : "newest"));
									Haptics.selection();
								}}
								className="px-3 py-2"
							>
								<Text className="text-sm">
									{sort === "newest" ? "Newest" : "Oldest"}
								</Text>
							</Pressable>
						</View>
					),
				}}
			/>

			{/* Search */}
			<View className="px-4 pt-3 pb-2">
				<Input
					value={pendingSearch}
					onChangeText={setPendingSearch}
					placeholder="Search Stage Application or Address"
					returnKeyType="search"
					onSubmitEditing={() => {
						setSearch(pendingSearch.trim());
						track(AnalyticsEvents.search_submitted, {
							qlen: pendingSearch.trim().length,
						});
					}}
				/>
			</View>

			{/* Chips row with overflow policy (Status) */}
			<ChipRow
				chips={chipItems}
				maxPrimary={5}
				onToggle={onToggleStatus}
				onOpenFilters={() => {
					setSheetOpen(true);
					sheetRef.current?.expand();
				}}
			/>

			{/* Task 5: Development Type and Build Type chip groups */}
			<View className="px-4 mt-2">
				<Small className="mb-2 text-muted-foreground">Development Type</Small>
			</View>
			<ChipRow
				chips={devTypeChips}
				maxPrimary={5}
				onToggle={onToggleDevType}
				onOpenFilters={() => {
					setSheetOpen(true);
					sheetRef.current?.expand();
				}}
			/>
			<View className="px-4 mt-2">
				<Small className="mb-2 text-muted-foreground">Build Type</Small>
			</View>
			<ChipRow
				chips={buildTypeChips}
				maxPrimary={5}
				onToggle={onToggleBuildType}
				onOpenFilters={() => {
					setSheetOpen(true);
					sheetRef.current?.expand();
				}}
			/>

			{/* List */}
			<View className="px-4 mt-2 flex-1">
				<FlatList
					data={items}
					keyExtractor={(p) => p.id}
					renderItem={({ item: p }) => {
						const deepLink = `omnivia://projects/${encodeURIComponent(p.stage_application)}`;
						// Task 5: Compose address line when base address present; skip missing parts
						// See [docs/product/projects-data-field-inventory.md](docs/product/projects-data-field-inventory.md:541)
						const addr = (p.address ?? "").trim();
						const suburb = (p.suburb ?? "").trim();
						const state = (p.state ?? "").trim();
						const locality = [suburb || null, state || null].filter(Boolean).join(" ");
						const composedAddr = addr ? [addr, locality].filter(Boolean).join(", ") : "";
						return (
							<Pressable
								onPress={() => {
									Haptics.selection();
									track(AnalyticsEvents.project_opened, {
										stage_application: p.stage_application,
									});
									router.push({
										pathname:
											"/(protected)/projects/[stage_application]" as any,
										params: {
											stage_application: p.stage_application,
											q: search || "",
											s: sort,
											f: statusFilter.join(","),
										},
									} as any);
								}}
								onLongPress={() => {
									void Share.share({ message: deepLink, url: deepLink });
								}}
								accessibilityRole="button"
								accessibilityLabel={`Open ${p.stage_application}. Long press to share deep link.`}
								className="py-3 border-b border-border"
							>
								<View className="flex-row items-center justify-between">
									<View className="flex-1 pr-3">
										<Text className="text-base font-semibold">
											{p.stage_application}
										</Text>
										{composedAddr ? (
											<Small className="text-muted-foreground">
												{composedAddr}
											</Small>
										) : null}
									</View>
									{p.derived_status ? (
										<StatusChip status={p.derived_status} />
									) : null}
								</View>
								<Small className="mt-1 text-muted-foreground">
									{new Date(p.stage_application_created).toLocaleString()}
								</Small>
							</Pressable>
						);
					}}
					contentContainerStyle={{ paddingBottom: 16 }}
					onEndReached={() => {
						if (hasMore && !loading) {
							void loadPage(false);
						}
					}}
					onEndReachedThreshold={0.3}
					ListEmptyComponent={
						!loading ? (
							<Muted className="mt-8 text-center">
								No projects match the current filters.
							</Muted>
						) : null
					}
					ListFooterComponent={
						loading && hasMore ? (
							<View className="py-4 items-center">
								<ActivityIndicator />
							</View>
						) : null
					}
				/>
			</View>

			{/* Filters bottom sheet */}
			<BottomSheet
				ref={sheetRef}
				index={-1}
				snapPoints={snapPoints}
				enablePanDownToClose
				onClose={() => setSheetOpen(false)}
				onChange={(idx: number) => setSheetOpen(idx >= 0)}
				animationConfigs={{ duration: reduced ? 1 : 250 }}
				enableHandlePanningGesture={!reduced}
				enableContentPanningGesture={!reduced}
				backdropComponent={(props: any) => (
					<BottomSheetBackdrop
						{...props}
						appearsOnIndex={0}
						disappearsOnIndex={-1}
						opacity={0.4}
					/>
				)}
				backgroundStyle={{ backgroundColor: "transparent" }}
				handleIndicatorStyle={{ backgroundColor: "#999" }}
			>
				<BlurView
					intensity={30}
					tint="systemThickMaterial"
					style={{
						flex: 1,
						borderTopLeftRadius: 16,
						borderTopRightRadius: 16,
						overflow: "hidden",
					}}
				>
					<BottomSheetView style={{ padding: 16 }}>
						<H2 className="mb-2">Filters</H2>
						<Muted className="mb-4">Tap to toggle. Apply to dismiss.</Muted>

						<Small className="mb-1">Overall Status</Small>
						<View className="flex-row flex-wrap gap-2 mb-4">
							{KNOWN_STATUSES.map((s) => {
								const sel = statusFilter.includes(s);
								return (
									<Button
										key={s}
										size="sm"
										variant={sel ? "secondary" : "outline"}
										onPress={() => onToggleStatus(s)}
									>
										<Text>{s}</Text>
									</Button>
								);
							})}
						</View>

						{/* Task 5: Development/Build filter groups (index-backed .in() filters) */}
						{/* See [supabase/migrations/20250820100000_stage6_projects_field_alignment.sql](supabase/migrations/20250820100000_stage6_projects_field_alignment.sql:1) */}
						<Small className="mb-1">Development Type</Small>
						<View className="flex-row flex-wrap gap-2 mb-4">
							{DEV_TYPES.map((s) => {
								const sel = devTypeFilter.includes(s);
								return (
									<Button
										key={s}
										size="sm"
										variant={sel ? "secondary" : "outline"}
										onPress={() => onToggleDevType(s)}
									>
										<Text>{s}</Text>
									</Button>
								);
							})}
						</View>

						<Small className="mb-1">Build Type</Small>
						<View className="flex-row flex-wrap gap-2 mb-4">
							{BUILD_TYPES.map((s) => {
								const sel = buildTypeFilter.includes(s);
								return (
									<Button
										key={s}
										size="sm"
										variant={sel ? "secondary" : "outline"}
										onPress={() => onToggleBuildType(s)}
									>
										<Text>{s}</Text>
									</Button>
								);
							})}
						</View>

						<View className="flex-row gap-3 mt-2">
							<Button
								variant="outline"
								onPress={onClearFilters}
								accessibilityLabel="Clear filters"
							>
								<Text>Clear</Text>
							</Button>
							<Button
								variant="default"
								onPress={onApplyFilters}
								accessibilityLabel="Apply filters"
							>
								<Text>Apply</Text>
							</Button>
						</View>
					</BottomSheetView>
				</BlurView>
			</BottomSheet>
		</View>
	);
}
