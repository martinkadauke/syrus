import { useEffect, useMemo, useState } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import {
  createRepository,
  fetchNewRepositoryForm,
  fetchRepositoryBranches,
  fetchRepositoryOptions,
  fetchRepositoryOwners,
  type GitHubRepositoryOption,
  type RepositoryInput
} from "../api/repositories"
import { ApiError } from "../api/client"
import { CloseIcon } from "./CloseIcon"

type OwnerOption = { login: string; type: "user" | "org" }
type Mode = "select" | "manual"

export function AddRepositoryModal({ onClose, onSaved }: { onClose: () => void; onSaved?: () => void }) {
  const queryClient = useQueryClient()
  const form = useQuery({ queryKey: ["repositories", "new"], queryFn: fetchNewRepositoryForm })
  const owners = useQuery({ queryKey: ["repositories", "owners"], queryFn: fetchRepositoryOwners })

  const [values, setValues] = useState<RepositoryInput | null>(null)
  const [ownerMode, setOwnerMode] = useState<Mode>("manual")
  const [nameMode, setNameMode] = useState<Mode>("manual")
  const [branchMode, setBranchMode] = useState<Mode>("manual")
  const [ownerOptions, setOwnerOptions] = useState<OwnerOption[]>([])
  const [repoOptions, setRepoOptions] = useState<GitHubRepositoryOption[]>([])
  const [branchOptions, setBranchOptions] = useState<string[]>([])
  const [notice, setNotice] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose()
    }
    document.addEventListener("keydown", onKeyDown)
    return () => document.removeEventListener("keydown", onKeyDown)
  }, [onClose])

  // Seed form values from the standard new-repository defaults, then apply the
  // onboarding overrides: auto-merge on, inherit the user's default agent, and
  // no upstream for now.
  useEffect(() => {
    if (!form.isSuccess || values) return
    const r = form.data.repository
    setValues({
      owner: r.owner,
      name: r.name,
      default_branch: r.default_branch || "main",
      upstream_owner: "",
      upstream_name: "",
      upstream_default_branch: "",
      trigger_label: r.trigger_label || "syrus",
      polling_enabled: r.polling_enabled,
      prepare_enabled: r.prepare_enabled,
      pr_cost_footer_enabled: r.pr_cost_footer_enabled,
      auto_merge_enabled: true,
      trust_clean_rebase_grade: r.trust_clean_rebase_grade,
      agent_provider: "",
      auto_approve_mode: r.auto_approve_mode,
      github_owner_id: "",
      github_repository_id: ""
    })
  }, [form.isSuccess, form.data, values])

  // Build the "Working owner" dropdown from the viewer + their orgs.
  useEffect(() => {
    if (!owners.isSuccess) return
    if (owners.data.error) {
      setNotice(ownerErrorMessage(owners.data.error))
      setOwnerMode("manual")
      return
    }
    const options = [
      owners.data.user ? ({ login: owners.data.user, type: "user" } as OwnerOption) : null,
      ...(owners.data.orgs || []).map((org) => ({ login: org, type: "org" } as OwnerOption))
    ].filter((o): o is OwnerOption => o !== null)
    setOwnerOptions(options)
    if (options.length > 0) setOwnerMode("select")
  }, [owners.isSuccess, owners.data])

  const selectedOwnerType = useMemo(
    () => ownerOptions.find((o) => o.login === values?.owner)?.type || "org",
    [ownerOptions, values?.owner]
  )

  // When an owner is picked in select mode, load its repositories.
  useEffect(() => {
    if (ownerMode !== "select" || !values?.owner) return
    let cancelled = false
    fetchRepositoryOptions(values.owner, selectedOwnerType).then((data) => {
      if (cancelled) return
      if (data.error || !data.repos) {
        setNameMode("manual")
        setRepoOptions([])
        return
      }
      const options = data.repos.map((repo) =>
        typeof repo === "string" ? { name: repo, github_repository_id: null, github_owner_id: null } : repo
      )
      setRepoOptions(options)
      setNameMode(options.length > 0 ? "select" : "manual")
    })
    return () => {
      cancelled = true
    }
  }, [ownerMode, selectedOwnerType, values?.owner])

  // Load branches once owner + name are known: turn Default branch into a
  // dropdown (like repo#add) and suggest main/master.
  useEffect(() => {
    if (!values?.owner || !values?.name) return
    let cancelled = false
    fetchRepositoryBranches(values.owner, values.name).then((data) => {
      if (cancelled) return
      if (data.error || !(data.branches && data.branches.length > 0)) {
        setBranchMode("manual")
        setBranchOptions([])
        return
      }
      setBranchOptions(data.branches)
      setBranchMode("select")
      setValues((current) => (current ? { ...current, default_branch: suggestBranch(data.branches, data.default_branch) } : current))
    }).catch(() => {
      if (cancelled) return
      setBranchMode("manual")
      setBranchOptions([])
    })
    return () => {
      cancelled = true
    }
  }, [values?.owner, values?.name])

  const save = useMutation({
    mutationFn: () => createRepository(values as RepositoryInput),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["bootstrap"] })
      await queryClient.invalidateQueries({ queryKey: ["repositories"] })
      onSaved?.()
      onClose()
    },
    onError: (err) => {
      setError(err instanceof ApiError ? err.message : "Could not add the repository. Check the details and try again.")
    }
  })

  function update(patch: Partial<RepositoryInput>) {
    setValues((current) => (current ? { ...current, ...patch } : current))
  }

  function chooseRepo(name: string) {
    const selected = repoOptions.find((r) => r.name === name)
    update({
      name,
      github_owner_id: selected?.github_owner_id == null ? "" : String(selected.github_owner_id),
      github_repository_id: selected?.github_repository_id == null ? "" : String(selected.github_repository_id)
    })
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    setError(null)
    if (!values || values.owner.trim().length === 0 || values.name.trim().length === 0) {
      setError("Choose an owner and repository name.")
      return
    }
    save.mutate()
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <section
        aria-labelledby="add-repository-title"
        aria-modal="true"
        className="max-h-[calc(100vh-2rem)] w-full max-w-lg overflow-y-auto rounded-lg bg-white dark:bg-gray-900 shadow-xl"
        role="dialog"
        onClick={(event) => event.stopPropagation()}
      >
        <form className="space-y-5 p-5 sm:p-6" onSubmit={submit}>
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100" id="add-repository-title">
                Add repository
              </h2>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
                Pick the first repository Syrus should work with. You can add more later from Repositories.
              </p>
            </div>
            <button
              aria-label="Close"
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 hover:text-gray-700 dark:hover:text-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
              onClick={onClose}
              type="button"
            >
              <CloseIcon className="h-7 w-7" />
            </button>
          </div>

          {notice ? <Box tone="muted">{notice}</Box> : null}

          {!values ? (
            <p className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400" role="status">
              <Spinner /> Loading…
            </p>
          ) : (
            <>
              <Field label="User/Org">
                {ownerMode === "select" && ownerOptions.length > 0 ? (
                  <SelectWithManual label="User/Org" onManual={() => setOwnerMode("manual")} onChange={(owner) => update({ owner, name: "", github_owner_id: "", github_repository_id: "" })} value={values.owner}>
                    <option value="">Select user or org…</option>
                    {ownerOptions.map((o) => <option key={o.login} value={o.login}>{o.login}</option>)}
                  </SelectWithManual>
                ) : (
                  <input aria-label="User/Org" className={inputClass()} onChange={(event) => update({ owner: event.target.value, github_owner_id: "", github_repository_id: "" })} placeholder="user or org" value={values.owner} />
                )}
              </Field>

              <Field label="Repository">
                {nameMode === "select" && repoOptions.length > 0 ? (
                  <SelectWithManual label="Repository" onManual={() => setNameMode("manual")} onChange={chooseRepo} value={values.name}>
                    <option value="">Select repository…</option>
                    {repoOptions.map((r) => <option key={r.name} value={r.name}>{r.name}</option>)}
                  </SelectWithManual>
                ) : (
                  <input aria-label="Repository" className={inputClass()} onChange={(event) => update({ name: event.target.value, github_repository_id: "" })} placeholder="repository" value={values.name} />
                )}
              </Field>

              <Field label="Default branch">
                {branchMode === "select" && branchOptions.length > 0 ? (
                  <SelectWithManual label="Default branch" onManual={() => setBranchMode("manual")} onChange={(branch) => update({ default_branch: branch })} value={values.default_branch}>
                    {branchOptions.map((branch) => <option key={branch} value={branch}>{branch}</option>)}
                  </SelectWithManual>
                ) : (
                  <input aria-label="Default branch" className={inputClass()} onChange={(event) => update({ default_branch: event.target.value })} placeholder="main" value={values.default_branch} />
                )}
              </Field>

              <Box tone="muted">
                Runs will use your default agent ({form.data?.user_agent_provider_label || "your default"}). The{" "}
                <code className="rounded bg-gray-100 px-1 py-0.5 font-mono text-xs dark:bg-gray-800">{values.trigger_label}</code>{" "}
                trigger label, auto-merge, and the standard repository defaults apply — you can change the label and
                fine-tune everything later in the repository settings.
              </Box>

              {error ? <Box tone="error">{error}</Box> : null}

              <div className="flex items-center justify-end gap-2">
                <button className="rounded-md border border-gray-300 dark:border-gray-600 px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800" onClick={onClose} type="button">
                  Cancel
                </button>
                <button className="inline-flex items-center gap-2 rounded-md bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-60" disabled={save.isPending} type="submit">
                  {save.isPending ? <><Spinner light /> Adding…</> : "Add repository"}
                </button>
              </div>
            </>
          )}
        </form>
      </section>
    </div>
  )
}

function suggestBranch(branches: string[] | undefined, defaultBranch: string | undefined) {
  if (defaultBranch) return defaultBranch
  const list = branches || []
  if (list.includes("main")) return "main"
  if (list.includes("master")) return "master"
  return list[0] || "main"
}

function SelectWithManual({ children, label, onChange, onManual, value }: {
  children: React.ReactNode
  label: string
  onChange: (value: string) => void
  onManual: () => void
  value: string
}) {
  return (
    <div>
      <select aria-label={label} className={`${inputClass()} font-mono`} onChange={(event) => onChange(event.target.value)} value={value}>
        {children}
      </select>
      <button className="mt-1 text-xs text-gray-500 dark:text-gray-400 underline hover:no-underline" onClick={onManual} type="button">Enter manually</button>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
      {label}
      <div className="mt-2">{children}</div>
    </label>
  )
}

function Box({ tone, children }: { tone: "muted" | "error"; children: React.ReactNode }) {
  const toneClass = tone === "error"
    ? "border-red-200 bg-red-50 text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300"
    : "border-gray-200 bg-gray-50 text-gray-600 dark:border-gray-700 dark:bg-gray-800/50 dark:text-gray-400"
  return <p className={`rounded border px-3 py-2 text-sm ${toneClass}`} role={tone === "error" ? "alert" : undefined}>{children}</p>
}

function Spinner({ light }: { light?: boolean }) {
  return (
    <svg aria-hidden="true" className={`h-4 w-4 animate-spin ${light ? "text-white" : "text-gray-400"}`} fill="none" viewBox="0 0 24 24">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" d="M4 12a8 8 0 018-8" fill="currentColor" />
    </svg>
  )
}

function inputClass() {
  return "block w-full rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-900 px-3 py-2 text-sm shadow-sm focus:outline-blue-600"
}

function ownerErrorMessage(error: string) {
  if (error === "no_token") return "No GitHub token configured yet. Enter the owner and repository manually."
  if (error === "unauthorized") return "GitHub rejected the configured credentials. Enter the repository manually or revisit Configure GitHub."
  return "Unable to load GitHub owners. Enter the repository manually."
}
