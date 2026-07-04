import { describe, expect, it } from "vitest"
import { passwordStrength } from "./passwordStrength"

describe("passwordStrength", () => {
  it("is empty for an empty password", () => {
    expect(passwordStrength("")).toEqual({ bits: 0, score: 0, label: "" })
  })

  it("rates short or single-class passwords weak", () => {
    expect(passwordStrength("cat").label).toBe("Weak")
    expect(passwordStrength("1234567").label).toBe("Weak")
  })

  it("does not reward repeated characters", () => {
    // 16 chars of one letter must not read as strong.
    expect(passwordStrength("aaaaaaaaaaaaaaaa").label).toBe("Weak")
  })

  it("climbs through fair and good as length and classes grow", () => {
    expect(passwordStrength("otter12").label).toBe("Fair")
    expect(passwordStrength("blueotter123").label).toBe("Good")
  })

  it("rates long multi-class passphrases strong", () => {
    expect(passwordStrength("Blue-Otter!Yodels@Dawn7").label).toBe("Strong")
    expect(passwordStrength("correct horse battery staple").label).toBe("Strong")
  })
})
