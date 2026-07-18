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

## 1. `formatDate` — inconsistent date rendering across the SPA

After consolidating the identical `null → "-"; toLocaleString()` copies into
`lib/format.ts`, these distinct variants remain. They disagree on **three
independent axes**: output format, locale, and the missing-value placeholder.

### The canonical the identical copies were merged into
```ts
// app/frontend/lib/format.ts
export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "-"
  return new Date(value).toLocaleString()
}
// renders e.g. "1/5/2026, 3:45:12 PM" (viewer locale, full OS style), "-" when missing
```

### The variants still in the wild

`routes/Profile.tsx` — **hard-coded en-US**, missing → `"unknown"`, and `Intl`
medium+short (a *different* string than `toLocaleString`):
```ts
function formatDate(value: string | null) {
  if (!value) return "unknown"

  return new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
}
// renders e.g. "Jan 5, 2026, 3:45 PM" — always en-US even for a German/Latin viewer; "unknown" when missing
```

`routes/Profiles.tsx` — **compact month/day only**, missing → `"not started"`:
```ts
function formatDate(value: string | null) {
  if (!value) return "not started"
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(new Date(value))
}
// renders e.g. "Jan 5" (no year, no time); "not started" when missing
```

`routes/Search.tsx` — compact month/day, missing/invalid → `""` (empty):
```ts
function formatDate(value: string) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ""
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(date)
}
// renders e.g. "Jan 5"; empty string on a bad date
```

`routes/RepositoryDetail.tsx` — hard-coded en-US, no missing-value guard:
```ts
function formatDate(value: string) {
  return new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
}
```

`routes/Memories.tsx` — viewer locale, `Intl` medium+short, no guard:
```ts
function formatDate(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
}
```

### Summary
| File | Format | Locale | Missing value |
|---|---|---|---|
| `lib/format.ts` `formatDateTime` (canonical, 7 files) | `toLocaleString()` | viewer | `"-"` |
| `lib/format.ts` `formatDateTimeOrNull` (2 files) | `toLocaleString()` | viewer | `null` |
| `Memories.tsx` | `Intl` medium+short | viewer | (none) |
| `RepositoryDetail.tsx` | `Intl` medium+short | **en-US** | (none) |
| `Profile.tsx` | `Intl` medium+short | **en-US** | `"unknown"` |
| `Profiles.tsx` | `Intl` **month+day** | viewer | `"not started"` |
| `Search.tsx` | `Intl` **month+day** | viewer | `""` |

**Questions**
- **Locale:** should everything use the viewer's locale? The two hard-coded
  `en-US` sites (`Profile`, `RepositoryDetail`) look like oversights given the
  app has en/de/la i18n — a German viewer sees English dates there today.
- **Compact vs full:** `Profiles`/`Search` show `"Jan 5"` (no year/time) — a
  deliberate dense-list choice? If so it should become a second canonical
  `formatShortDate`, not fold into the full one.
- **Missing text:** `"-"` vs `"unknown"` vs `"not started"` vs `""` vs `null`.
  `"not started"` for an unstarted profile run is arguably better UX than `"-"`.

**Simplest unification I'd propose:** one `formatDateTime` (viewer locale, `Intl`
medium+short, `"-"` missing) + one `formatShortDate` (viewer locale, month+day,
`"-"` missing). Say go and I'll migrate all seven and fix any tests that assert
the old strings.

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
