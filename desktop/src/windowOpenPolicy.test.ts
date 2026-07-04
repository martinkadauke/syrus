import { describe, expect, it } from "vitest"
import { decideWindowOpen } from "../electron/windows/windowOpenPolicy"

const origin = "http://localhost:3000"

describe("decideWindowOpen", () => {
  it("keeps same-origin URLs in the main window", () => {
    expect(decideWindowOpen("http://localhost:3000/jobs/12", origin)).toBe("main")
  })

  it("sends cross-origin web URLs to the external browser", () => {
    expect(decideWindowOpen("https://github.com/tkadauke/syrus/pull/1", origin)).toBe("external")
    expect(decideWindowOpen("https://claude.ai/oauth/authorize?x=1", origin)).toBe("external")
  })

  it("sends same-origin URLs marked syrus_external=1 to the external browser", () => {
    expect(
      decideWindowOpen("http://localhost:3000/admin/github_app/manifest?state=abc&syrus_external=1", origin)
    ).toBe("external")
  })

  it("ignores a syrus_external marker with any other value", () => {
    expect(decideWindowOpen("http://localhost:3000/page?syrus_external=0", origin)).toBe("main")
  })

  it("denies non-web protocols", () => {
    expect(decideWindowOpen("file:///etc/passwd", origin)).toBe("deny")
    expect(decideWindowOpen("javascript:alert(1)", origin)).toBe("deny")
    expect(decideWindowOpen("about:blank", origin)).toBe("deny")
  })

  it("denies unparseable URLs", () => {
    expect(decideWindowOpen("not a url", origin)).toBe("deny")
  })
})
