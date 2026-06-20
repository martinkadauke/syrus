import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { afterEach, describe, expect, it, vi } from "vitest"
import { AddRepositoryModal } from "./AddRepositoryModal"

function renderModal(props: { onClose?: () => void; onSaved?: () => void } = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}>
      <AddRepositoryModal onClose={props.onClose ?? (() => {})} onSaved={props.onSaved} />
    </QueryClientProvider>
  )
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
}

const newFormPayload = {
  repository: {
    id: null,
    owner: "",
    name: "",
    slug: null,
    default_branch: "main",
    upstream_owner: "",
    upstream_name: "",
    upstream_default_branch: "",
    trigger_label: "syrus",
    polling_enabled: true,
    prepare_enabled: true,
    pr_cost_footer_enabled: true,
    auto_merge_enabled: false,
    trust_clean_rebase_grade: false,
    agent_provider: "",
    auto_approve_mode: "never",
    github_owner_id: null,
    github_repository_id: null,
    repository_path: null
  },
  configured_agent_providers: [{ value: "claude", label: "Claude" }],
  user_agent_provider_label: "Claude",
  auto_approve_modes: [],
  repositories_path: "/repositories"
}

function mockRoutes(over: { owners?: () => Response; create?: () => Response } = {}) {
  return vi.spyOn(window, "fetch").mockImplementation(async (input, init) => {
    const url = String(input)
    if (url.includes("/repositories/new")) return jsonResponse(newFormPayload)
    if (url.includes("/repositories/owners")) return over.owners?.() ?? jsonResponse({ user: "octocat", orgs: ["acme"] })
    if (url.includes("/repositories/repos")) return jsonResponse({ repos: [{ name: "hello-world", github_repository_id: 7, github_owner_id: 3 }] })
    if (url.includes("/repositories/branches")) return jsonResponse({ branches: ["main", "dev"], default_branch: "main" })
    if (url.endsWith("/api/v1/app/repositories") && init?.method === "POST") {
      return over.create?.() ?? jsonResponse({ message: "Saved", redirect_to: "/repositories/1", repository: {} })
    }
    throw new Error(`unexpected fetch: ${url}`)
  })
}

describe("AddRepositoryModal", () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("offers User/Org and Repository dropdowns, suggests main, and defaults the syrus label silently", async () => {
    mockRoutes()
    renderModal()

    const owner = (await screen.findByRole("combobox", { name: "User/Org" })) as HTMLSelectElement
    expect(Array.from(owner.options).map((o) => o.value)).toEqual(["", "octocat", "acme"])
    expect((screen.getByLabelText("Default branch") as HTMLInputElement).value).toBe("main")
    // Trigger label is not a field — it defaults to syrus and is set later.
    expect(screen.queryByLabelText("Trigger label")).not.toBeInTheDocument()
    expect(screen.getByText("syrus")).toBeInTheDocument()
    expect(screen.getByText(/add more later/i)).toBeInTheDocument()
  })

  it("turns Default branch into a dropdown once the repository is selected", async () => {
    mockRoutes()
    renderModal()

    fireEvent.change(await screen.findByRole("combobox", { name: "User/Org" }), { target: { value: "octocat" } })
    fireEvent.change(await screen.findByRole("combobox", { name: "Repository" }), { target: { value: "hello-world" } })

    const branch = (await screen.findByRole("combobox", { name: "Default branch" })) as HTMLSelectElement
    expect(Array.from(branch.options).map((o) => o.value)).toEqual(["main", "dev"])
    expect(branch.value).toBe("main")
  })

  it("creates one repository with auto-merge on, inherited agent, and no upstream", async () => {
    const fetchSpy = mockRoutes()
    const onSaved = vi.fn()
    const onClose = vi.fn()
    renderModal({ onSaved, onClose })

    const owner = await screen.findByRole("combobox", { name: "User/Org" })
    fireEvent.change(owner, { target: { value: "octocat" } })

    const name = await screen.findByRole("combobox", { name: "Repository" })
    fireEvent.change(name, { target: { value: "hello-world" } })

    fireEvent.click(screen.getByRole("button", { name: "Add repository" }))

    await waitFor(() => expect(onClose).toHaveBeenCalled())
    expect(onSaved).toHaveBeenCalledTimes(1)

    const createCall = fetchSpy.mock.calls.find(([u, i]) => String(u).endsWith("/api/v1/app/repositories") && (i as RequestInit)?.method === "POST")
    const repo = JSON.parse((createCall?.[1] as RequestInit).body as string).repository
    expect(repo).toMatchObject({
      owner: "octocat",
      name: "hello-world",
      default_branch: "main",
      trigger_label: "syrus",
      auto_merge_enabled: true,
      agent_provider: "",
      upstream_owner: "",
      upstream_name: "",
      github_repository_id: "7"
    })
  })

  it("falls back to manual entry when GitHub owners can't be loaded", async () => {
    mockRoutes({ owners: () => jsonResponse({ error: "no_token" }) })
    renderModal()

    await waitFor(() => expect(screen.getByText(/No GitHub token configured/)).toBeInTheDocument())
    expect(screen.getByRole("textbox", { name: "User/Org" })).toBeInTheDocument()
    expect(screen.getByRole("textbox", { name: "Repository" })).toBeInTheDocument()
  })
})
