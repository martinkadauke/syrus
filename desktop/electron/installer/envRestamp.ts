// Pure helper for OnboardingDriver.locateEnv (installerDriver.ts) — no electron
// import so vitest can cover it directly (desktop/src/envRestamp.test.ts).
//
// When a TEST build adopts an existing install's .env to keep its data volume
// decryptable, that .env may belong to the production stack (port 3000). The
// test stack must bind ITS port (3001), so we force SYRUS_PORT / SYRUS_APP_HOST
// to the channel default. Two cases matter:
//   - line present  -> replace it (a wrong picked value can't leak through)
//   - line absent    -> APPEND it (otherwise install.sh copies the .env verbatim
//                       and docker-compose falls back to ${SYRUS_PORT:-3000},
//                       silently binding production's port)
// This runs ONLY on the test channel; the stable channel copies the adopted
// .env verbatim (a deliberately non-default production port must be preserved).

const setEnvLine = (text: string, key: string, value: string): string => {
  const line = `${key}=${value}`
  const re = new RegExp(`^${key}=.*$`, "m")
  if (re.test(text)) {
    return text.replace(re, line)
  }
  // Append on its own line; keep it valid whether or not the file ended in a
  // newline (or was empty).
  const sep = text.length === 0 || text.endsWith("\n") ? "" : "\n"
  return `${text}${sep}${line}\n`
}

export const restampEnvPort = (contents: string, port: number): string => {
  let out = setEnvLine(contents, "SYRUS_PORT", String(port))
  out = setEnvLine(out, "SYRUS_APP_HOST", `localhost:${port}`)
  return out
}
