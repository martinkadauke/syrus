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

**One intentional exception, left for a product call:**
`routes/chat/messageDisplay.ts#formatMessageTimestamp` — the chat message-bubble
timestamp is a **hybrid** (relative for the last 24h, then clock time / date for
older messages, e.g. `3/5 2:32pm`). That's a deliberate chat UX distinct from
"3 days ago". **Want the chat bubbles uniformly relative too?** Say so and I'll
switch it. Non-timestamp `Intl`/`toLocaleString` uses were left alone on purpose
(`BuildBadge` version label, rate-limit numbers, snapshot names).

---

## 2. `inputClass` — form-input styling drift

The visually-identical copies (blue vs terracotta outline, which render the same
via the `blue → terracotta` remap in `config/tailwind.config.js`) were already
merged into `app/frontend/lib/formClasses.ts`:

```ts
// canonical — 6 files now import this
export function inputClass() {
  return "block w-full rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-900 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 shadow-sm focus:outline-terracotta-600"
}
```

Two other groups differ in ways you'd actually see. Diff against the canonical:

`routes/RepositoryForm.tsx`, `routes/ScheduledTasks.tsx` — **darker border**
(`gray-700` vs canonical `gray-600`) and an extra placeholder color:
```ts
function inputClass() {
  return "block w-full rounded border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 dark:placeholder:text-gray-500 shadow-sm focus:outline-blue-600"
}
//                                       ^^^^^^^^^^^^^^^^ gray-700            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ + placeholder color
```

`routes/DirectJobNew.tsx`, `routes/EpicForm.tsx` — **darker background**
(`dark:bg-gray-950` vs canonical `gray-900`), `gray-700` border, placeholder:
```ts
function inputClass() {
  return "block w-full rounded border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:outline-blue-600 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100 dark:placeholder:text-gray-500"
}
//                                                                                                                              ^^^^^^^^^^^^^^ gray-700  ^^^^^^^^^^^^^ gray-950 (near-black)
```

So in dark mode: canonical inputs have a slightly lighter border and a
`gray-900` background with no styled placeholder; these two groups use a darker
border, and `DirectJobNew`/`EpicForm` sit on a near-black `gray-950` field.

**Question:** which is the canonical form-input look — the lighter
`gray-600`/`gray-900` (current shared helper) or the darker
`gray-700`/`gray-950` with the muted placeholder? Pick one and I'll migrate the
remaining four forms into `lib/formClasses`.

---

## 3. `formatCurrency` — precision differs

`routes/jobDetail/formatting.ts` — **2 decimals**:
```ts
export function formatCurrency(value: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value)
}
// $1.20
```

`routes/chat/utils.ts`, `routes/dashboard/helpers.ts` — **4 decimals** (default):
```ts
export function formatCurrency(value: number, digits = 4) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value)
}
// $1.2000  (or $0.0034 for a small agent/token cost)
```

The 4-decimal form shows fine-grained agent/token costs (`$0.0034`); the
2-decimal form is for coarser dollar totals. Merging naively would either drop
precision on token costs or render `$1.2000` on a summary. This looks
intentional.

**Question:** keep two, but rename for intent (e.g. `formatCost` for the
4-decimal fine-grained one, `formatCurrency` for the 2-decimal total)? Or
standardize on one precision?

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
