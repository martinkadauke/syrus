// Versioned URL for the brand icon served from public/. Production serves
// public/ files with a 1-year max-age, so a rebranded icon.png stays stale in
// any browser (including the desktop shell's web container) that cached a
// previous backend's copy. The version query busts that cache; bump it
// whenever the brand artwork changes. Keep in sync with the favicon links in
// app/views/layouts/spa.html.erb.
export const BRAND_ICON_VERSION = 2
export const BRAND_ICON_SRC = `/icon.png?v=${BRAND_ICON_VERSION}`
