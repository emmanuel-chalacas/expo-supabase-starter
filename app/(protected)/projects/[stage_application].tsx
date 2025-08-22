import React, {
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
} from "react";
import { ActivityIndicator, Platform, ScrollView, View } from "react-native";
import { Stack, useLocalSearchParams } from "expo-router";
import * as DocumentPicker from "expo-document-picker";
import Ionicons from "@expo/vector-icons/Ionicons";

import { supabase } from "@/config/supabase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Text } from "@/components/ui/text";
import { H2, H3, Muted, P, Small } from "@/components/ui/typography";
import { Image } from "@/components/image";
import { useFeatures } from "@/lib/useFeatures";
import { canCreateUGC } from "@/lib/authz";
import * as Haptics from "@/lib/haptics";
import { AnalyticsEvents, track } from "@/lib/analytics";
import { SafeAreaView } from "@/components/safe-area-view";
import { useReducedMotion } from "@/lib/useReducedMotion";

/**
 * Stage 6 — Project Detail (tabs: Overview, Timeline, Contacts, Engagements, Attachments)
 * - Fetches by stage_application (deep-link omnivia://projects/{stage_application})
 * - Overview: imported fields read-only
 * - Timeline: MVP summary with EFSCD presence
 * - Contacts/Engagements: lists and creator-bound forms if canCreateUGC(); RLS enforces
 * - Attachments: metadata insert precedes storage upload; previews for image/* and application/pdf
 */

type ProjectRecord = {
	id: string;
	tenant_id: string;
	stage_application: string;
	stage_application_created: string;
	developer_class: string | null;
	derived_status: string | null;
	delivery_partner_label: string | null;
	partner_org: { name: string | null } | null;

	// Section 6 fields — Overview/Timeline per docs/product/projects-data-field-inventory.md:419
	address: string | null;
	suburb: string | null;
	state: string | null;
	fod_id: string | null;
	development_type: string | null;
	build_type: string | null;
	premises_count: number | null;
	residential: number | null;
	commercial: number | null;
	essential: number | null;

	// Timeline insertion (PCN) per docs/product/projects-data-field-inventory.md:425
	practical_completion_notified: string | null;

	// Existing timeline fields
	efscd: string | null;
	developer_design_submitted: string | null;
	developer_design_accepted: string | null;
	issued_to_delivery_partner: string | null;
	practical_completion_certified: string | null;
	delivery_partner_pc_sub: string | null;
	in_service: string | null;
};

type Contact = {
	id: string;
	name: string;
	// Company/Role optional fields per inventory Task 7 — see docs/product/projects-data-field-inventory.md:431
	company?: string | null;
	role?: string | null;
	phone: string | null;
	email: string | null;
	created_by: string;
	created_at: string;
};

type Engagement = {
	id: string;
	kind: string;
	body: string;
	created_by: string;
	created_at: string;
};

type AttachmentRow = {
	id: string;
	object_name: string;
	content_type: string | null;
	size_bytes: number | null;
	created_at: string;
};

type TabKey =
	| "Overview"
	| "Timeline"
	| "Contacts"
	| "Engagements"
	| "Attachments";

export default function ProjectDetailScreen() {
	const params = useLocalSearchParams<{
		stage_application?: string;
		q?: string;
		s?: string;
		f?: string;
	}>();
	const stageApp = String(params?.stage_application || "");
	const { ENABLE_PROJECTS, ENABLE_ATTACHMENTS_UPLOAD } = useFeatures();
	const reduced = useReducedMotion();

	// Roles for UI gating
	const [roles, setRoles] = useState<string[]>([]);
	const [userId, setUserId] = useState<string | null>(null);
	const [tenantId, setTenantId] = useState<string | null>(null);

	useEffect(() => {
		let mounted = true;
		(async () => {
			const { data: auth } = await supabase.auth.getUser();
			const uid = auth?.user?.id ?? null;
			const [{ data: profile }, { data: rs }] = await Promise.all([
				supabase
					.from("user_profiles")
					.select("tenant_id")
					.eq("user_id", uid)
					.maybeSingle(),
				supabase.from("user_roles").select("role"),
			]);
			if (!mounted) return;
			setUserId(uid);
			setTenantId(profile?.tenant_id ?? "TELCO");
			setRoles(
				Array.isArray(rs)
					? rs.map((r: any) => String(r.role || "").toLowerCase())
					: [],
			);
		})();
		return () => {
			mounted = false;
		};
	}, []);

	const canUGC = useMemo(() => canCreateUGC(roles), [roles]);

	// Active tab
	const [tab, setTab] = useState<TabKey>("Overview");

	// Project fetch
	const [proj, setProj] = useState<ProjectRecord | null>(null);
	const [loading, setLoading] = useState(true);

	const refreshProject = useCallback(async () => {
		if (!stageApp) return;
		setLoading(true);
		try {
			const { data, error } = await supabase
				.from("projects")
				.select(
					`
          id, tenant_id, stage_application, stage_application_created, developer_class, derived_status,
          delivery_partner_label, partner_org:partner_org_id(name),
          address, suburb, state, fod_id, development_type, build_type,
          premises_count, residential, commercial, essential,
          efscd, practical_completion_notified, developer_design_submitted, developer_design_accepted,
          issued_to_delivery_partner, practical_completion_certified, delivery_partner_pc_sub, in_service
        `,
				)
				.eq("stage_application", stageApp)
				.maybeSingle();
			if (error) throw error;
			if (data) {
				setProj({
					id: String((data as any).id),
					tenant_id: String((data as any).tenant_id),
					stage_application: String((data as any).stage_application),
					stage_application_created: String(
						(data as any).stage_application_created,
					),
					developer_class: (data as any).developer_class ?? null,
					derived_status: (data as any).derived_status ?? null,
					delivery_partner_label: (data as any).delivery_partner_label ?? null,
					partner_org: (data as any).partner_org
						? { name: (data as any).partner_org?.name ?? null }
						: null,

					// Section 6 fields — Overview/Timeline per docs/product/projects-data-field-inventory.md:419
					address: (data as any).address ?? null,
					suburb: (data as any).suburb ?? null,
					state: (data as any).state ?? null,
					fod_id: (data as any).fod_id ?? null,
					development_type: (data as any).development_type ?? null,
					build_type: (data as any).build_type ?? null,
					premises_count: (data as any).premises_count ?? null,
					residential: (data as any).residential ?? null,
					commercial: (data as any).commercial ?? null,
					essential: (data as any).essential ?? null,

					// Timeline insertion (PCN) per docs/product/projects-data-field-inventory.md:425
					efscd: (data as any).efscd ?? null,
					practical_completion_notified:
						(data as any).practical_completion_notified ?? null,

					developer_design_submitted:
						(data as any).developer_design_submitted ?? null,
					developer_design_accepted:
						(data as any).developer_design_accepted ?? null,
					issued_to_delivery_partner:
						(data as any).issued_to_delivery_partner ?? null,
					practical_completion_certified:
						(data as any).practical_completion_certified ?? null,
					delivery_partner_pc_sub:
						(data as any).delivery_partner_pc_sub ?? null,
					in_service: (data as any).in_service ?? null,
				});
			} else {
				setProj(null);
			}
		} finally {
			setLoading(false);
		}
	}, [stageApp]);

	useEffect(() => {
		void refreshProject();
	}, [refreshProject]);

	// Contacts
	const [contacts, setContacts] = useState<Contact[]>([]);
	const refreshContacts = useCallback(async () => {
		if (!proj?.id) return;
		const { data, error } = await supabase
			.from("contacts")
			.select("id,name,company,role,phone,email,created_by,created_at")
			.eq("project_id", proj.id)
			.order("created_at", { ascending: false });
		if (!error && Array.isArray(data)) {
			setContacts(
				data.map((c: any) => ({
					id: String(c.id),
					name: String(c.name),
					company: c.company ?? null,
					role: c.role ?? null,
					phone: c.phone ?? null,
					email: c.email ?? null,
					created_by: String(c.created_by),
					created_at: String(c.created_at),
				})),
			);
		}
	}, [proj?.id]);

	// Engagements
	const [engagements, setEngagements] = useState<Engagement[]>([]);
	const refreshEngagements = useCallback(async () => {
		if (!proj?.id) return;
		const { data, error } = await supabase
			.from("engagements")
			.select("id,kind,body,created_by,created_at")
			.eq("project_id", proj.id)
			.order("created_at", { ascending: false });
		if (!error && Array.isArray(data)) {
			setEngagements(
				data.map((e: any) => ({
					id: String(e.id),
					kind: String(e.kind || "note"),
					body: String(e.body || ""),
					created_by: String(e.created_by),
					created_at: String(e.created_at),
				})),
			);
		}
	}, [proj?.id]);

	// Attachments
	const [attachments, setAttachments] = useState<AttachmentRow[]>([]);
	const refreshAttachments = useCallback(async () => {
		if (!proj?.id) return;
		const { data, error } = await supabase
			.from("attachments_meta")
			.select("id,object_name,content_type,size_bytes,created_at")
			.eq("project_id", proj.id)
			.order("created_at", { ascending: false });
		if (!error && Array.isArray(data)) {
			setAttachments(
				data.map((a: any) => ({
					id: String(a.id),
					object_name: String(a.object_name),
					content_type: a.content_type ?? null,
					size_bytes: a.size_bytes ?? null,
					created_at: String(a.created_at),
				})),
			);
		}
	}, [proj?.id]);

	useEffect(() => {
		if (!proj?.id) return;
		void refreshContacts();
		void refreshEngagements();
		void refreshAttachments();
	}, [proj?.id, refreshContacts, refreshEngagements, refreshAttachments]);

	// Forms state
	// Contacts form
	// Company/Role optional fields per inventory Task 7 — docs/product/projects-data-field-inventory.md:431
	const [cName, setCName] = useState("");
	const [cCompany, setCCompany] = useState("");
	const [cRole, setCRole] = useState("");
	const [cPhone, setCPhone] = useState("");
	const [cEmail, setCEmail] = useState("");
	const [cSubmitting, setCSubmitting] = useState(false);

	const submitContact = useCallback(async () => {
		if (!proj?.id || !userId) return;
		setCSubmitting(true);
		try {
			const { error } = await supabase.from("contacts").insert({
				project_id: proj.id,
				created_by: userId, // RLS: created_by must equal auth.uid() per bootstrap policies — see supabase/migrations/20250817061900_omni_bootstrap.sql:171
				name: cName.trim(),
				// Company/Role optional fields per inventory Task 7 — docs/product/projects-data-field-inventory.md:431
				company: cCompany.trim() || null,
				role: cRole.trim() || null,
				phone: cPhone.trim() || null,
				email: cEmail.trim() || null,
			});
			if (error) throw error;
			Haptics.success();
			track(AnalyticsEvents.contact_added, {
				stage_application: proj.stage_application,
			});
			setCName("");
			setCCompany("");
			setCRole("");
			setCPhone("");
			setCEmail("");
			await refreshContacts();
		} catch {
			Haptics.warning();
		} finally {
			setCSubmitting(false);
		}
	}, [proj?.id, userId, cName, cCompany, cRole, cPhone, cEmail, refreshContacts]);

	// Engagements form
	const [eBody, setEBody] = useState("");
	const [eSubmitting, setESubmitting] = useState(false);

	const submitEngagement = useCallback(async () => {
		if (!proj?.id || !userId) return;
		setESubmitting(true);
		try {
			const { error } = await supabase.from("engagements").insert({
				project_id: proj.id,
				created_by: userId,
				kind: "note",
				body: eBody.trim(),
			});
			if (error) throw error;
			Haptics.success();
			track(AnalyticsEvents.engagement_added, {
				stage_application: proj.stage_application,
			});
			setEBody("");
			await refreshEngagements();
		} catch {
			Haptics.warning();
		} finally {
			setESubmitting(false);
		}
	}, [proj?.id, userId, eBody, refreshEngagements]);

	// Upload
	const [uploading, setUploading] = useState(false);
	const pickAndUpload = useCallback(async () => {
		if (!proj || !tenantId || !userId || !ENABLE_ATTACHMENTS_UPLOAD || !canUGC)
			return;

		// Pick file
		const result = await DocumentPicker.getDocumentAsync({
			multiple: false,
			copyToCacheDirectory: true,
			type: ["image/*", "application/pdf"],
		});
		if (result.canceled || !result.assets?.length) return;

		const asset = result.assets[0];
		const uri = asset.uri;
		const name = asset.name || "upload";
		const size = typeof asset.size === "number" ? asset.size : undefined;
		const mime =
			asset.mimeType ||
			(name.toLowerCase().endsWith(".pdf")
				? "application/pdf"
				: "application/octet-stream");

		// 25 MB cap
		const cap = 25 * 1024 * 1024;
		if (typeof size === "number" && size > cap) {
			Haptics.warning();
			return;
		}

		setUploading(true);
		try {
			// 1) Insert metadata (server policies require this before upload)
			// Use path tenant_id/stage_application/object_uuid (object_uuid = metadata id)
			const { data: metaIns, error: metaErr } = await supabase
				.from("attachments_meta")
				.insert({
					project_id: proj.id,
					created_by: userId,
					bucket: "attachments",
					object_name: "tmp", // placeholder; updated below using id
					content_type: mime,
					size_bytes: size ?? null,
				})
				.select("id")
				.single();
			if (metaErr) throw metaErr;

			const objectUuid = String(metaIns.id);
			const objectPath = `${tenantId}/${encodeURIComponent(proj.stage_application)}/${objectUuid}`;

			// Update object_name to final path (idempotent convenience)
			await supabase
				.from("attachments_meta")
				.update({ object_name: objectPath })
				.eq("id", objectUuid);

			// 2) Upload binary to storage bucket
			// Fetch blob from uri
			const blob = await (await fetch(uri)).blob();

			const attempt = async () => {
				const { error: upErr } = await supabase.storage
					.from("attachments")
					.upload(objectPath, blob, { contentType: mime, upsert: false });
				if (upErr) throw upErr;
			};

			let attemptNo = 0;
			const maxAttempts = 3; // initial + 2 retries
			// exponential backoff: 0ms, 500ms, 1000ms
			while (true) {
				try {
					await attempt();
					break;
				} catch (e) {
					attemptNo++;
					if (attemptNo >= maxAttempts) throw e;
					await new Promise((r) => setTimeout(r, attemptNo * 500));
				}
			}

			await refreshAttachments();
			Haptics.success();
			track(AnalyticsEvents.attachment_uploaded, {
				stage_application: proj.stage_application,
				mime,
				size_bytes: size ?? null,
			});
		} catch {
			Haptics.warning();
		} finally {
			setUploading(false);
		}
	}, [
		proj,
		userId,
		tenantId,
		ENABLE_ATTACHMENTS_UPLOAD,
		canUGC,
		refreshAttachments,
	]);

	const renderTabs = () => {
		const TabButton = ({ k, icon }: { k: TabKey; icon: any }) => (
			<Button
				size="sm"
				variant={tab === k ? "secondary" : "ghost"}
				onPress={() => setTab(k)}
				className="px-3"
			>
				<View className="flex-row items-center gap-x-1">
					<Ionicons name={icon} size={16} color="currentColor" />
					<Text>{k}</Text>
				</View>
			</Button>
		);

		return (
			<View className="flex-row gap-x-2 px-4 py-2 border-b border-border">
				<TabButton
					k="Overview"
					icon={
						Platform.OS === "ios"
							? "information-circle-outline"
							: "information-circle"
					}
				/>
				<TabButton
					k="Timeline"
					icon={Platform.OS === "ios" ? "time-outline" : "time"}
				/>
				<TabButton
					k="Contacts"
					icon={Platform.OS === "ios" ? "person-add-outline" : "person-add"}
				/>
				<TabButton
					k="Engagements"
					icon={Platform.OS === "ios" ? "chatbubbles-outline" : "chatbubbles"}
				/>
				<TabButton
					k="Attachments"
					icon={Platform.OS === "ios" ? "attach-outline" : "attach"}
				/>
			</View>
		);
	};

	if (loading) {
		return (
			<SafeAreaView className="flex-1 bg-background items-center justify-center">
				<ActivityIndicator />
			</SafeAreaView>
		);
	}

	if (!proj) {
		return (
			<SafeAreaView className="flex-1 bg-background items-center justify-center p-4">
				<Stack.Screen
					options={{
						headerShown: true,
						animation: reduced ? "none" : "default",
						title: stageApp || "Project",
					}}
				/>
				<Muted>Project not found or access denied.</Muted>
			</SafeAreaView>
		);
	}

	return (
		<SafeAreaView className="flex-1 bg-background">
			<Stack.Screen
				options={{
					headerShown: true,
					animation: reduced ? "none" : "default",
					// Compact header (no large title inside detail)
					title: proj.stage_application,
					gestureEnabled: true,
				}}
			/>

			{renderTabs()}

			<ScrollView className="flex-1 px-4 py-3">
				{tab === "Overview" ? (
					<View>
						<H2 className="mb-2">Overview</H2>
						<P>
							<Small className="text-muted-foreground">Stage Application</Small>{" "}
							<Text className="font-semibold">{proj.stage_application}</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Delivery Partner</Small>{" "}
							<Text className="font-medium">
								{proj.partner_org?.name || "Not Yet Assigned"}
							</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Developer Class</Small>{" "}
							<Text className="font-medium">{proj.developer_class || "-"}</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Derived Status</Small>{" "}
							<Text className="font-medium">{proj.derived_status || "-"}</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Stage App Created</Small>{" "}
							<Text className="font-medium">
								{new Date(proj.stage_application_created).toLocaleString()}
							</Text>
						</P>

						{/* Overview fields per docs/product/projects-data-field-inventory.md:419 */}
						{proj.address ? (
							<P className="mt-2">
								<Small className="text-muted-foreground">Address</Small>{" "}
								<Text className="font-medium">
									{(() => {
										const primary = String(proj.address || "").trim();
										const locality = [proj.suburb, proj.state]
											.filter(Boolean)
											.join(" ")
											.trim();
										return locality ? `${primary}, ${locality}` : primary;
									})()}
								</Text>
							</P>
						) : null}

						{proj.fod_id ? (
							<P className="mt-2">
								<Small className="text-muted-foreground">FOD ID</Small>{" "}
								<Text className="font-medium">{proj.fod_id}</Text>
							</P>
						) : null}

						<P className="mt-2">
							<Small className="text-muted-foreground">Development Type</Small>{" "}
							<Text className="font-medium">{proj.development_type || "-"}</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Build Type</Small>{" "}
							<Text className="font-medium">{proj.build_type || "-"}</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Premises Count</Small>{" "}
							<Text className="font-medium">
								{typeof proj.premises_count === "number" ? proj.premises_count : 0}
							</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Residential</Small>{" "}
							<Text className="font-medium">
								{typeof proj.residential === "number" ? proj.residential : 0}
							</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Commercial</Small>{" "}
							<Text className="font-medium">
								{typeof proj.commercial === "number" ? proj.commercial : 0}
							</Text>
						</P>
						<P className="mt-2">
							<Small className="text-muted-foreground">Essential</Small>{" "}
							<Text className="font-medium">
								{typeof proj.essential === "number" ? proj.essential : 0}
							</Text>
						</P>

						{/* Storage-only: latitude/longitude intentionally not rendered per docs/product/projects-data-field-inventory.md:332 */}
					</View>
				) : null}

				{tab === "Timeline" ? (
					<View>
						<H2 className="mb-2">Timeline</H2>
						{(() => {
							const milestones: Array<[string, string | Date | null]> = [
								["Stage Application Created", proj?.stage_application_created ?? null],
								["Developer Design Submitted", proj?.developer_design_submitted ?? null],
								["Developer Design Accepted", proj?.developer_design_accepted ?? null],
								["Issued to Delivery Partner", proj?.issued_to_delivery_partner ?? null],
								["Practical Completion Notified", proj?.practical_completion_notified ?? null],
								["Practical Completion Certified", proj?.practical_completion_certified ?? null],
								["Delivery Partner PC Sub", proj?.delivery_partner_pc_sub ?? null],
								["In Service", proj?.in_service ?? null],
							];
							return milestones.map(([label, value]) => (
								<P key={label} className="mb-1">
									<Small className="text-muted-foreground">{label}</Small>{" "}
									<Text className="font-medium">
										{value ? new Date(value as any).toLocaleString() : "Not yet provided"}
									</Text>
								</P>
							));
						})()}
						{/* Overview only per PRD; no milestone bars in MVP */}
					</View>
				) : null}

				{tab === "Contacts" ? (
					<View>
						<H2 className="mb-3">Contacts</H2>
						{contacts.map((c) => (
							<View key={c.id} className="py-2 border-b border-border">
								<Text className="font-medium">{c.name}</Text>
								{/* Company/Role optional fields per inventory Task 7 — docs/product/projects-data-field-inventory.md:431 */}
								{(() => {
									const segments: string[] = [];
									if (c.company) segments.push(String(c.company));
									if (c.role) segments.push(String(c.role));
									if (c.phone) segments.push(String(c.phone));
									if (c.email) segments.push(String(c.email));
									return segments.length ? (
										<Small className="text-muted-foreground">
											{segments.join(" • ")}
										</Small>
									) : null;
								})()}
							</View>
						))}
						{contacts.length === 0 ? (
							<Muted className="mb-3">No contacts yet.</Muted>
						) : null}

						{canUGC ? (
							<View className="mt-4">
								<H3 className="mb-2">Add Contact</H3>
								<View className="gap-3">
									<Input
										placeholder="Name"
										value={cName}
										onChangeText={setCName}
									/>
									{/* Company/Role optional fields per inventory Task 7 — docs/product/projects-data-field-inventory.md:431 */}
									<Input
										placeholder="Company"
										value={cCompany}
										onChangeText={setCCompany}
									/>
									<Input
										placeholder="Role"
										value={cRole}
										onChangeText={setCRole}
									/>
									<Input
										placeholder="Phone"
										value={cPhone}
										onChangeText={setCPhone}
										keyboardType="phone-pad"
									/>
									<Input
										placeholder="Email"
										value={cEmail}
										onChangeText={setCEmail}
										keyboardType="email-address"
										autoCapitalize="none"
									/>
									<Button
										disabled={cSubmitting || !cName.trim()}
										onPress={() => void submitContact()}
									>
										<Text>{cSubmitting ? "Saving…" : "Save Contact"}</Text>
									</Button>
								</View>
							</View>
						) : null}
					</View>
				) : null}

				{tab === "Engagements" ? (
					<View>
						<H2 className="mb-3">Engagements</H2>
						{engagements.map((e) => (
							<View key={e.id} className="py-2 border-b border-border">
								<Small className="text-muted-foreground">
									{new Date(e.created_at).toLocaleString()}
								</Small>
								<P className="mt-1">{e.body}</P>
							</View>
						))}
						{engagements.length === 0 ? (
							<Muted className="mb-3">No engagements yet.</Muted>
						) : null}

						{canUGC ? (
							<View className="mt-4">
								<H3 className="mb-2">Add Note</H3>
								<Input
									placeholder="Write a note"
									value={eBody}
									onChangeText={setEBody}
									multiline
								/>
								<View className="mt-2 flex-row gap-x-3">
									<Button
										disabled={eSubmitting || !eBody.trim()}
										onPress={() => void submitEngagement()}
									>
										<Text>{eSubmitting ? "Saving…" : "Save Note"}</Text>
									</Button>
								</View>
							</View>
						) : null}
					</View>
				) : null}

				{tab === "Attachments" ? (
					<View>
						<H2 className="mb-3">Attachments</H2>
						{attachments.map((a) => {
							const isImage = (a.content_type || "").startsWith("image/");
							const isPdf = a.content_type === "application/pdf";
							return (
								<View
									key={a.id}
									className="py-3 border-b border-border flex-row items-center gap-x-3"
								>
									<View className="w-12 h-12 rounded-md overflow-hidden bg-muted items-center justify-center">
										{isImage ? (
											// Best-effort signed URL (may fail if policies deny); silently fallback to icon
											<SignedImage objectName={a.object_name} />
										) : (
											<Ionicons
												name={
													isPdf
														? Platform.OS === "ios"
															? "document-text-outline"
															: "document-text"
														: Platform.OS === "ios"
															? "document-outline"
															: "document"
												}
												size={24}
												color="currentColor"
											/>
										)}
									</View>
									<View className="flex-1">
										<Text className="font-medium" numberOfLines={1}>
											{a.object_name.split("/").slice(-1)[0]}
										</Text>
										<Small className="text-muted-foreground">
											{a.content_type || "application/octet-stream"} ·{" "}
											{a.size_bytes ? formatBytes(a.size_bytes) : "-"}
										</Small>
									</View>
								</View>
							);
						})}
						{attachments.length === 0 ? (
							<Muted>No attachments yet.</Muted>
						) : null}

						{ENABLE_ATTACHMENTS_UPLOAD && canUGC ? (
							<View className="mt-4">
								<Button
									disabled={uploading}
									onPress={() => void pickAndUpload()}
								>
									<Text>{uploading ? "Uploading…" : "Upload File"}</Text>
								</Button>
							</View>
						) : null}
					</View>
				) : null}
			</ScrollView>
		</SafeAreaView>
	);
}

function formatBytes(n: number): string {
	if (n < 1024) return `${n} B`;
	const kb = n / 1024;
	if (kb < 1024) return `${kb.toFixed(1)} KB`;
	const mb = kb / 1024;
	return `${mb.toFixed(2)} MB`;
}

/**
 * Best-effort signed URL preview for images.
 * Falls back to icon if createSignedUrl fails or returns no URL.
 */
function SignedImage({ objectName }: { objectName: string }) {
	const [url, setUrl] = useState<string | null>(null);
	useEffect(() => {
		let mounted = true;
		(async () => {
			try {
				const { data, error } = await supabase.storage
					.from("attachments")
					.createSignedUrl(objectName, 60);
				if (!error && data?.signedUrl && mounted) {
					setUrl(String(data.signedUrl));
				}
			} catch {
				// ignore
			}
		})();
		return () => {
			mounted = false;
		};
	}, [objectName]);

	if (!url) {
		return (
			<View className="w-12 h-12 items-center justify-center">
				<Ionicons
					name={Platform.OS === "ios" ? "image-outline" : "image"}
					size={24}
					color="currentColor"
				/>
			</View>
		);
	}
	return <Image source={{ uri: url }} className="w-12 h-12" />;
}
