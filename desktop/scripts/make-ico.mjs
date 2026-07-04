// Builds desktop/build/icon.ico from desktop/build/icon.png for the Windows
// installer + tray. Modern .ico files may embed PNG-compressed frames
// (Vista+), so this needs no image library: sips (macOS) produces the
// resized PNGs and this script packs them into the ICO container.
//
//   node scripts/make-ico.mjs
import { execFileSync } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"

const buildDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "build")
const source = path.join(buildDir, "icon.png")
const out = path.join(buildDir, "icon.ico")
const sizes = [16, 24, 32, 48, 64, 128, 256]

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "syrus-ico-"))
const frames = sizes.map((size) => {
  const file = path.join(tmp, `icon-${size}.png`)
  execFileSync("sips", ["--resampleHeightWidth", String(size), String(size), source, "--out", file], { stdio: "ignore" })
  return { size, data: fs.readFileSync(file) }
})

// ICONDIR (6 bytes) + ICONDIRENTRY (16 bytes each) + PNG payloads.
const header = Buffer.alloc(6)
header.writeUInt16LE(0, 0) // reserved
header.writeUInt16LE(1, 2) // type: icon
header.writeUInt16LE(frames.length, 4)

const entries = []
let offset = 6 + 16 * frames.length
for (const frame of frames) {
  const entry = Buffer.alloc(16)
  entry.writeUInt8(frame.size === 256 ? 0 : frame.size, 0) // width (0 = 256)
  entry.writeUInt8(frame.size === 256 ? 0 : frame.size, 1) // height
  entry.writeUInt8(0, 2) // palette
  entry.writeUInt8(0, 3) // reserved
  entry.writeUInt16LE(1, 4) // planes
  entry.writeUInt16LE(32, 6) // bpp
  entry.writeUInt32LE(frame.data.length, 8)
  entry.writeUInt32LE(offset, 12)
  offset += frame.data.length
  entries.push(entry)
}

fs.writeFileSync(out, Buffer.concat([header, ...entries, ...frames.map((f) => f.data)]))
fs.rmSync(tmp, { recursive: true, force: true })
console.log(`Wrote ${out} (${sizes.join(", ")}px)`)
