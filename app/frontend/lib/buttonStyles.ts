// One primary-action style for every signed-out surface (marketing landing,
// first-run welcome, and the sign-in/sign-up/password forms) so the web pages
// and the desktop shell's entry screens render the same button. `blue-*` is
// remapped to the terracotta brand scale in the Tailwind config.
export const authPrimaryButtonClass =
  "inline-flex items-center justify-center rounded bg-blue-600 px-3.5 py-2.5 text-sm font-semibold text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:bg-blue-300 dark:disabled:bg-blue-900"
