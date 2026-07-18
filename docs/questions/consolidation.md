# Consolidation questions — helpers that differ in a user-visible way

During the codebase de-duplication pass, several helpers were found copy-pasted
across many files. The **behaviorally-identical** copies were consolidated into
shared modules (`lib/routing` for `withRoutePrefix`/`routePrefix`, `testSupport`
for `jsonResponse`, `lib/format` for the identical `formatDate` copies,
`lib/formClasses` for the visually-identical `inputClass` copies).

The helpers below were **left un-consolidated on purpose**: their copies differ
in ways a user would actually see, so picking one canonical form is a product/
design decision rather than a mechanical refactor. Each needs a call on which
behavior is correct; once decided, they can be unified the same way.

Every code block below is the **actual current source** from the named file.

---

## 1. Date rendering across the SPA — **RESOLVED: uniform relative time**

Every timestamp now renders as a **localized relative time** ("2 minutes ago" /
"vor 2 Minuten", via `Intl.RelativeTimeFormat`) with the **exact local
timestamp in a hover title**, through one shared component:
`app/frontend/components/RelativeTimestamp.tsx`
(relative string from `lib/relativeTime.ts#formatRelativeDate`):

```tsx
<RelativeTimestamp value={job.updated_at} />
// -> <time datetime="…" title="Jan 5, 2026, 3:45 PM">2 minutes ago</time>
<RelativeTimestamp value={task.last_fired_at} fallback={t("…never")} />  // per-caller empty text
```

~40 call sites across ~25 files were migrated (profiles, admin, scheduled
tasks, repository detail/health/issues, job detail + workflow graph, dashboard
tables, memories, search, epics, hidden chats, chat search, workspace panels,
notifications, …) and all the per-file `formatDate` / `formatRelative` /
`formatDateTime` / `formatRelativeTime` copies were deleted. Where a timestamp
sits inside a translated sentence (`t(…, { date })`) and can't carry the
component, it uses the relative string `formatRelativeDate(new Date(x))`
(localized, no hover).

**One intentional exception — RESOLVED as a localized hybrid:**
`routes/chat/messageDisplay.ts#formatMessageTimestamp` is the chat message-bubble
timestamp. By product decision it keeps its **hybrid** shape (relative for the
first 24h, then an absolute clock/date beyond that — scrollback wants the actual
time), which is distinct from the uniform "3 days ago" everywhere else. What was
fixed: it used to be **hardcoded English + US format** ("5m ago", `3/5 2:32pm`);
now both halves respect the viewer's locale — the relative side via the shared
`formatRelativeDate` (Intl.RelativeTimeFormat), the absolute side via
Intl.DateTimeFormat (`3/5, 2:32 PM` / `05.03., 14:32`). Non-timestamp
`Intl`/`toLocaleString` uses were left alone on purpose (`BuildBadge` version
label, rate-limit numbers, snapshot names).

---

## 2. `inputClass` — **RESOLVED: one shared helper, DirectJobNew look**

There were three visually-distinct variants; we standardized on the darker
`DirectJobNew`/`EpicForm` look (near-black `gray-950` dark field, `gray-700`
dark border, muted `gray-500` placeholder) as the single canonical
`app/frontend/lib/formClasses.ts#inputClass()`:

```ts
export function inputClass() {
  return "block w-full rounded border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:outline-terracotta-600 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100 dark:placeholder:text-gray-500"
}
```

The four hold-out forms (`RepositoryForm`, `ScheduledTasks`, `DirectJobNew`,
`EpicForm`) dropped their local copies and import the shared helper, so every
form input across the SPA now renders identically. The focus outline is named
`terracotta-600` (the old `focus:outline-blue-600` rendered the same via the
`blue → terracotta` remap in `config/tailwind.config.js`, but new code names
terracotta).

---

## 3. `formatCurrency` — **RESOLVED: 4 decimals everywhere**

There were four definitions with different precision (jobDetail 2dp;
SpendingInsights 2dp-if-≥10-else-4dp; chat/utils + dashboard/helpers a
`digits = 4` param) and two call sites passing `, 2`. Consolidated to one
canonical helper in `lib/format.ts`, always **4 decimals** — agent costs are
frequently fractions of a cent, so 2 decimals collapsed distinct runs to the
same `$0.00`:

```ts
// app/frontend/lib/format.ts
export function formatCurrency(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency", currency: "USD",
    minimumFractionDigits: 4, maximumFractionDigits: 4
  }).format(value)
}
// $1.2000, $0.0034
```

`chat/utils.ts`, `dashboard/helpers.ts`, and `jobDetail/formatting.ts` now
re-export it (`export { formatCurrency } from "../../lib/format"`), so their
importers are unchanged; `SpendingInsights.tsx` imports it directly. The
`digits` param and both `, 2` call-site overrides are gone.

---

## 4. Large files whose remainder needs a *behaviour-aware* split, not a mechanical one

Every other oversized file was decomposed by lifting cohesive clusters into leaf
modules/concerns (see git history). Two remain large because what's left is a
single tightly-coupled unit that can't be shattered mechanically without risk:

- **`app/frontend/routes/chat/Compose.tsx` (~1757)** — dominated by one ~1400-line
  `Compose` component. Its slash-command, attachment, draft, MCP-config,
  walkthrough, and remote-suggestion logic share one big web of `useState`/`useRef`
  state and handlers (e.g. a single component owns `draftTree`, attachment
  arrays, walkthrough upload state, slash-command palette state, and their
  interdependent effects). Splitting it means extracting real sub-components with
  a designed prop/callback interface (and probably custom hooks), which is a
  focused refactor, not a cut-and-paste. The six trailing sub-components
  (ReportIssueDialog, SlashCommand*, QueuedMessages, StopButton) *could* move to
  their own file, but they're interleaved with helpers the core still uses and it
  wouldn't touch the 1400-line core — low value for the churn.
- **`app/models/job.rb` (~1092, down from 1483)** — seven concerns were already
  extracted (coding-mode, needs-attention, workflow accessors, cost, stack/base,
  dependencies, execution accessors, lifecycle). What remains is the core AASM
  state machine (`aasm do ... end`), its `before_/after_` callbacks and
  validations, the associations, and the approval methods that *call* the state
  events (`approve!`/`unapprove!` wrappers). Splitting the state machine from its
  guards/callbacks is behaviour-critical, so it was left in one place.

**Question:** do you want either of these taken on as a dedicated, carefully-
tested refactor? They're the last two files over ~1000 lines.
