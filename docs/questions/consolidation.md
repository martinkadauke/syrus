# Consolidation questions — helpers that differ in a user-visible way

During the codebase de-duplication pass, several helpers were found copy-pasted
across many files. The **behaviorally-identical** copies were consolidated into
shared modules (`lib/routing` for `withRoutePrefix`/`routePrefix`, `testSupport`
for `jsonResponse`, `lib/format` for the identical `formatDate` copies).

The helpers below were **left un-consolidated on purpose**: their copies differ
in ways a user would actually see, so picking one canonical form is a product/
design decision rather than a mechanical refactor. Each needs a call on which
behavior is correct; once decided, they can be unified the same way.

---

## 1. `formatDate` — inconsistent date rendering across the SPA

After consolidating the identical `null → "-"; toLocaleString()` copies into
`lib/format.ts#formatDateTime`, these distinct variants remain. They disagree on
**three independent axes**: output format, locale, and the missing-value
placeholder.

| File(s) | Format | Locale | Missing value |
|---|---|---|---|
| `lib/format.ts` (`formatDateTime`, canonical for 7 files) | `toLocaleString()` (full, OS-styled) | viewer | `"-"` |
| `lib/format.ts` (`formatDateTimeOrNull`, canonical for 2 files) | `toLocaleString()` | viewer | `null` (returns null, for callers that render their own fallback) |
| `routes/Memories.tsx` | `Intl` medium date + short time | viewer | (no guard) |
| `routes/RepositoryDetail.tsx` | `Intl` medium date + short time | **en-US** (hard-coded) | (no guard) |
| `routes/Profile.tsx` | `Intl` medium date + short time | **en-US** (hard-coded) | `"unknown"` |
| `routes/Profiles.tsx` | `Intl` **month + day only** (compact) | viewer | `"not started"` |
| `routes/Search.tsx` | `Intl` **month + day only** (compact) | viewer | `""` (empty) + NaN guard |

**Questions:**
- Should dates use the **viewer's locale** everywhere (the app has en/de/la
  i18n, so the two hard-coded `en-US` sites — `Profile`, `RepositoryDetail` —
  look like oversights), or is en-US intentional somewhere?
- Is the **compact month/day** format (`Profiles`, `Search`) a deliberate
  dense-list choice? If so it should become a second canonical
  (`formatShortDate`), not be merged into the full formatter.
- Which **missing-value placeholder** is canonical? Today it's `"-"`,
  `"unknown"`, `"not started"`, `""`, or `null` depending on the file. The
  varied text (`"not started"` for an unstarted run) may be deliberate UX.

**If you want the simplest unification:** viewer-locale, `Intl` medium+short,
`"-"` for missing → one `formatDateTime`; a second `formatShortDate` (month+day,
viewer locale) for the two compact sites. Say the word and I'll migrate + fix
any tests that assert the old strings.

---

## 2. `inputClass` — form-input styling drift

The form-input Tailwind class helper exists in ~10 files in 3 visually-distinct
variants (a 4th differs only by `focus:outline-blue-600` vs
`focus:outline-terracotta-600`, which render **identically** because
`config/tailwind.config.js` remaps `blue` onto the terracotta scale — those are
safe to merge).

The genuine visual differences among the rest:
- **border**: `border-gray-600` (dark) vs `border-gray-700`
- **dark background**: `dark:bg-gray-900` vs `dark:bg-gray-950`
- **placeholder**: some add `dark:placeholder:text-gray-500`, some don't

**Question:** what is the canonical form-input style? Once chosen I'll lift it to
a shared `lib` helper and migrate every form. (The visually-identical
blue/terracotta group can be merged immediately — see the follow-up commit.)

---

## 3. `formatCurrency` — precision differs

- `routes/jobDetail/formatting.ts` — `formatCurrency(value)` → **2** decimals.
- `routes/chat/utils.ts`, `routes/dashboard/helpers.ts` —
  `formatCurrency(value, digits = 4)` → **4** decimals.

The 4-decimal form is used for fine-grained agent/token costs; the 2-decimal for
coarser totals. This looks intentional (different precision for different
magnitudes), so it was left alone.

**Question:** keep two precisions (rename to make intent explicit, e.g.
`formatCost` vs `formatCurrency`), or standardize on one?
