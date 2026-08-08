import { describe, expect, it } from "vitest"
import { pluginAdminComponentFor, pluginAdminComponentKeys } from "./pluginAdminPages"

describe("plugin admin page registry", () => {
  it("discovers installed plugin admin route components by component key", () => {
    expect(pluginAdminComponentKeys()).toContain("syrus_dev/AdminPerformance")
    expect(pluginAdminComponentFor("syrus_dev/AdminPerformance")).toBeTruthy()
    expect(pluginAdminComponentFor("missing/Nope")).toBeNull()
  })
})
