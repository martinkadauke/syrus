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

export function AddRepositoryModal({ onClose, onSaved }: { onClose: () => void; onSaved?: () => void }) {
  const queryClient = useQueryClient()
  const form = useQuery({ queryKey: ["repositories", "new"], queryFn: fetchNewRepositoryForm })
  const owners = useQuery({ queryKey: ["repositories", "owners"], queryFn: fetchRepositoryOwners })

  const [values, setValues] = useState<RepositoryInput | null>(null)
  const [ownerOptions, setOwnerOptions] = useState<OwnerOption[]>([])
  const [repoOptions, setRepoOptions] = useState<GitHubRepositoryOption[]>([])
  const [branchOptions, setBranchOptions] = useState<string[]>([])
  const [loadingRepos, setLoadingRepos] = useState(false)
  const [loadingBranches, setLoadingBranches] = useState(false)
  const [ownersNotice, setOwnersNotice] = useState<string | null>(null)
  const [reposNotice, setReposNotice] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [installUrl, setInstallUrl] = useState<string | null>(null)

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose()
    }
    document.addEventListener("keydown", onKeyDown)
    return () => document.removeEventListener("keydown", onKeyDown)
  }, [onClose])

  // Seed defaults from the standard new-repository form, then apply the
  // onboarding overrides: auto-merge on, inherit the user's default agent,
  // keep the syrus trigger label, and no upstream.
  useEffect(() => {
    if (!form.isSuccess || values) return
    const r = form.data.repository
    setValues({
      owner: "",
      name: "",
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

  // Build the User/Org dropdown from the viewer + their orgs.
  useEffect(() => {
    if (!owners.isSuccess) return
    if (owners.data.error) {
      setOwnersNotice(ownerErrorMessage(owners.data.error))
      return
    }
    setOwnerOptions([
      owners.data.user ? ({ login: owners.data.user, type: "user" } as OwnerOption) : null,
      ...(owners.data.orgs || []).map((org) => ({ login: org, type: "org" } as OwnerOption))
    ].filter((o): o is OwnerOption => o !== null))
  }, [owners.isSuccess, owners.data])

  const selectedOwnerType = useMemo(
    () => ownerOptions.find((o) => o.login === values?.owner)?.type || "org",
    [ownerOptions, values?.owner]
  )

  // Load repositories once a User/Org is picked.
  useEffect(() => {
    if (!values?.owner) return
    let cancelled = false
    setLoadingRepos(true)
    setReposNotice(null)
    fetchRepositoryOptions(values.owner, selectedOwnerType).then((data) => {
      if (cancelled) return
      setLoadingRepos(false)
      if (data.error || !data.repos) {
        setRepoOptions([])
        setReposNotice(repoErrorMessage(data.error))
        return
      }
      const options = data.repos.map((repo) =>
        typeof repo === "string" ? { name: repo, github_repository_id: null, github_owner_id: null } : repo
      )
      setRepoOptions(options)
      if (options.length === 0) setReposNotice("No repositories found for this owner.")
    }).catch(() => {
      if (cancelled) return
      setLoadingRepos(false)
      setRepoOptions([])
      setReposNotice("Unable to load repositories.")
    })
    return () => {
      cancelled = true
    }
  }, [selectedOwnerType, values?.owner])

  // Load branches once a repository is picked, then suggest main/master.
  useEffect(() => {
    if (!values?.owner || !values?.name) return
    let cancelled = false
    setLoadingBranches(true)
    fetchRepositoryBranches(values.owner, values.name).then((data) => {
      if (cancelled) return
      setLoadingBranches(false)
      const branches = data.error ? [] : data.branches || []
      setBranchOptions(branches)
      if (branches.length > 0) {
        setValues((current) => (current ? { ...current, default_branch: suggestBranch(branches, data.default_branch) } : current))
      }
    }).catch(() => {
      if (cancelled) return
      setLoadingBranches(false)
      setBranchOptions([])
    })
    return () => {
      cancelled = true
    }
  }, [values?.owner, values?.name])

  const save = useMutation({
    mutationFn: () => createRepository(values as RepositoryInput),
    onSuccess: async (payload) => {
      await queryClient.invalidateQueries({ queryKey: ["bootstrap"] })
      await queryClient.invalidateQueries({ queryKey: ["repositories"] })
      onSaved?.()
      // If the GitHub App is registered but not yet installed on this repo,
      // prompt to install it instead of closing right away.
      if (payload.app_install_url) {
        setInstallUrl(payload.app_install_url)
      } else {
        onClose()
      }
    },
    onError: (err) => {
      setError(err instanceof ApiError ? err.message : "Could not add the repository. Try again.")
    }
  })

  function chooseOwner(owner: string) {
    setRepoOptions([])
    setBranchOptions([])
    setReposNotice(null)
    setValues((current) => (current ? { ...current, owner, name: "", github_owner_id: "", github_repository_id: "" } : current))
  }

  function chooseRepo(name: string) {
    const selected = repoOptions.find((r) => r.name === name)
    setBranchOptions([])
    setValues((current) => (current ? {
      ...current,
      name,
      github_owner_id: selected?.github_owner_id == null ? "" : String(selected.github_owner_id),
      github_repository_id: selected?.github_repository_id == null ? "" : String(selected.github_repository_id)
    } : current))
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    setError(null)
    if (!values || !values.owner || !values.name) {
      setError("Choose a user/org and repository.")
      return
    }
    save.mutate()
  }

  const ownersLoading = !owners.isSuccess && !ownersNotice

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <section
        aria-labelledby="add-repository-title"
        aria-modal="true"
        className="max-h-[calc(100vh-2rem)] w-full max-w-lg overflow-y-auto rounded-lg bg-white dark:bg-gray-900 shadow-xl"
        role="dialog"
        onClick={(event) => event.stopPropagation()}
      >
        {installUrl ? (
          <div className="space-y-5 p-5 sm:p-6">
            <div className="flex items-start justify-between gap-4">
              <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">Install the Syrus GitHub App</h2>
              <button aria-label="Close" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800" onClick={onClose} type="button">
                <CloseIcon className="h-7 w-7" />
              </button>
            </div>
            <Box tone="muted">
              {(values?.owner ? `${values.owner}/${values.name}` : "This repository")} was added. Install the Syrus
              GitHub App on it so Syrus can act as a bot (independent rate limit, auto-refreshing tokens). Until then,
              Syrus falls back to your personal access token.
            </Box>
            <a className="inline-flex items-center gap-1 rounded-md bg-gray-900 px-3 py-2 text-sm font-medium text-white hover:bg-gray-700 dark:bg-gray-100 dark:text-gray-900 dark:hover:bg-white" href={installUrl} rel="noreferrer" target="_blank">
              Install on GitHub <span aria-hidden="true">↗</span>
            </a>
            <div className="flex items-center justify-end gap-2">
              <button className="rounded-md border border-gray-300 dark:border-gray-600 px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800" onClick={onClose} type="button">Skip for now</button>
              <button className="rounded-md bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700" onClick={onClose} type="button">Done</button>
            </div>
          </div>
        ) : (
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

          {!values ? (
            <p className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400" role="status">
              <Spinner /> Loading…
            </p>
          ) : (
            <>
              <Field label="User/Org">
                {ownersNotice ? (
                  <Box tone="error">{ownersNotice}</Box>
                ) : ownersLoading ? (
                  <Loading>Loading your GitHub accounts…</Loading>
                ) : (
                  <select aria-label="User/Org" className={selectClass()} onChange={(event) => chooseOwner(event.target.value)} value={values.owner}>
                    <option value="">Select user or org…</option>
                    {ownerOptions.map((o) => <option key={o.login} value={o.login}>{o.login}</option>)}
                  </select>
                )}
              </Field>

              {values.owner ? (
                <Field label="Repository">
                  {loadingRepos ? (
                    <Loading>Loading repositories…</Loading>
                  ) : reposNotice ? (
                    <Box tone="error">{reposNotice}</Box>
                  ) : (
                    <select aria-label="Repository" className={selectClass()} onChange={(event) => chooseRepo(event.target.value)} value={values.name}>
                      <option value="">Select repository…</option>
                      {repoOptions.map((r) => <option key={r.name} value={r.name}>{r.name}</option>)}
                    </select>
                  )}
                </Field>
              ) : null}

              {values.name ? (
                <Field label="Default branch">
                  {loadingBranches ? (
                    <Loading>Loading branches…</Loading>
                  ) : (
                    <select aria-label="Default branch" className={selectClass()} onChange={(event) => setValues((c) => (c ? { ...c, default_branch: event.target.value } : c))} value={values.default_branch}>
                      {branchOptions.map((branch) => <option key={branch} value={branch}>{branch}</option>)}
                    </select>
                  )}
                </Field>
              ) : null}

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
                <button className="inline-flex items-center gap-2 rounded-md bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-60" disabled={save.isPending || !values.owner || !values.name} type="submit">
                  {save.isPending ? <><Spinner light /> Adding…</> : "Add repository"}
                </button>
              </div>
            </>
          )}
        </form>
        )}
      </section>
    </div>
  )
}

function suggestBranch(branches: string[], defaultBranch: string | undefined) {
  if (defaultBranch && branches.includes(defaultBranch)) return defaultBranch
  if (branches.includes("main")) return "main"
  if (branches.includes("master")) return "master"
  return branches[0] || "main"
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
      {label}
      <div className="mt-2">{children}</div>
    </label>
  )
}

function Loading({ children }: { children: React.ReactNode }) {
  return (
    <p className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400" role="status">
      <Spinner /> {children}
    </p>
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

function selectClass() {
  return "block w-full rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-900 px-3 py-2 text-sm font-mono shadow-sm focus:outline-blue-600"
}

function ownerErrorMessage(error: string) {
  if (error === "no_token") return "No GitHub token configured yet — revisit Configure GitHub first."
  if (error === "unauthorized") return "GitHub rejected the configured credentials. Revisit Configure GitHub."
  return "Unable to load your GitHub accounts. Revisit Configure GitHub."
}

function repoErrorMessage(error?: string) {
  if (error === "no_token") return "No GitHub token configured — revisit Configure GitHub."
  if (error === "not_found") return "Owner not found or not accessible."
  return "Unable to load repositories for this owner."
}
