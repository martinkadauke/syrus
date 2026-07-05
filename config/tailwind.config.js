// Brand palette: the terracotta of the winged-stylus mark (#b6492e at 600).
// The default Tailwind `blue` scale is remapped onto it so every existing
// `*-blue-*` utility renders the brand accent — one source of truth instead
// of a ~900-occurrence class rename that would conflict with every open
// branch. `terracotta-*` is the preferred name for new code; both names are
// the same scale by design. Keep this in sync with the desktop app's @theme
// block in desktop/src/styles.css.
const terracotta = {
  50: "#faf3ef",
  100: "#f4e2d9",
  200: "#e8c3b3",
  300: "#dba28b",
  400: "#cd7a5c",
  500: "#c05c3f",
  600: "#b6492e",
  700: "#973b25",
  800: "#7a2f1e",
  900: "#632718",
  950: "#361208"
}

module.exports = {
  darkMode: "class",
  content: [
    "./app/assets/tailwind/**/*.css",
    "./app/frontend/**/*.{js,jsx,ts,tsx}",
    "./app/helpers/**/*.rb",
    "./app/views/**/*.{erb,haml,html,slim}",
    "./public/*.html"
  ],
  theme: {
    extend: {
      colors: {
        terracotta,
        blue: terracotta
      }
    }
  }
}
