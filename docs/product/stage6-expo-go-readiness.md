# Stage 6 — Expo Go Readiness Review and Remediation Plan

Scope
- Assess Stage 6 implementation for Expo Go readiness and PRD/spec alignment
- Identify blockers, gaps, and polish items with concrete remediation steps
- Provide a go/no‑go checklist and mapping to tracker acceptance

Primary sources
- Tracker Stage 6: [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md)
- List screen: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Detail screen: [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx)
- Keyset helper: [lib/keyset-pagination.ts](lib/keyset-pagination.ts)
- Feature flags: [lib/useFeatures.ts](lib/useFeatures.ts)
- Haptics wrapper: [lib/haptics.ts](lib/haptics.ts)
- Reduced Motion: [lib/useReducedMotion.ts](lib/useReducedMotion.ts)
- Supabase config: [config/supabase.ts](config/supabase.ts)

Executive summary
- Overall Stage 6 alignment is strong: list/detail, keyset pagination, chip overflow, deep links, UGC under RLS, attachments with metadata‑then‑upload, analytics surface, iPhone‑first touches, token‑only primitives.
- Expo Go blockers identified:
  - Unsupported native module usage for iOS context menu in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
  - Missing Expo dependency [typescript.expo-haptics](lib/haptics.ts:35)
  - Required environment variables for Supabase must be present at runtime in [config/supabase.ts](config/supabase.ts)
- Spec gaps:
  - Infinite scroll is not implemented (Load more button present)
  - Reduced Motion hook is available but not applied to animations and transitions
  - Global UI/UX Steering adoption (outside Projects) remains unchecked in the tracker

Severity‑ranked issues and remediation

High severity (blocks Expo Go or critical runtime)
1) Native iOS context menu (unsupported in Expo Go)
- Where:
  - Import in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
  - Usage around share action: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Impact:
  - Expo Go will fail to resolve the native module.
- Remediation:
  - Remove the import and wrapper usage for Expo Go. Provide a simple long‑press or overflow tap that calls Share.share directly on both platforms.
  - Optionally reintroduce a dynamic import guarded by a custom dev client after Expo Go validation.
- Deployment notes:
  - Source changes:
    - Removed unsupported native module import and wrapper; replaced with a cross‑platform long‑press handler that calls Share.share on each row in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx).
    - List rendering converted to FlatList; long‑press is now available on both iOS and Android.
  - Test:
    - Run the app in Expo Go (iOS). Long‑press any Project row; the system share sheet should open with deep link omnivia://projects/{stage_application}.
    - Verify no module resolution error for react-native-ios-context-menu appears in Metro logs.

2) Missing expo-haptics dependency used by [typescript.haptics](lib/haptics.ts:1)
- Where:
  - [lib/haptics.ts](lib/haptics.ts) dynamically imports expo‑haptics before falling back to react-native-haptic-feedback
- Impact:
  - Metro cannot resolve expo-haptics import during bundling; Expo Go cannot use the native fallback either.
- Remediation:
  - Install expo‑haptics (Expo SDK 53 aligned) and keep the import order:
    - yarn: expo install expo-haptics
  - Continue preferring [typescript.expo-haptics](lib/haptics.ts:35); fallback is for custom dev clients.
- Deployment notes:
  - Package change:
    - Added dependency "expo-haptics" to [package.json](package.json).
  - Install locally (choose one):
    - Yarn (recommended): yarn add expo-haptics@~14.1.4
    - Expo (auto‑resolution): npx expo install expo-haptics
    - npm: npm i -S expo-haptics@~14.1.4
  - Test:
    - Start the app; trigger interactions that call haptics (e.g., toggle Sort, press status chips, submit forms). No “Cannot resolve module expo-haptics” errors should appear.
    - Run npx expo-doctor to confirm dependency health.

3) Environment variables for Supabase required at runtime
- Where:
  - [config.supa url/key checks](config/supabase.ts) and [typescript.createClient](config/supabase.ts:25)
- Impact:
  - Missing EXPO_PUBLIC_SUPABASE_URL or EXPO_PUBLIC_SUPABASE_ANON_KEY will crash on launch.
- Remediation:
  - Ensure .env contains:
    - EXPO_PUBLIC_SUPABASE_URL=...
    - EXPO_PUBLIC_SUPABASE_ANON_KEY=...
  - Confirm Expo reads env and values are present before calling [typescript.createClient()](config/supabase.ts:25).
- Deployment notes:
  - Status:
    - Confirmed present in [.env](.env): EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY exist and match the current Supabase project.
    - Runtime validation remains enforced in [config/supabase.ts](config/supabase.ts) and will throw if missing.
  - Test:
    - npx expo start (Metro). App should launch without "Missing EXPO_PUBLIC_*" errors.
    - In development, [config/supabase.ts](config/supabase.ts) logs a non‑secret validity hint: “[Supabase] URL valid: true”.

Medium severity (functional alignment and UX)
4) Infinite scroll not implemented (spec requires it)
- Where:
  - Load more button at [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Spec:
  - Stage 6 list acceptance includes infinite scroll.
- Remediation:
  - Convert to FlatList with onEndReached calling the same loader that uses [typescript.applyProjectsKeyset()](lib/keyset-pagination.ts:104). Preserve sort/filter/search and keep chip overflow policy.
- Deployment notes:
  - Source changes:
    - Replaced manual map + "Load more" button with FlatList + onEndReached in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx).
    - Uses [typescript.applyProjectsKeyset()](lib/keyset-pagination.ts:104) with PAGE_SIZE for consistent ordering and cursor advancement.
  - Test:
    - Apply optional search or status filters. Scroll to the end; additional pages should load automatically until hasMore is false.
    - Verify analytics events continue to fire for list_viewed, project_opened, filter_applied, search_submitted.

5) Reduced Motion not applied to animations
- Where:
  - Hook is read in list screen [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx), but not driving transitions.
- Spec:
  - Swap animations to instant/fades when [typescript.useReducedMotion()](lib/useReducedMotion.ts:10) is true; adjust bottom sheet interactions and any reanimated transitions.
- Remediation:
  - For bottom sheet opening/closing, minimize or disable animations under reduced motion.
  - For screen transitions, prefer no animation or fade when reduced motion is on.
- Deployment notes:
  - Source changes:
    - Applied reduced‑motion guard to Stack.Screen transitions (animation: "none") in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx) and [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx).
    - Minimized BottomSheet motion by setting short animationConfigs and disabling handle/content panning gestures when reduced motion is enabled in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx).
  - Test:
    - Enable OS Reduce Motion (iOS: Settings → Accessibility → Motion; Android: Developer options → Remove animations / Accessibility settings).
    - Navigate list → detail and open/close Filters. Transitions should be instant or significantly reduced.

6) iPhone‑first safeguards and Android parity
- Where:
  - Large title set at [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
  - Gesture disabled when sheet open at [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
  - Bottom sheet configured at [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Remediation:
  - Confirm a11y labels for sheet controls and chip overflow actions.
  - Validate minimum 48 dp targets (button sizing in [components/ui/button.tsx](components/ui/button.tsx) suggests compliance).
- Deployment notes:
  - Source changes:
    - Added explicit accessibilityLabel/Hint to Sort toggle and to Filters sheet actions ("Clear" / "Apply") in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx).
    - Chip overflow "Filters" control already labeled in [components/projects/ChipRow.tsx](components/projects/ChipRow.tsx).
    - Button sizes remain compliant per [components/ui/button.tsx](components/ui/button.tsx).
  - Test:
    - VoiceOver (iOS) / TalkBack (Android): navigate to Sort and Filters actions; labels and hints should read correctly. Touch targets meet 48dp guidance.

Low severity (polish / compatibility)
7) Ionicons color set to "currentColor"
- Where:
  - PDF/file icon color in [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx)
- Impact:
  - RN color expects a resolved color; "currentColor" may not apply as intended.
- Remediation:
  - Pass a token color or omit color prop to use default theme text color.

8) "Oldest" sort path not using keyset
- Where:
  - ASC sorting path at [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Impact:
  - Acceptable for small slices; keyset preferred at scale.
- Remediation:
  - Optionally add mirrored keyset logic later.

Spec conformance mapping (selected items)
- Keyset pagination
  - [typescript.applyProjectsKeyset()](lib/keyset-pagination.ts:104) used; ordering aligns with [docs/sql/stage6-keyset-verify.sql](docs/sql/stage6-keyset-verify.sql)
- Chip overflow policy
  - [typescript.ChipRow](components/projects/ChipRow.tsx:13) renders up to 5 chips plus "Filters"; bottom sheet at [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Attachments flow (25 MB cap; metadata ➜ upload)
  - Cap check at [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx)
  - Metadata insert at [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx)
  - Path update and storage upload at [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx) and [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx)
- Authorization helpers
  - [typescript.canViewProjects()](lib/authz.ts:62), [typescript.canCreateUGC()](lib/authz.ts:75) used to gate CTAs and module exposure
- Deep links
  - Share deep link usage in [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
  - Direct route: [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx)
- Analytics instrumentation
  - [typescript.track()](lib/analytics.ts:48) emits list_viewed, search_submitted, filter_applied, project_opened, engagement_added, attachment_uploaded, contact_added

Expo Go go/no‑go checklist
- Dependencies
  - Install: expo‑haptics (Expo SDK 53 aligned). Reference: [typescript.haptics](lib/haptics.ts:1)
  - Reanimated plugin present and last: [babel.config.js](babel.config.js) — confirmed
  - Gesture handler side‑effect import present: [app/_layout.tsx](app/_layout.tsx) — confirmed
- Remove/guard unsupported native modules
  - Remove "react-native-ios-context-menu" import and usage for Expo Go: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Environment variables (must exist)
  - [config.supa URL/key checks](config/supabase.ts)
  - Required:
    - EXPO_PUBLIC_SUPABASE_URL=...
    - EXPO_PUBLIC_SUPABASE_ANON_KEY=...
- Smoke checks
  - npx expo-doctor
  - expo start (or yarn start)

Recommended follow‑ups (spec completeness)
- Implement infinite scroll (FlatList with onEndReached), preserving [typescript.applyProjectsKeyset()](lib/keyset-pagination.ts:104)
- Apply Reduced Motion behavior to bottom sheet and screen transitions with [typescript.useReducedMotion()](lib/useReducedMotion.ts:10)
- Address Global UI/UX Steering adoption tasks in the tracker (outside Projects) if required for Stage 6 acceptance; currently unchecked in [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md)

Appendix — References
- Tracker (Stage 6): [docs/product/projects-okta-rbac-implementation-tracker.md](docs/product/projects-okta-rbac-implementation-tracker.md)
- List screen: [app/(protected)/(tabs)/projects/index.tsx](app/(protected)/(tabs)/projects/index.tsx)
- Detail screen: [app/(protected)/projects/[stage_application].tsx](app/(protected)/projects/[stage_application].tsx)
- Keyset: [typescript.applyProjectsKeyset()](lib/keyset-pagination.ts:104)
- Haptics: [typescript.selection()](lib/haptics.ts:98), [typescript.success()](lib/haptics.ts:101), [typescript.warning()](lib/haptics.ts:104), [typescript.error()](lib/haptics.ts:107), [typescript.destructive()](lib/haptics.ts:110)
- Reduced Motion: [typescript.useReducedMotion()](lib/useReducedMotion.ts:10)
- Features: [lib/useFeatures.ts](lib/useFeatures.ts)
- Supabase env checks: [config/supabase.ts](config/supabase.ts)