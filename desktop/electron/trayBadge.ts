// Paints the unread dot straight into a tray icon's BGRA bitmap (the layout
// nativeImage.toBitmap() returns). Kept free of Electron imports so the pixel
// math can be unit-tested — this surface once shipped a blank Windows tray
// icon, because nativeImage decodes SVG data URLs to an empty image there.
export const paintUnreadDot = (bitmap: Buffer, width: number, height: number): void => {
  const radius = Math.max(3, Math.round(width * 0.22))
  const centerX = width - radius - 1
  const centerY = radius + 1

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const dx = x - centerX
      const dy = y - centerY
      if (dx * dx + dy * dy <= radius * radius) {
        const offset = (y * width + x) * 4
        // BGRA byte order, premultiplied alpha.
        bitmap[offset] = 0x26
        bitmap[offset + 1] = 0x26
        bitmap[offset + 2] = 0xdc
        bitmap[offset + 3] = 0xff
      }
    }
  }
}
