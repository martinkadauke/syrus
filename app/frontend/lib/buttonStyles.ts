// One primary-action style for every signed-out surface (marketing landing,
// first-run welcome, and the sign-in/sign-up/password forms) so the web pages
// and the desktop shell's entry screens render the same button. terracotta-*
// per the palette convention — blue-* only survives in legacy code.
export const authPrimaryButtonClass =
  "inline-flex items-center justify-center rounded bg-terracotta-600 px-3.5 py-2.5 text-sm font-semibold text-white hover:bg-terracotta-500 disabled:cursor-not-allowed disabled:bg-terracotta-300 dark:disabled:bg-terracotta-900"
