# Omnivia Branding & Front-End Steering Document
Version: 1.0
Scope: iOS-first, Light and Dark themes, SF Symbols, 44pt touch targets, placeholder wordmark

References:
- Tokens and CSS vars: [global.css](global.css:6), [constants/colors.ts](constants/colors.ts:6), [tailwind.config.js](tailwind.config.js:7)
- Core components: [typescript.buttonVariants()](components/ui/button.tsx:7), [typescript.Button](components/ui/button.tsx:65), [typescript.Input](components/ui/input.tsx:5), [typescript.Switch](components/ui/switch.tsx:99), [typescript.RadioGroup](components/ui/radio-group.tsx:6), [typescript.Form primitives](components/ui/form.tsx:21), [typescript.Typography](components/ui/typography.tsx:1), [typescript.Text](components/ui/text.tsx:1)
---

0. Purpose, scope, and design principles
- Audience: designers, iOS engineers, PMs
- Omnivia personality: professional, corporate, trustworthy, approachable
- Mobile-first, iOS-first execution; desktop/web parity follows later
- Principles: clarity over ornament; consistent tokens; stateful feedback; predictable interactions; accessible by default

1. Brand positioning and tone of voice
- Tone: confident, succinct, action-oriented
- Microcopy: avoid jargon; prefer verbs (“Assign”, “Archive”) and plain-language confirmations (“Project added”)
- Errors: explain what happened + how to resolve (“Sync failed — check your connection and retry”)
- Empty states: helpful, minimal; show next action; avoid “no data” without guidance
- Toasts: short, single action max; auto-dismiss after 3–4s unless destructive

2. Color system and tokens
2.1 Core palette (Hex)
- Primary Navy: #1B2A49
- Secondary Beige: #F5F0E6
- Accent Blue (links/highlights): #3B82F6
- Semantic: Success #2E7D32, Warning #B45309, Error #B91C1C, Info #2563EB
- Neutrals (text, dividers): derived from navy-tinted grays

2.2 Token definitions (Light mode — HSL numeric values for CSS)
Set in [global.css](global.css:6) under :root:
- --background: 40 43% 93% (Secondary Beige #F5F0E6)
- --foreground: 220 28% 16% (Deep slate-navy for default text)
- --card: 0 0% 100% (White)
- --card-foreground: 220 28% 16%
- --popover: 0 0% 100%
- --popover-foreground: 220 28% 16%
- --primary: 220 46% 20% (Primary Navy #1B2A49)
- --primary-foreground: 0 0% 100% (On-primary text)
- --secondary: 40 35% 88% (Beige surface-2)
- --secondary-foreground: 220 28% 16%
- --muted: 40 30% 86% (Beige muted)
- --muted-foreground: 220 12% 40%
- --accent: 217 91% 60% (Accent Blue #3B82F6)
- --accent-foreground: 0 0% 100%
- --success: 123 46% 34% (#2E7D32)
- --warning: 26 91% 37% (#B45309)
- --info: 221 83% 53% (#2563EB)
- --destructive: 0 74% 42% (#B91C1C)
- --destructive-foreground: 0 0% 100%
- --border: 220 20% 80% (Navy-tinted divider)
- --input: 220 20% 80%
- --ring: 217 91% 60% (Accent halo)

2.3 Token definitions (Dark mode — HSL numeric values for CSS)
Set in [global.css](global.css:28) under .dark:root:
- --background: 220 42% 10% (Brand-true dark navy)
- --foreground: 0 0% 98%
- --card: 220 42% 12%
- --card-foreground: 0 0% 98%
- --popover: 220 42% 12%
- --popover-foreground: 0 0% 98%
- --primary: 220 46% 60% (Lightened navy for filled controls on dark)
- --primary-foreground: 240 6% 10%
- --secondary: 220 28% 18%
- --secondary-foreground: 0 0% 98%
- --muted: 220 20% 20%
- --muted-foreground: 220 10% 70%
- --accent: 217 91% 60%
- --accent-foreground: 0 0% 100%
- --success: 123 46% 45%
- --warning: 26 91% 55%
- --info: 221 83% 62%
- --destructive: 0 62% 50%
- --destructive-foreground: 0 86% 97%
- --border: 220 20% 23%
- --input: 220 20% 23%
- --ring: 217 91% 60%

2.4 Usage rules
- Primary Navy: branding, primary actions, active indicators
- Secondary Beige: backgrounds and secondary surfaces; avoid overly large beige blocks next to cards — prefer beige background with white cards
- Accent Blue: links, focus halos, selected states; avoid competing with Primary Navy in the same control
- Semantic colors: success/warning/error/info in badges, toasts, validation; do not use as default text colors
- Contrast: ensure body text 4.5:1 minimum; large text 3:1 minimum; icons 3:1 minimum when semantic

2.5 Implementation notes
- CSS variables: define the HSL numbers above in [global.css](global.css:6) and [.dark:root](global.css:28)
- React Native color map: keep HSL strings synchronized in [constants/colors.ts](constants/colors.ts:6) for light/dark; if adding semantic colors on native, create a parallel semanticColors map rather than modifying the existing colors object which is consumed by tabs
- Tailwind tokens: extend theme to include success, warning, info alongside existing tokens in [tailwind.config.js](tailwind.config.js:7-44). Keys:
  - success.DEFAULT hsl(var(--success)); success.foreground hsl(var(--foreground))
  - warning.DEFAULT hsl(var(--warning)); warning.foreground hsl(var(--foreground))
  - info.DEFAULT hsl(var(--info)); info.foreground hsl(var(--foreground))
- Focus ring: set ring color to accent by default; respect prefers-reduced-motion on web

3. Typography
3.1 Families and weights
- iOS: SF Pro Text/Display (system default); Weights: Regular 400, Medium 500, Semibold 600, Bold 700
- Android/Web fallback (future): platform system UI font stack

3.2 Type scale and roles (points, iOS)
- H1: 34/41, Bold (hero, screen title)
- H2: 28/34, Semibold (section title)
- H3: 22/28, Semibold
- H4: 17/22, Semibold
- Body: 17/22, Regular (default)
- Subhead: 15/20, Regular
- Caption: 13/18, Regular
- Small/Overline: 12–13/16–18, Medium
- Button: 17/22, Medium (all-caps not required)

3.3 Implementation mapping
- Adjust text classes in headings in [typescript.H1()](components/ui/typography.tsx:7), [typescript.H2()](components/ui/typography.tsx:27), [typescript.H3()](components/ui/typography.tsx:47), [typescript.H4()](components/ui/typography.tsx:67) to align with the sizes above
- Base text class in [typescript.Text()](components/ui/text.tsx:9) remains the default Body; avoid shrinking below 15pt for dense data
- Button text comes from [typescript.buttonTextVariants()](components/ui/button.tsx:35); ensure default/large sizes map to 17pt and 19–20pt on native

4. Core UI components
4.1 Buttons ([typescript.buttonVariants()](components/ui/button.tsx:7), [typescript.Button()](components/ui/button.tsx:65))
- Variants:
  - Primary: bg=primary, text=primary-foreground
  - Secondary: bg=secondary, text=secondary-foreground
  - Outline: bg=background, border=input, text=foreground; pressed bg=accent (10–12% opacity), text=accent-foreground
  - Ghost: transparent; pressed bg=accent (10–12% opacity)
  - Link: color=accent; underline on focus/active (web)
  - Destructive: bg=destructive, text=destructive-foreground
- States:
  - Hover (web): opacity 90% (primary/secondary/destructive)
  - Pressed: opacity 90% or bg darken by 4–6 L
  - Focus: ring=accent, 2px (web)
  - Disabled: opacity 50%, no interaction
  - Loading: reserve space for spinner at start; do not change label width
- Dimensions:
  - Min size: 44x44pt hit area
  - Corners: md radius (iOS-friendly rounded)
  - Spacing: default h=48pt native, px=16–20; large h=56pt native
- Icon buttons:
  - Icon leading spacing 8–12pt; icon-only uses size=icon with explicit accessible label

4.2 Inputs and forms ([typescript.Input()](components/ui/input.tsx:5), [typescript.Form()](components/ui/form.tsx:21), [typescript.FormInput()](components/ui/form.tsx:177), [typescript.FormMessage()](components/ui/form.tsx:133))
- Field background: background
- Border: input; focus ring: ring=accent
- Placeholder: muted-foreground
- Helper: muted-foreground; Error: destructive (announce to VoiceOver)
- Validation: inline message below field; avoid only-color cues; include icons for status if needed
- Required fields: indicate in label; do not rely on placeholder
- Disabled/read-only: 50% opacity; cursor-not-allowed on web
- Density: default comfortable; stacked labels above fields

4.3 Switches and radios ([typescript.Switch()](components/ui/switch.tsx:99), [typescript.RadioGroup()](components/ui/radio-group.tsx:6))
- Switch on: track bg=primary (web) / interpolated to primary (native), thumb bg=background; off: track bg=input
- Radio item: border=text-primary; dot bg=primary; disabled reduces opacity
- Haptic: selection when toggling switch or selecting radio

4.4 Cards
- Surfaces: card on beige background; white cards with subtle shadow/elevation
- Spacing: 16–20pt padding; 12–16pt between header, content, actions
- Header: title (H4), optional metadata (Small)
- Footer: use buttons or text links; avoid dense clusters

4.5 Modals and sheets
- Full-screen: tasks requiring multi-step forms or navigation
- Page sheet (card-style): quick edits, confirmations; drag-to-dismiss with clear affordance
- Scrim: 40–50% opacity; avoid colored scrims
- Destructive confirmations: use destructive color for primary action

4.6 Chips/Tags
- Shapes: pill; 18–24pt height; 12pt min hit target if interactive
- Status colors: success/warning/error/info backgrounds at 12–16% opacity; text at strong semantic color
- Icons: optional leading SF Symbol

4.7 Tables/Lists (mobile-first)
- Prefer lists with clear separators; 56–64pt row height default; multi-line subtitle allowed
- Metadata right-aligned or secondary line; avoid more than three columns
- Use swipe actions for secondary/tertiary commands

5. iOS-specific patterns
5.1 Navigation
- Large titles at root screens; inline titles on deeper levels
- Back gestures: edge-swipe to go back; do not block with full-width gestures unless critical
- Tab bar: 3–5 tabs; active tint uses foreground; background uses brand background via [typescript.Tabs()](app/(protected)/(tabs)/_layout.tsx:1)

5.2 Safe areas
- Respect notches and home indicator using [typescript.SafeAreaView()](components/safe-area-view.tsx:1); avoid content under indicators unless scrollable with insets

5.3 Standard controls
- Use native pickers where possible; segmented controls for 2–3 options; switches for binary states

5.4 Gestures
- List row swipe:
  - Left swipe: primary actions (Delete [destructive], Archive [muted], More [accent])
  - Ensure actions have icons and labels; haptic on commit

5.5 Modals
- PageSheet for short tasks; drag-dismiss allowed unless destructive or unsaved changes
- FullScreen for multistep flows; provide explicit Close/Back

5.6 Haptics
- Selection: light on toggles, segmented controls
- Success: success haptic on completion
- Warning/Error: warning/error haptic on failures
- Avoid overuse; one haptic per user action

5.7 Touch targets
- 44x44pt minimum; surround small icons with invisible padding

6. Iconography and imagery
6.1 SF Symbols
- Use outlined/monoline style to match UI weight
- Rendering modes: single-color; tint with foreground or semantic; avoid multicolor unless explicit
- Sizes: 17–24pt depending on control size; match button text size visually

6.2 Imagery
- Style: operations, people, telecom infrastructure; natural light; subtle beige overlays allowed
- Avoid overly saturated or stocky visuals; keep brand coherence

7. Layout and spacing rules
- Grid: 4pt baseline
- Page padding: 16pt
- Section spacing: 16/24/32pt depending on hierarchy
- Dividers: 1px hairline using border token; avoid heavy borders
- Elevation: minimal shadows on iOS (1–3 levels); prefer contrast via surface color

8. Accessibility
- Contrast: body text ≥ 4.5:1; large text/icons ≥ 3:1; test semantic on beige
- VoiceOver: ensure labels, hints, and traits on [typescript.Button()](components/ui/button.tsx:65), [typescript.Input()](components/ui/input.tsx:5), form controls; maintain logical focus order
- Dynamic Type: support content size categories; wrap rather than truncate where possible; reserve vertical space in cards
- Reduced motion: respect platform settings; minimize animated transitions on web/native
- Web parity: use ARIA roles/labels; the codebase already sets aria- props in [typescript.FormInput()](components/ui/form.tsx:177) and [typescript.FormMessage()](components/ui/form.tsx:133)

9. Branding consistency
- Use Primary Navy for primary actions, active states, and key brand surfaces; use Beige as base background or secondary surfaces
- Maintain the typography hierarchy; avoid mixing more than two sizes in a single region
- Component variants: prefer primary/secondary; outline for low-emphasis actions; ghost for icon affordances; destructive for irreversible actions only

10. Examples (spec, mobile-first)
- Primary Button (default): bg primary; text white; ring accent; pressed opacity 90%; min 44pt height; leading icon optional
- Secondary Button: bg secondary; text secondary-foreground; pressed darken by 4–6 L
- Outline Button: bg background; border input; pressed bg accent 10–12% opacity; text foreground
- Input (text): bg background; border input; focus ring accent; placeholder muted-foreground; helper muted; error destructive
- Card: page bg beige; card bg white; 16pt padding; subtle shadow; header H4; actions in footer
- Modal (PageSheet): 24pt content margins; drag handle visible; primary/destructive actions bottom
- Chip (Status=Success): bg success @ 16% opacity; text success at full

11. Implementation checklist (targeting current codebase)
- CSS variables
  - Update :root and .dark:root in [global.css](global.css:6) with the HSL numbers in sections 2.2 and 2.3
- React Native color map
  - In [constants/colors.ts](constants/colors.ts:6), adjust light/dark HSL strings to match the tokens (primary, secondary, accent, destructive, border, input, ring, etc.). For semantics (success/warning/info), create a separate semanticColors map consumed by components that need semantic styling
- Tailwind tokens
  - Extend [tailwind.config.js](tailwind.config.js:7-44) colors with success, warning, info keys mirroring the CSS variables (DEFAULT + foreground)
- Components
  - Buttons: confirm [typescript.buttonVariants()](components/ui/button.tsx:7) uses bg-primary/secondary/… and pressed/hover states per spec
  - Inputs: confirm [typescript.Input()](components/ui/input.tsx:5) uses border=input, ring=ring, placeholder=muted-foreground
  - Forms: confirm error styles in [typescript.FormMessage()](components/ui/form.tsx:133) use destructive and announce
  - Switch/Radio: ensure selected/on states use primary; disabled opacity 50%
  - Typography: adjust sizes in [typescript.H1()](components/ui/typography.tsx:7) … [typescript.Small()](components/ui/typography.tsx:178) to the scale above
- Navigation and tabs
  - Tab bar colors are drawn from [constants/colors.ts](constants/colors.ts:6) within [typescript.Tabs()](app/(protected)/(tabs)/_layout.tsx:1); after updating constants, verify dark/light parity
- Safe area
  - Wrap screens with [typescript.SafeAreaView()](components/safe-area-view.tsx:1) to respect notches/home indicator
- QA checklist
  - Light/Dark parity; contrast checks; Dynamic Type; VoiceOver labels; focus rings on web; haptics on key actions

12. Sign-off criteria
- Visual QA across iPhone sizes (SE, 13 mini/regular/Pro Max)
- Contrast verified for core surfaces and text on beige and dark navy
- Token audit: CSS vars, Tailwind colors, RN constants in sync
- Interactive states confirmed for all button variants and form controls
- Accessibility audit complete; no blockers

Appendix A — Token copy sheet (Light)
- background: 40 43% 93%
- foreground: 220 28% 16%
- card: 0 0% 100%
- card-foreground: 220 28% 16%
- popover: 0 0% 100%
- popover-foreground: 220 28% 16%
- primary: 220 46% 20%
- primary-foreground: 0 0% 100%
- secondary: 40 35% 88%
- secondary-foreground: 220 28% 16%
- muted: 40 30% 86%
- muted-foreground: 220 12% 40%
- accent: 217 91% 60%
- accent-foreground: 0 0% 100%
- success: 123 46% 34%
- warning: 26 91% 37%
- info: 221 83% 53%
- destructive: 0 74% 42%
- destructive-foreground: 0 0% 100%
- border: 220 20% 80%
- input: 220 20% 80%
- ring: 217 91% 60%

Appendix B — Token copy sheet (Dark)
- background: 220 42% 10%
- foreground: 0 0% 98%
- card: 220 42% 12%
- card-foreground: 0 0% 98%
- popover: 220 42% 12%
- popover-foreground: 0 0% 98%
- primary: 220 46% 60%
- primary-foreground: 240 6% 10%
- secondary: 220 28% 18%
- secondary-foreground: 0 0% 98%
- muted: 220 20% 20%
- muted-foreground: 220 10% 70%
- accent: 217 91% 60%
- accent-foreground: 0 0% 100%
- success: 123 46% 45%
- warning: 26 91% 55%
- info: 221 83% 62%
- destructive: 0 62% 50%
- destructive-foreground: 0 86% 97%
- border: 220 20% 23%
- input: 220 20% 23%
- ring: 217 91% 60%