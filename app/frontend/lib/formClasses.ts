// Canonical Tailwind class for text/select form inputs, shared across the SPA.
// Uses the terracotta brand accent for the focus outline (blue-* renders the
// same via the palette remap in config/tailwind.config.js, but new code should
// name terracotta). Consolidated from several visually-identical copies.
export function inputClass() {
  return "block w-full rounded border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:outline-terracotta-600 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100 dark:placeholder:text-gray-500"
}
