import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { FormEvent } from "react"
import { useEffect, useRef, useState } from "react"
import { Link, useLocation, useNavigate, useParams } from "react-router-dom"
import { useT } from "../hooks/useT"
import { CloseIcon } from "../components/CloseIcon"
import { KeyValue } from "../components/KeyValue"
import { CopyableSlug } from "../components/CopyableSlug"
import { SlugHoverCard } from "../components/SlugHoverCard"
import { NoticeToast } from "../components/NoticeToast"
import { StatusPill } from "../components/StatusPill"
import { Markdown } from "../lib/Markdown"
import { workflowSlug } from "../lib/slugs"
import { buttonClass, type ButtonTone } from "../lib/buttonClasses"
import { useDismissiblePopup } from "../lib/useDismissiblePopup"
import { applyPendingFeedback, createJobAttachments, deleteJobCommand, fetchJobDetail, fetchJobTimeline, fetchJobWorkflows, ignorePendingFeedback, replacePendingFeedback, submitJobFeedback, type JobAttachment, type JobDependency, type JobApprovalRecord, type JobApprovalStatus, type JobDetailPayload, type JobTestPlan, type JobWorkflow, type PendingFeedbackComment } from "../api/jobs"
import { CoverageCard } from "../components/CoverageCard"
import { errorMessage } from "../lib/errorMessage"
import { formatBytes } from "../lib/format"
import type { JobDetailQueryKey, JobTab, JobWorkflowsQueryKey } from "./jobDetail/queryKeys"
import { CommandButton, useJobCommand, type CommandInput } from "./jobDetail/command"
import { PanelMessage, SmallPill } from "./jobDetail/components"
import { jobDetailQueryKey, jobDetailSearch, jobWorkflowsQueryKey, mergeJobWorkflowsPayload, tabFromLocation } from "./jobDetail/queryKeys"
import { formatCurrency, formatDate, jobSlug, menuButtonClass, withRoutePrefix } from "./jobDetail/formatting"
import { latestWorkflowCoverage, workflowCreatedAtTime } from "./jobDetail/workflowArtifacts"
import { WorkflowsTab } from "./jobDetail/WorkflowGraph"
import { SourceTab } from "./jobDetail/SourceBrowser"

type HeaderAction = {
  key: string
  label: string
  input: CommandInput
  tone: ButtonTone
}

export function JobDetailRoute() {
  const { t } = useT("jobs")
  const params = useParams()
  const location = useLocation()
  const navigate = useNavigate()
  const id = params.id || ""
  const activeTab = tabFromLocation(location.pathname, location.search)
  const prefix = location.pathname.startsWith("/app-shell") ? "/app-shell" : ""
  const detailSearch = jobDetailSearch(location.search)
  const queryKey = jobDetailQueryKey(id, detailSearch)
  const workflowsQueryKey = jobWorkflowsQueryKey(id, detailSearch)
  const detail = useQuery({
    queryKey,
    queryFn: () => fetchJobDetail(id, detailSearch),
    enabled: id.length > 0
  })
  const workflows = useQuery({
    queryKey: workflowsQueryKey,
    queryFn: () => fetchJobWorkflows(id, detailSearch),
    enabled: id.length > 0 && activeTab === "workflows" && detail.isSuccess,
    placeholderData: keepPreviousData
  })
  const payload = detail.isSuccess ? mergeJobWorkflowsPayload(detail.data, workflows.data) : null

  function selectTab(tab: JobTab) {
    const search = new URLSearchParams(location.search)
    if (tab === "summary") search.delete("tab")
    else search.set("tab", tab)
    if (tab !== "workflows") search.delete("workflows_page")
    const next = search.toString()
    navigate(`${location.pathname}${next ? `?${next}` : ""}`)
  }

  return (
    <main aria-label={t("aria_job")} className="mx-auto max-w-[96rem] space-y-6 p-6">
      {detail.isPending ? <PanelMessage>{t("loading")}</PanelMessage> : null}
      {detail.isError ? <PanelMessage tone="error">{errorMessage(detail.error, t("load_error"))}</PanelMessage> : null}
      {payload ? <JobDetailView activeTab={activeTab} onSelectTab={selectTab} payload={payload} prefix={prefix} queryKey={queryKey} workflowsQueryKey={workflowsQueryKey} /> : null}
    </main>
  )
}

export function JobDetailView({ payload, queryKey, workflowsQueryKey, activeTab, onSelectTab, prefix }: { payload: JobDetailPayload; queryKey: JobDetailQueryKey; workflowsQueryKey?: JobWorkflowsQueryKey; activeTab: JobTab; onSelectTab: (tab: JobTab) => void; prefix: string }) {
  const { t } = useT("jobs")
  const location = useLocation()
  const queryClient = useQueryClient()
  const [notice, setNotice] = useState<string | null>(payload.message || null)
  const [feedbackPanelOpen, setFeedbackPanelOpen] = useState(false)
  const command = useJobCommand(payload.job.id, queryKey, workflowsQueryKey, setNotice)
  const title = payload.job.issue_title || jobSourceLabel(payload, t)
  const workflowAnchor = location.hash.startsWith("#workflow-") ? location.hash.slice(1) : null
  const renderedWorkflowIds = payload.workflows.map((workflow) => workflow.id).join(",")
  const feedback = useMutation({
    mutationFn: (body: string) => submitJobFeedback(payload.job.id, body),
    onSuccess: () => {
      setFeedbackPanelOpen(false)
      setNotice(t("feedback_submitted"))
      void queryClient.invalidateQueries({ queryKey })
      if (workflowsQueryKey) void queryClient.invalidateQueries({ queryKey: workflowsQueryKey })
    }
  })

  useEffect(() => {
    setNotice(payload.message || null)
  }, [payload.job.id, payload.message])

  useEffect(() => {
    if (activeTab !== "workflows" || !workflowAnchor) return undefined

    const frame = window.requestAnimationFrame(() => {
      document.getElementById(workflowAnchor)?.scrollIntoView({ block: "start" })
    })

    return () => window.cancelAnimationFrame(frame)
  }, [activeTab, workflowAnchor, renderedWorkflowIds])

  return (
    <>
      <header className="space-y-3">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex flex-wrap items-start gap-3">
              <h1 className="break-words text-3xl font-semibold text-gray-900 dark:text-gray-100">
                <CopyableSlug slug={jobSlug(payload.job.id)} />
                <span className="px-2 text-gray-400 dark:text-gray-500">·</span>
                <PendingJobTitle pending={Boolean(payload.job.title_pending)} title={title} />
              </h1>
              <div className="mt-1.5 shrink-0"><JobStateBadge state={payload.job.summary_state} /></div>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <p className="mt-1 break-words text-sm text-gray-600 dark:text-gray-300">
                <Link className="font-mono hover:underline" to={withRoutePrefix(payload.repository.repository_path, prefix)}>{payload.repository.slug}</Link>
                <span className="px-2 text-gray-300 dark:text-gray-600">/</span>
                <JobSourceLink payload={payload} prefix={prefix} />
              </p>
              {payload.job.agent_provider ? <SmallPill>{payload.job.agent_provider}</SmallPill> : null}
              {payload.job.credential_mode ? <SmallPill>{payload.job.credential_mode}</SmallPill> : null}
            </div>
            <div className="mt-1 flex flex-wrap items-center gap-x-1 gap-y-1 text-sm text-gray-500 dark:text-gray-400">
              <span>{t("workflow_count", { count: payload.job.workflows_count })} · {t("run_count", { count: payload.job.runs_count })}</span>
              {payload.job.total_cost_usd == null ? null : <span>· {formatCurrency(payload.job.total_cost_usd)}</span>}
              {payload.job.prepare_skipped ? <span className="font-medium text-amber-700">· {t("prepare_skipped")}</span> : null}
              {payload.job.source_chat ? (
                <span>
                  · <Link className="font-medium text-blue-600 hover:underline dark:text-blue-300" to={withRoutePrefix(payload.job.source_chat.path, prefix)}>{payload.job.source_chat.label}</Link>
                </span>
              ) : null}
              {payload.origin_chat ? (
                <span>
                  · <Link className="inline-flex items-center gap-1 font-medium text-blue-600 hover:underline dark:text-blue-300" to={withRoutePrefix(`/chats/${payload.origin_chat.chat_session_id}#message-${payload.origin_chat.message_id}`, prefix)}>
                    <ChatBubbleIcon />
                    <span>{t("view_in_chat")}</span>
                  </Link>
                </span>
              ) : null}
            </div>
          </div>
          <HeaderActions
            command={command}
            feedbackPanelOpen={feedbackPanelOpen}
            onToggleFeedbackPanel={() => setFeedbackPanelOpen((current) => !current)}
            payload={payload}
          />
        </div>
      </header>

      <NoticeToast message={notice} onDismiss={() => setNotice(null)} />
      {command.isError ? <PanelMessage tone="error">{errorMessage(command.error, t("command_error"))}</PanelMessage> : null}
      {payload.job.state === "queued" && payload.repository.landing_paused && payload.repository.main_health !== "healthy" ? (
        <div className="flex items-center gap-3 rounded border border-amber-200 bg-amber-50 px-4 py-3 text-sm dark:border-amber-900 dark:bg-amber-950/40" role="alert">
          <span className="text-amber-800 dark:text-amber-200">{t("main_branch_health_waiting")}</span>
          <Link className="shrink-0 rounded border border-amber-300 bg-white px-2 py-1 text-xs font-medium text-amber-800 hover:bg-amber-50 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-200 dark:hover:bg-amber-900" to={withRoutePrefix(payload.repository.repository_path, prefix)}>
            {t("main_branch_health_view")}
          </Link>
        </div>
      ) : null}
      {feedbackPanelOpen ? (
        <JobFeedbackPanel
          error={feedback.error}
          isPending={feedback.isPending}
          onCancel={() => setFeedbackPanelOpen(false)}
          onSubmit={(body) => feedback.mutate(body)}
        />
      ) : null}

      <TabNav active={activeTab} attachmentsCount={(payload.attachments ?? []).length} workflowsCount={payload.job.workflows_count} onSelect={onSelectTab} />

      {activeTab === "summary" ? <SummaryTab command={command} payload={payload} prefix={prefix} queryKey={queryKey} /> : null}
      {activeTab === "workflows" ? <WorkflowsTab command={command} payload={payload} prefix={prefix} /> : null}
      {activeTab === "attachments" ? <AttachmentsTab payload={payload} queryKey={queryKey} onNotice={setNotice} /> : null}
      {activeTab === "source" ? <SourceTab jobId={String(payload.job.id)} coverageInfo={latestWorkflowCoverage(payload.workflows)} /> : null}
    </>
  )
}

function ChatBubbleIcon() {
  return (
    <svg aria-hidden="true" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" viewBox="0 0 24 24">
      <path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 17 0Z" />
    </svg>
  )
}

function HeaderActions({ payload, command, feedbackPanelOpen, onToggleFeedbackPanel }: { payload: JobDetailPayload; command: ReturnType<typeof useJobCommand>; feedbackPanelOpen: boolean; onToggleFeedbackPanel: () => void }) {
  const { t } = useT("jobs")
  const [retryFeedbackOpen, setRetryFeedbackOpen] = useState(false)
  const actions = headerActions(payload, t)
  const visibleKeys = primaryHeaderActionKeys(payload, actions)
  const visibleActions = visibleKeys.map((key) => actions.find((action) => action.key === key)).filter((action): action is HeaderAction => Boolean(action))
  const overflowActions = actions.filter((action) => !visibleKeys.includes(action.key))
  const canGiveFeedback = ["implemented", "failed"].includes(payload.job.state)

  return (
    <>
      <div className="flex flex-wrap items-center justify-end gap-2">
        {canGiveFeedback ? (
          <button
            aria-expanded={feedbackPanelOpen}
            className={buttonClass("secondary")}
            onClick={onToggleFeedbackPanel}
            type="button"
          >
            {t("give_feedback")}
          </button>
        ) : null}
        {visibleActions.map((action) => (
          <CommandButton command={command} input={action.input} key={action.key} tone={action.tone}>{action.label}</CommandButton>
        ))}
        {overflowActions.length > 0 ? <HeaderActionsMenu actions={overflowActions} command={command} onRetryFeedback={() => setRetryFeedbackOpen(true)} /> : null}
      </div>
      {retryFeedbackOpen ? (
        <RetryFeedbackDialog
          command={command}
          onClose={() => setRetryFeedbackOpen(false)}
          path={payload.actions.retry_implementation_action?.path || payload.paths.app_run_again_path}
        />
      ) : null}
    </>
  )
}

function JobFeedbackPanel({ error, isPending, onCancel, onSubmit }: { error: Error | null; isPending: boolean; onCancel: () => void; onSubmit: (body: string) => void }) {
  const { t } = useT("jobs")
  const [body, setBody] = useState("")
  const trimmedBody = body.trim()

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!trimmedBody) return

    onSubmit(trimmedBody)
  }

  return (
    <section aria-labelledby="job-feedback-title" className="rounded border border-blue-200 bg-blue-50/60 p-4 dark:border-blue-900/60 dark:bg-blue-950/20">
      <form className="space-y-3" onSubmit={submit}>
        <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100" id="job-feedback-title">{t("feedback_panel_title")}</h2>
        <textarea
          className="w-full rounded border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:outline-blue-600 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100"
          disabled={isPending}
          onChange={(event) => setBody(event.target.value)}
          placeholder={t("feedback_placeholder")}
          rows={4}
          value={body}
        />
        {error ? <p className="text-sm text-red-700 dark:text-red-300" role="alert">{errorMessage(error, t("feedback_error"))}</p> : null}
        <div className="flex flex-wrap justify-end gap-2">
          <button className={buttonClass("secondary")} disabled={isPending} onClick={onCancel} type="button">{t("cancel")}</button>
          <button className={buttonClass("primary")} disabled={isPending || !trimmedBody} type="submit">
            {isPending ? t("submitting") : t("submit_feedback")}
          </button>
        </div>
      </form>
    </section>
  )
}

function headerActions(payload: JobDetailPayload, t: ReturnType<typeof useT>["t"]): HeaderAction[] {
  const actions = payload.actions
  const paths = payload.paths
  const available: HeaderAction[] = []

  if (actions.can_start) available.push({ key: "start", label: t("start_run"), input: { method: "post", path: paths.app_start_path }, tone: "primary" })
  if (actions.can_poll_feedback) available.push({ key: "poll_feedback", label: t("check_feedback"), input: { method: "post", path: paths.app_poll_feedback_path }, tone: "secondary" })
  if (actions.can_rebase) available.push({ key: "rebase", label: t("rebase_now"), input: { method: "post", path: paths.app_rebase_path }, tone: "secondary" })
  if (actions.can_check_mergeability) available.push({ key: "check_mergeability", label: t("check_mergeability"), input: { method: "post", path: paths.app_check_mergeability_path }, tone: "secondary" })
  if (actions.retry_failed_step_action) available.push({ key: "retry_failed_step", label: actions.retry_failed_step_action.label, input: { method: "post", path: actions.retry_failed_step_action.path }, tone: "primary" })
  if (actions.retry_implementation_action) available.push({ key: "retry_implementation", label: actions.retry_implementation_action.label, input: { method: "post", path: actions.retry_implementation_action.path }, tone: "primary" })
  if (actions.retry_implementation_action) available.push({ key: "retry_feedback", label: t("retry_with_feedback"), input: { method: "post", path: actions.retry_implementation_action.path }, tone: "secondary" })
  if (actions.can_restart) available.push({ key: "restart", label: t("start_over"), input: { method: "post", path: paths.app_restart_path, confirm: t("confirm_start_over") }, tone: "secondary" })
  if (actions.can_approve) available.push({ key: "approve", label: payload.job.landing_failure_reason ? t("reapprove") : t("approve"), input: { method: "post", path: paths.app_approve_path }, tone: "success" })
  if (actions.can_unapprove) available.push({ key: "unapprove", label: t("unapprove"), input: { method: "post", path: paths.app_unapprove_path, confirm: t("confirm_unapprove") }, tone: "secondary" })
  if (actions.can_open_in_local_mode) available.push({ key: "open_in_local_mode", label: t("open_in_local_mode"), input: { method: "post", path: paths.app_open_in_local_mode_path }, tone: "secondary" })
  if (actions.can_cancel_local_mode) available.push({ key: "cancel_local_mode", label: t("cancel_local_mode"), input: { method: "post", path: paths.app_cancel_local_mode_path, confirm: t("confirm_cancel_local_mode") }, tone: "danger" })
  if (actions.can_cancel) available.push({ key: "cancel", label: t("cancel"), input: { method: "post", path: paths.app_cancel_path, confirm: t("confirm_cancel") }, tone: "danger" })
  if (actions.can_reopen) available.push({ key: "reopen", label: t("reopen"), input: { method: "post", path: paths.app_reopen_path }, tone: "success" })
  if (actions.can_mark_valid) available.push({ key: "mark_valid", label: t("mark_valid"), input: { method: "post", path: paths.app_mark_valid_path }, tone: "secondary" })
  if (actions.can_open_in_coding_mode) available.push({ key: "open_in_coding_mode", label: t("open_in_coding_mode"), input: { method: "post", path: paths.app_open_in_coding_mode_path }, tone: "secondary" })
  available.push({ key: "pin", label: payload.pinned ? t("unpin") : t("pin"), input: payload.pinned ? { method: "delete", path: paths.app_pin_path } : { method: "post", path: paths.app_pin_path }, tone: "secondary" })

  return available
}

function primaryHeaderActionKeys(payload: JobDetailPayload, actions: HeaderAction[]) {
  const availableKeys = new Set(actions.map((action) => action.key))
  const jobState = payload.job.summary_state.toLowerCase()
  const keys: string[] = []

  function add(key: string) {
    if (availableKeys.has(key) && keys.length < 2) keys.push(key)
  }

  if (payload.job.any_active_run || jobState === "running") {
    add("cancel")
  } else if (jobState === "coding") {
    add("cancel_local_mode")
  } else if (availableKeys.has("approve")) {
    add("approve")
    add("retry_failed_step")
  } else if (jobState === "failed") {
    add("retry_failed_step")
    add("retry_implementation")
    add("restart")
  } else if (availableKeys.has("reopen")) {
    add("reopen")
  } else if (availableKeys.has("retry_failed_step")) {
    add("retry_failed_step")
  } else if (availableKeys.has("retry_implementation")) {
    add("retry_implementation")
  } else {
    add("start")
    add("mark_valid")
  }

  return keys
}

function HeaderActionsMenu({ actions, command, onRetryFeedback }: { actions: HeaderAction[]; command: ReturnType<typeof useJobCommand>; onRetryFeedback: () => void }) {
  const [open, setOpen] = useState(false)
  const [alignRight, setAlignRight] = useState(true)
  const menuRef = useDismissiblePopup<HTMLDivElement>(open, () => setOpen(false))
  const buttonRef = useRef<HTMLButtonElement>(null)

  function handleToggle() {
    if (!open && buttonRef.current) {
      // w-56 = 224px; open left only when the button has enough room to the left
      setAlignRight(buttonRef.current.getBoundingClientRect().right >= 224)
    }
    setOpen((current) => !current)
  }

  return (
    <div className="relative" ref={menuRef}>
      <button
        aria-expanded={open}
        aria-haspopup="menu"
        className={buttonClass("secondary")}
        disabled={command.isPending}
        onClick={handleToggle}
        ref={buttonRef}
        type="button"
      >
        ⋯
      </button>
      {open ? (
        <div className={`absolute ${alignRight ? "right-0" : "left-0"} z-20 mt-2 w-56 rounded border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-700 dark:bg-gray-900`} role="menu">
          {actions.map((action) => (
            <button
              className={menuButtonClass(action.tone)}
              disabled={command.isPending}
              key={action.key}
              onClick={() => {
                setOpen(false)
                if (action.key === "retry_feedback") {
                  onRetryFeedback()
                  return
                }
                command.mutate(action.input)
              }}
              role="menuitem"
              type="button"
            >
              {action.label}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  )
}

function RetryFeedbackDialog({ command, path, onClose }: { command: ReturnType<typeof useJobCommand>; path: string; onClose: () => void }) {
  const { t } = useT("jobs")
  const [feedback, setFeedback] = useState("")
  const trimmedFeedback = feedback.trim()

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!trimmedFeedback) return

    command.mutate(
      { method: "post", path, body: { retry_context: trimmedFeedback } },
      { onSuccess: onClose }
    )
  }

  return (
    <div className="fixed inset-0 z-30 flex items-center justify-center bg-gray-900/40 p-4" role="presentation">
      <section aria-labelledby="retry-feedback-title" className="w-full max-w-lg rounded border border-gray-200 bg-white p-4 shadow-xl dark:border-gray-700 dark:bg-gray-900" role="dialog" aria-modal="true">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100" id="retry-feedback-title">{t("retry_feedback_title")}</h2>
            <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">{t("retry_feedback_description")}</p>
          </div>
          <button
            aria-label={t("close_retry_feedback")}
            className="inline-flex h-8 w-8 items-center justify-center rounded text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200"
            disabled={command.isPending}
            onClick={onClose}
            type="button"
          >
            <CloseIcon className="h-4 w-4" />
          </button>
        </div>
        <form className="mt-4 space-y-3" onSubmit={submit}>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300" htmlFor="retry-feedback-text">
            {t("retry_feedback_label")}
          </label>
          <textarea
            autoFocus
            className="min-h-36 w-full rounded border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:outline-blue-600 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100"
            id="retry-feedback-text"
            onChange={(event) => setFeedback(event.target.value)}
            required
            value={feedback}
          />
          <div className="flex flex-wrap justify-end gap-2">
            <button className={buttonClass("secondary")} disabled={command.isPending} onClick={onClose} type="button">{t("cancel")}</button>
            <button className={buttonClass("primary")} disabled={command.isPending || !trimmedFeedback} type="submit">
              {command.isPending ? t("retrying") : t("retry")}
            </button>
          </div>
        </form>
      </section>
    </div>
  )
}

function TagsPanel({ payload, command, embedded = false, canManageTags }: { payload: JobDetailPayload; command: ReturnType<typeof useJobCommand>; embedded?: boolean; canManageTags: boolean }) {
  const { t } = useT("jobs")
  const [tagName, setTagName] = useState("")
  const [addingTag, setAddingTag] = useState(false)

  if (payload.tags.length === 0 && !canManageTags) return null

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    command.mutate(
      { method: "post", path: payload.paths.app_tags_path, body: { tag_name: tagName } },
      { onSuccess: () => { setTagName(""); setAddingTag(false) } }
    )
  }

  const content = (
    <div className="space-y-2">
      <div className="flex min-w-0 flex-wrap items-center gap-2">
        <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{t("section_tags")}</h2>
        {payload.tags.map((tag) => (
          <span className="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-700 dark:bg-gray-800 dark:text-gray-200" key={tag.id}>
            {tag.name}
            {canManageTags ? (
              <button
                aria-label={t("tags_remove_aria", { name: tag.name })}
                className="inline-flex h-4 w-4 items-center justify-center rounded text-gray-400 hover:bg-gray-200 hover:text-red-600 dark:text-gray-500 dark:hover:bg-gray-700 dark:hover:text-red-300"
                disabled={command.isPending}
                onClick={() => command.mutate({ method: "delete", path: `${payload.paths.app_tags_path}/${tag.id}` })}
                title={t("tags_remove_aria", { name: tag.name })}
                type="button"
              >
                <CloseIcon className="h-3 w-3" />
              </button>
            ) : null}
          </span>
        ))}
      </div>
      {canManageTags ? (
        addingTag ? (
          <form className="flex items-center gap-2" onSubmit={submit}>
            <input className="w-40 rounded border border-gray-300 bg-white px-2 py-1.5 text-sm text-gray-900 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100" list="job-tag-options" onChange={(event) => setTagName(event.target.value)} placeholder={t("tags_placeholder")} required value={tagName} />
            <datalist id="job-tag-options">
              {payload.tag_options.map((tag) => <option key={tag.id} value={tag.name} />)}
            </datalist>
            <button className={buttonClass("secondary")} disabled={command.isPending} type="submit">{t("tags_add")}</button>
            <button className="text-xs text-gray-500 hover:underline disabled:cursor-not-allowed disabled:opacity-50" disabled={command.isPending} onClick={() => setAddingTag(false)} type="button">{t("tags_cancel")}</button>
          </form>
        ) : (
          <button className="text-xs font-medium text-blue-600 hover:underline" onClick={() => setAddingTag(true)} type="button">{t("tags_add_tag")}</button>
        )
      ) : null}
    </div>
  )

  if (embedded) {
    return (
      <div className="mt-3 border-t border-gray-100 pt-3 dark:border-gray-800">
        {content}
      </div>
    )
  }

  return (
    <section className="rounded border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-900">
      {content}
    </section>
  )
}

function TabNav({ active, workflowsCount, attachmentsCount, onSelect }: { active: JobTab; workflowsCount: number; attachmentsCount: number; onSelect: (tab: JobTab) => void }) {
  const { t } = useT("jobs")
  const tabs: Array<{ id: JobTab; label: string }> = [
    { id: "summary", label: t("tab_summary") },
    { id: "workflows", label: t("tab_workflows", { count: workflowsCount }) },
    { id: "attachments", label: t("tab_attachments", { count: attachmentsCount }) },
    { id: "source", label: t("tab_source") }
  ]

  return (
    <div className="flex overflow-x-auto border-b border-gray-200 dark:border-gray-700">
      {tabs.map((tab) => (
        <button
          className={`shrink-0 border-b-2 px-4 py-2 text-sm font-medium ${active === tab.id ? "border-blue-600 text-blue-600 dark:border-blue-400 dark:text-blue-300" : "border-transparent text-gray-500 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200"}`}
          key={tab.id}
          onClick={() => onSelect(tab.id)}
          type="button"
        >
          {tab.label}
        </button>
      ))}
    </div>
  )
}

function NeedsAttentionBanner({ job }: { job: JobDetailPayload["job"] }) {
  const { t } = useT("jobs")
  if (!job.needs_attention) return null

  const reasonKeys: Record<string, string> = {
    fork_pr_closed: "attention_fork_pr_closed",
    fork_pr_changes_requested: "attention_fork_pr_changes_requested",
    upstream_pr_closed: "attention_upstream_pr_closed",
    upstream_pr_changes_requested: "attention_upstream_pr_changes_requested"
  }

  const message = job.needs_attention_reason
    ? (reasonKeys[job.needs_attention_reason]
        ? t(reasonKeys[job.needs_attention_reason])
        : t("attention_reason_fallback", { reason: job.needs_attention_reason }))
    : t("attention_generic")

  const gracePeriodText = job.grace_period_expires_at ? (() => {
    const expires = new Date(job.grace_period_expires_at)
    const now = new Date()
    const ms = expires.getTime() - now.getTime()
    if (ms <= 0) return t("grace_expired")
    const totalSeconds = Math.floor(ms / 1000)
    const days = Math.floor(totalSeconds / 86400)
    const hours = Math.floor((totalSeconds % 86400) / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    if (days > 0) return t("grace_cleanup_days", { days, hours })
    if (hours > 0) return t("grace_cleanup_hours", { hours, minutes })
    return t("grace_cleanup_minutes", { minutes })
  })() : null

  return (
    <div className="rounded border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-200">
      <p className="font-medium">{t("action_needed")}</p>
      <p className="mt-1">{message}</p>
      {gracePeriodText ? <p className="mt-1 text-amber-700 dark:text-amber-300">{gracePeriodText}</p> : null}
    </div>
  )
}

function SummaryTab({ payload, command, prefix, queryKey }: { payload: JobDetailPayload; command: ReturnType<typeof useJobCommand>; prefix: string; queryKey: JobDetailQueryKey }) {
  const { t } = useT("jobs")
  const coverageInfo = latestWorkflowCoverage(payload.workflows)
  return (
    <div className="space-y-4">
      <NeedsAttentionBanner job={payload.job} />
      {payload.landing_queue_entry ? (
        <PanelMessage>
          {t("landing_queue_position", { position: payload.landing_queue_entry.position })}
          {payload.landing_queue_entry.blocked_reason ? ` (${payload.landing_queue_entry.blocked_reason})` : ""}
          {payload.landing_queue_entry.waiting_for_jobs.length > 0 ? (
            <>
              {" "}
              {t("landing_queue_waiting_for")} {payload.landing_queue_entry.waiting_for_jobs.map((job, index) => (
                <span key={job.id}>
                  {index > 0 ? ", " : null}
                  <Link className="font-medium text-blue-700 underline hover:no-underline" to={`${prefix}${job.job_path}`}>
                    {job.label} {job.title}
                  </Link>
                </span>
              ))}
            </>
          ) : null}
        </PanelMessage>
      ) : null}
      {payload.job.landing_failure_reason ? <PanelMessage tone="error">{t("landing_failed", { reason: payload.job.landing_failure_reason })}</PanelMessage> : null}
      <RetryStatePanel payload={payload} />
      {payload.unsatisfied_dependencies.length > 0 ? <UnsatisfiedDependencies command={command} payload={payload} prefix={prefix} /> : null}

      <div className="grid gap-4 lg:grid-cols-[62%_38%]">
        <div className="space-y-4">
          <section className="rounded border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-900">
            <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{t("section_issue")}</h2>
            {payload.job.issue_body ? <Markdown className="chat-prose mt-2 text-sm text-gray-700 dark:text-gray-300" text={payload.job.issue_body} /> : <p className="mt-2 text-sm text-gray-400 dark:text-gray-500">{t("no_issue_body")}</p>}
          </section>
          <section className="rounded border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-900">
            <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{t("section_agent_summary")}</h2>
            {payload.summary ? <p className="mt-2 whitespace-pre-wrap text-sm text-gray-700 dark:text-gray-300">{payload.summary.text}</p> : <p className="mt-2 text-sm text-gray-400 dark:text-gray-500">{t("no_summary")}</p>}
          </section>

          <TestPlanPanel testPlan={payload.test_plan} />

          {coverageInfo ? <CoverageCard coverage={coverageInfo.coverage} /> : null}

          <PendingFeedbackPanel jobId={payload.job.id} comments={payload.pending_feedback} queryKey={queryKey} />

          <FeedbackHistoryPanel prefix={prefix} workflows={payload.workflows} />

          <TimelinePanel canView={payload.actions.can_view_timeline} jobId={payload.job.id} prefix={prefix} runsCount={payload.job.runs_count} />
          <AttachmentPreview attachments={payload.attachments} />
        </div>

        <div className="space-y-4">
          <section className="rounded border border-gray-200 bg-white p-4 text-sm dark:border-gray-700 dark:bg-gray-900">
            <h2 className="font-semibold text-gray-900 dark:text-gray-100">{t("section_details")}</h2>
            <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3">
              <KeyValue label={t("detail_state")}><StatusPill state={payload.job.summary_state} /></KeyValue>
              <KeyValue label={t("detail_owner")}><JobOwnerLabel command={command} payload={payload} prefix={prefix} /></KeyValue>
              <KeyValue label={t("detail_priority")}><SmallPill>{payload.job.priority}</SmallPill></KeyValue>
              <KeyValue label={t("detail_validity")}><span className="capitalize">{payload.job.validity}</span></KeyValue>
              {payload.epic ? <KeyValue label={t("detail_epic")}><EpicSummaryLink epic={payload.epic} prefix={prefix} /></KeyValue> : null}
              {payload.job.branch_name ? <KeyValue label={t("detail_branch")}><code className="break-all">{payload.job.branch_name}</code></KeyValue> : null}
              <KeyValue label={t("detail_stack_base")}><StackBaseForm command={command} payload={payload} /></KeyValue>
              {payload.job.pr_number || payload.job.external_pr_number ? <KeyValue label={t("detail_pull_request")}><PullRequestSummary payload={payload} /></KeyValue> : null}
              <KeyValue label={t("detail_cost")}>{payload.job.total_cost_usd == null ? "-" : formatCurrency(payload.job.total_cost_usd)} <span className="text-xs text-gray-400 dark:text-gray-500">({payload.job.billed_runs_count} {t("detail_billed")})</span></KeyValue>
              <KeyValue label={t("detail_started")}>{formatDate(payload.job.started_at)}</KeyValue>
              {payload.job.finished_at ? <KeyValue label={t("detail_closed")}>{formatDate(payload.job.finished_at)} ({payload.job.closure_reason || "unspecified"})</KeyValue> : null}
            </div>
            <TagsPanel canManageTags={payload.actions.can_manage_tags} embedded command={command} payload={payload} />
          </section>

          <ApprovalStatusPanel payload={payload} />
          <DependenciesPanel command={command} payload={payload} prefix={prefix} />
        </div>
      </div>
    </div>
  )
}

export function TestPlanPanel({ testPlan }: { testPlan: JobTestPlan | null }) {
  const { t } = useT("jobs")
  if (!testPlan || (testPlan.steps.length === 0 && !testPlan.notes)) return null

  return (
    <section className="rounded border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-900">
      <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{t("section_test_plan")}</h2>
      <ol className="mt-2 list-decimal space-y-1 pl-5 text-sm text-gray-700 dark:text-gray-300">
        {testPlan.steps.map((step, index) => <li key={`${index}-${step}`}>{step}</li>)}
      </ol>
      {testPlan.notes ? <p className="mt-3 whitespace-pre-wrap text-sm text-gray-700 dark:text-gray-300">{testPlan.notes}</p> : null}
    </section>
  )
}

function PendingFeedbackPanel({ jobId, comments = [], queryKey }: { jobId: number; comments?: PendingFeedbackComment[]; queryKey: JobDetailQueryKey }) {
  const { t } = useT("jobs")
  const queryClient = useQueryClient()
  const [replaceId, setReplaceId] = useState<number | null>(null)
  const [replaceBody, setReplaceBody] = useState("")
  const [notice, setNotice] = useState<string | null>(null)

  const apply = useMutation({
    mutationFn: (commentId: number) => applyPendingFeedback(jobId, commentId),
    onSuccess: (data) => {
      setNotice(data.message)
      void queryClient.invalidateQueries({ queryKey })
    }
  })

  const ignore = useMutation({
    mutationFn: (commentId: number) => ignorePendingFeedback(jobId, commentId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey })
    }
  })

  const replace = useMutation({
    mutationFn: ({ commentId, body }: { commentId: number; body: string }) => replacePendingFeedback(jobId, commentId, body),
    onSuccess: (data) => {
      setReplaceId(null)
      setReplaceBody("")
      setNotice(data.message)
      void queryClient.invalidateQueries({ queryKey })
    }
  })

  if (comments.length === 0) return null

  const isPending = apply.isPending || ignore.isPending || replace.isPending

  return (
    <section className="rounded border border-amber-200 bg-amber-50 p-4 dark:border-amber-800/60 dark:bg-amber-950/30">
      <h2 className="text-sm font-semibold text-amber-900 dark:text-amber-200">{t("pending_feedback_title")}</h2>
      <p className="mt-1 text-xs text-amber-700 dark:text-amber-400">
        {t("pending_feedback_description")}
      </p>
      {notice ? (
        <div className="mt-2 flex items-center justify-between gap-2 rounded bg-amber-100 px-3 py-2 text-xs text-amber-800 dark:bg-amber-900/40 dark:text-amber-300">
          <span>{notice}</span>
          <button className="ml-2 hover:underline" onClick={() => setNotice(null)} type="button">{t("dismiss")}</button>
        </div>
      ) : null}
      {(apply.isError || ignore.isError || replace.isError) ? (
        <p className="mt-2 text-xs text-red-600 dark:text-red-400">
          {apply.error instanceof Error ? apply.error.message : ignore.error instanceof Error ? ignore.error.message : replace.error instanceof Error ? replace.error.message : "Action failed."}
        </p>
      ) : null}
      <div className="mt-3 space-y-3">
        {comments.map((comment) => (
          <div className="rounded border border-amber-200 bg-white p-3 dark:border-amber-800/40 dark:bg-gray-900" key={comment.id}>
            <div className="flex flex-wrap items-center gap-2 text-xs text-amber-700 dark:text-amber-400">
              {comment.github_handle ? <span className="font-medium">@{comment.github_handle}</span> : null}
              <span className="capitalize">{comment.attributed_to}</span>
              <span>·</span>
              <span className="capitalize">{comment.pr_type} PR</span>
              {comment.comment_created_at ? <span>· {formatDate(comment.comment_created_at)}</span> : null}
            </div>
            <p className="mt-2 whitespace-pre-wrap break-words text-sm text-gray-700 dark:text-gray-300">{comment.body}</p>
            {replaceId === comment.id ? (
              <div className="mt-3 space-y-2">
                <textarea
                  aria-label={t("replacement_feedback_aria")}
                  className="block w-full rounded border border-gray-300 bg-white px-3 py-2 text-sm focus:outline-blue-600 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200"
                  onChange={(e) => setReplaceBody(e.target.value)}
                  placeholder={t("replacement_feedback_placeholder")}
                  rows={3}
                  value={replaceBody}
                />
                <div className="flex gap-2">
                  <button
                    className="rounded bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
                    disabled={isPending || !replaceBody.trim()}
                    onClick={() => replace.mutate({ commentId: comment.id, body: replaceBody })}
                    type="button"
                  >
                    Submit replacement
                  </button>
                  <button
                    className="text-xs text-gray-500 hover:underline dark:text-gray-400"
                    onClick={() => { setReplaceId(null); setReplaceBody("") }}
                    type="button"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            ) : (
              <div className="mt-3 flex flex-wrap gap-2">
                <button
                  className="rounded bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
                  disabled={isPending}
                  onClick={() => apply.mutate(comment.id)}
                  type="button"
                >
                  Apply
                </button>
                <button
                  className="rounded border border-gray-300 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
                  disabled={isPending}
                  onClick={() => { setReplaceId(comment.id); setReplaceBody("") }}
                  type="button"
                >
                  Replace
                </button>
                <button
                  className="text-xs text-gray-500 hover:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-400"
                  disabled={isPending}
                  onClick={() => ignore.mutate(comment.id)}
                  type="button"
                >
                  Ignore
                </button>
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  )
}

export function FeedbackHistoryPanel({ workflows, prefix }: { workflows: JobWorkflow[]; prefix: string }) {
  const { t } = useT("jobs")
  const feedbackWorkflows = [...workflows]
    .filter((workflow) => workflow.trigger_kind === "chat_feedback" || workflow.trigger_kind === "pr_comment")
    .sort((left, right) => workflowCreatedAtTime(right) - workflowCreatedAtTime(left))

  if (feedbackWorkflows.length === 0) return null

  return (
    <section className="rounded border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-900">
      <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{t("section_feedback_history")}</h2>
      <div className="mt-3">
        {feedbackWorkflows.map((workflow) => {
          const artifacts = workflow.artifacts ?? {}
          const chatFeedback = artifacts.chat_feedback
          return (
            <div className="mt-3 border-t border-gray-100 pt-3 first:mt-0 first:border-t-0 first:pt-0 dark:border-gray-800" key={workflow.id}>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{feedbackTriggerLabel(workflow.trigger_kind, t)}</span>
                  <StatusPill state={workflow.state} />
                </div>
                <div className="flex flex-wrap items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                  <span>{formatDate(workflow.created_at)}</span>
                  <Link className="text-blue-600 hover:underline dark:text-blue-300" to={withRoutePrefix(workflow.path, prefix)}>
                    {workflow.slug || workflowSlug(workflow.id)}
                  </Link>
                </div>
              </div>
              {workflow.trigger_kind === "chat_feedback" ? (
                <>
                  <FeedbackSourceBadge source={artifacts.feedback_source} />
                  <pre className="mt-2 whitespace-pre-wrap break-words text-sm text-gray-700 dark:text-gray-300">{typeof chatFeedback === "string" ? chatFeedback : ""}</pre>
                </>
              ) : (
                <p className="mt-2 text-sm text-gray-700 dark:text-gray-300">{t("feedback_trigger_pr_review_text")}</p>
              )}
            </div>
          )
        })}
      </div>
    </section>
  )
}

function FeedbackSourceBadge({ source }: { source: unknown }) {
  if (!source || typeof source !== "object") return null

  const s = source as Record<string, unknown>
  const attributedTo = typeof s.attributed_to === "string" ? s.attributed_to : null
  const githubHandle = typeof s.github_handle === "string" ? s.github_handle : null
  const action = typeof s.action === "string" ? s.action : null
  const confirmedBy = typeof s.confirmed_by === "string" ? s.confirmed_by : null

  if (!attributedTo && !githubHandle) return null

  const label = [
    githubHandle ? `@${githubHandle}` : null,
    attributedTo,
    confirmedBy ? `confirmed by ${confirmedBy}` : null,
    action === "replace" ? "(replaced)" : null
  ].filter(Boolean).join(" · ")

  return (
    <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">{label}</p>
  )
}

function feedbackTriggerLabel(triggerKind: string, t: ReturnType<typeof useT>["t"]) {
  if (triggerKind === "chat_feedback") return t("feedback_trigger_chat")
  if (triggerKind === "pr_comment") return t("feedback_trigger_pr")
  return triggerKind.replaceAll("_", " ")
}

function EpicSummaryLink({ epic, prefix }: { epic: NonNullable<JobDetailPayload["epic"]>; prefix: string }) {
  return (
    <Link className="text-blue-600 hover:underline" to={withRoutePrefix(epic.epic_path, prefix)}>
      {epic.display_number} {epic.title}
    </Link>
  )
}

function RetryStatePanel({ payload }: { payload: JobDetailPayload }) {
  const { t } = useT("jobs")
  const retry = payload.job.retry_state
  if (!retry || (retry.state_label === "No failure" && !retry.classification)) return null

  return (
    <section className={`rounded border px-4 py-3 text-sm ${retry.auto_retry_exhausted ? "border-red-200 bg-red-50 text-red-800 dark:border-red-900/70 dark:bg-red-950/40 dark:text-red-200" : retry.provider_circuit_open ? "border-amber-200 bg-amber-50 text-amber-900 dark:border-amber-900/70 dark:bg-amber-950/40 dark:text-amber-200" : "border-gray-200 bg-white text-gray-700 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300"}`}>
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-semibold">{retry.state_label}</span>
        <SmallPill>{retry.classification_label}</SmallPill>
        <SmallPill>{retry.retryable ? t("run_retryable") : t("run_not_retryable")}</SmallPill>
        <SmallPill>{retry.retry_attempt_count}/{retry.retry_budget} {t("retry_attempts_label")}</SmallPill>
        <SmallPill>{retry.retry_budget_remaining} {t("retry_remaining_label")}</SmallPill>
      </div>
      <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs">
        {retry.next_auto_retry_at ? <span>{t("retry_state_next_retry")} {formatDate(retry.next_auto_retry_at)}</span> : null}
        {retry.retry_delayed_until ? <span>{t("retry_state_delayed_until")} {formatDate(retry.retry_delayed_until)}</span> : null}
        {retry.retry_delay_reason ? <span>{retry.retry_delay_reason}</span> : null}
      </div>
    </section>
  )
}

function JobOwnerLabel({ payload, command, prefix }: { payload: JobDetailPayload; command: ReturnType<typeof useJobCommand>; prefix: string }) {
  const { t } = useT("jobs")
  const owner = payload.job.claimed_by_user

  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      {owner ? (
        <>
          <Link className="font-medium text-blue-700 hover:underline" to={withRoutePrefix(owner.profile_path, prefix)}>
            {payload.job.claimed_by_current_user ? t("owner_you") : owner.display_name}
          </Link>
          {payload.job.claimed_at ? <span className="text-xs text-gray-400 dark:text-gray-500">{formatDate(payload.job.claimed_at)}</span> : null}
        </>
      ) : (
        <span className="text-gray-400 dark:text-gray-500">{t("owner_unclaimed")}</span>
      )}
      {payload.actions.can_claim ? (
        <button className="text-xs font-medium text-blue-600 hover:underline disabled:cursor-not-allowed disabled:opacity-50" disabled={command.isPending} onClick={() => command.mutate({ method: "post", path: payload.paths.app_claim_path })} type="button">{t("owner_claim")}</button>
      ) : null}
      {payload.actions.can_unclaim ? (
        <button className="text-xs text-gray-500 hover:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-400" disabled={command.isPending} onClick={() => command.mutate({ method: "delete", path: payload.paths.app_claim_path })} type="button">{t("owner_release")}</button>
      ) : null}
    </span>
  )
}

function UnsatisfiedDependencies({ payload, command, prefix }: { payload: JobDetailPayload; command: ReturnType<typeof useJobCommand>; prefix: string }) {
  const { t } = useT("jobs")
  const count = payload.unsatisfied_dependencies.length
  return (
    <section className="rounded border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900/70 dark:bg-amber-950/40 dark:text-amber-200">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <span className="font-medium">{t("blocked_on", { count })}</span>
          <span className="ml-2 inline-flex flex-wrap gap-x-2 gap-y-1">
            {payload.unsatisfied_dependencies.map((dependency, index) => (
              <span key={dependency.id}>
                {index > 0 ? <span className="mr-2">,</span> : null}
                <DependencyLink dependency={dependency} prefix={prefix} />
              </span>
            ))}
          </span>
          <span className="ml-1">{count === 1 ? t("blocked_auto_start_one") : t("blocked_auto_start_other")}</span>
        </div>
        {payload.actions.can_override_dependencies ? (
          <CommandButton command={command} input={{ method: "post", path: payload.paths.app_dependency_override_path, confirm: t("confirm_override_dependencies") }} tone="danger-outline">
            {t("override_and_force_run")}
          </CommandButton>
        ) : null}
      </div>
    </section>
  )
}

function StackBaseForm({ payload, command }: { payload: JobDetailPayload; command: ReturnType<typeof useJobCommand> }) {
  const { t } = useT("jobs")
  const [stackBase, setStackBase] = useState(payload.job.stack_base)

  useEffect(() => setStackBase(payload.job.stack_base), [payload.job.stack_base])

  return (
    <form className="flex flex-wrap items-center gap-2" onSubmit={(event) => {
      event.preventDefault()
      command.mutate({ method: "patch", path: payload.paths.app_stack_base_path, body: { stack_base: stackBase } })
    }}>
      <select className="rounded border border-gray-300 bg-white px-2 py-1 text-xs text-gray-900 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100" onChange={(event) => setStackBase(event.target.value)} value={stackBase}>
        <option value="auto">auto</option>
        <option value="main">main</option>
      </select>
      <button className="text-xs text-blue-600 hover:underline" disabled={command.isPending} type="submit">{t("stack_base_update")}</button>
    </form>
  )
}

function PullRequestSummary({ payload }: { payload: JobDetailPayload }) {
  const { t } = useT("jobs")
  if (!payload.job.pr_number && !payload.job.external_pr_number) return <span className="text-gray-400 dark:text-gray-500">-</span>

  return (
    <div className="space-y-1">
      {payload.job.pr_number ? <a className="text-blue-600 hover:underline" href={payload.job.pr_url || "#"} rel="noopener" target="_blank">{t("pr_syrus", { number: payload.job.pr_number })}</a> : null}
      {payload.job.external_pr_number ? <a className="block text-violet-700 hover:underline" href={payload.job.external_pr_url || "#"} rel="noopener" target="_blank">{t("pr_external", { number: payload.job.external_pr_number })}</a> : null}
      <div><MergeablePill value={payload.job.pr_mergeable} /> {payload.job.pr_mergeable_checked_at ? <span className="text-xs text-gray-400 dark:text-gray-500">{t("pr_checked")} {formatDate(payload.job.pr_mergeable_checked_at)}</span> : null}</div>
    </div>
  )
}

function ApprovalStatusPanel({ payload }: { payload: JobDetailPayload }) {
  const { t } = useT("jobs")
  const { job, repository } = payload
  const status: JobApprovalStatus | null = job.approval_status
  const approvals: JobApprovalRecord[] = job.job_approvals ?? []

  const policyLabel: Record<string, string> = {
    self: t("approval_policy_self"),
    two_person: t("approval_policy_two_person"),
    final_say: t("approval_policy_final_say")
  }

  if (!status && approvals.length === 0 && repository.review_policy === "self") return null

  return (
    <div className="rounded border border-gray-200 bg-white p-4 text-sm dark:border-gray-700 dark:bg-gray-900">
      <h2 className="font-semibold text-gray-900 dark:text-gray-100">{t("section_approval")}</h2>
      <div className="mt-2 space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-gray-500 dark:text-gray-400">{t("approval_policy")}</span>
          <span className="text-gray-700 dark:text-gray-300">{policyLabel[repository.review_policy] ?? repository.review_policy}</span>
        </div>
        {status && (
          <div className="flex items-center justify-between">
            <span className="text-gray-500 dark:text-gray-400">{t("approval_status")}</span>
            {status.satisfied
              ? <span className="font-medium text-emerald-600 dark:text-emerald-400">{t("approval_satisfied")}</span>
              : <span className="text-amber-600 dark:text-amber-400">{status.pending_description ?? t("approval_pending")}</span>
            }
          </div>
        )}
        {approvals.length > 0 ? (
          <div>
            <span className="text-gray-500 dark:text-gray-400">{t("approval_approvals")}</span>
            <ul className="mt-1 divide-y divide-gray-100 dark:divide-gray-800">
              {approvals.map((approval) => (
                <li key={approval.id} className="flex items-center justify-between py-1 text-xs">
                  <span className="truncate text-gray-700 dark:text-gray-300">{approval.user_email}</span>
                  <span className="ml-2 shrink-0 text-gray-400 dark:text-gray-500">{new Date(approval.approved_at).toLocaleDateString()}</span>
                </li>
              ))}
            </ul>
          </div>
        ) : (
          <p className="text-xs text-gray-400 dark:text-gray-500">{t("no_approvals")}</p>
        )}
      </div>
    </div>
  )
}

function DependenciesPanel({ payload, command, prefix }: { payload: JobDetailPayload; command: ReturnType<typeof useJobCommand>; prefix: string }) {
  const { t } = useT("jobs")
  const [query, setQuery] = useState("")
  const [addingDependency, setAddingDependency] = useState(false)

  const trimmedQuery = query.trim()
  const filteredOptions = trimmedQuery.length > 0
    ? payload.dependency_target_options.filter((option) => option.label.toLowerCase().includes(trimmedQuery.toLowerCase()))
    : payload.dependency_target_options

  function choose(value: string) {
    command.mutate({ method: "post", path: payload.paths.app_dependencies_path, body: { dependency_target: value } }, { onSuccess: () => {
      setQuery("")
      setAddingDependency(false)
    }})
  }

  function cancelAdding() {
    setQuery("")
    setAddingDependency(false)
  }

  return (
    <div className="space-y-4">
      <div className="rounded border border-gray-200 bg-white p-4 text-sm dark:border-gray-700 dark:bg-gray-900">
        <h2 className="font-semibold text-gray-900 dark:text-gray-100">{t("section_dependencies")}</h2>
        {payload.dependencies.length > 0 ? (
          <ul className="mt-2 divide-y divide-gray-100 dark:divide-gray-800">
            {payload.dependencies.map((dependency) => (
              <li className="flex flex-wrap items-center justify-between gap-2 py-2" key={dependency.id}>
                <span><DependencyLink dependency={dependency} prefix={prefix} /> <span className="text-xs text-gray-400 dark:text-gray-500">({dependency.source})</span></span>
                {dependency.manual ? <button className="text-xs text-red-600 hover:underline" disabled={command.isPending} onClick={() => command.mutate({ method: "delete", path: `${payload.paths.app_dependencies_path}/${dependency.id}`, confirm: t("confirm_remove_dependency") })} type="button">{t("remove_dependency")}</button> : null}
              </li>
            ))}
          </ul>
        ) : <p className="mt-2 text-gray-400 dark:text-gray-500">{t("section_no_dependencies")}</p>}
        {addingDependency ? (
          <div className="mt-3 border-t border-gray-100 pt-3 dark:border-gray-800">
            <label className="block text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
              {t("dependency_search_label")}
              <div className="relative mt-1">
                <input
                  aria-autocomplete="list"
                  autoFocus
                  className="w-full rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100"
                  disabled={command.isPending}
                  onChange={(event) => setQuery(event.target.value)}
                  placeholder={t("dependency_search_placeholder")}
                  type="search"
                  value={query}
                />
                {filteredOptions.length > 0 ? (
                  <div className="absolute left-0 right-0 top-full z-20 mt-1 max-h-56 overflow-y-auto rounded border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-700 dark:bg-gray-900">
                    {filteredOptions.map((option) => (
                      <button
                        className="block w-full px-3 py-1.5 text-left text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50 dark:text-gray-200 dark:hover:bg-gray-800"
                        disabled={command.isPending}
                        key={option.value}
                        onClick={() => choose(option.value)}
                        type="button"
                      >
                        {option.label}
                      </button>
                    ))}
                  </div>
                ) : trimmedQuery.length > 0 ? (
                  <div className="absolute left-0 right-0 top-full z-20 mt-1 rounded border border-gray-200 bg-white px-3 py-1.5 text-sm text-gray-400 shadow-lg dark:border-gray-700 dark:bg-gray-900 dark:text-gray-500">{t("dependency_no_matches")}</div>
                ) : null}
              </div>
            </label>
            <button className="mt-2 text-xs text-gray-500 hover:underline disabled:cursor-not-allowed disabled:opacity-50" disabled={command.isPending} onClick={cancelAdding} type="button">{t("cancel")}</button>
          </div>
        ) : (
          <div className="mt-3 border-t border-gray-100 pt-3 dark:border-gray-800">
            <button className="text-xs font-medium text-blue-600 hover:underline" onClick={() => setAddingDependency(true)} type="button">{t("add_dependency")}</button>
          </div>
        )}
      </div>
      {payload.dependents.length > 0 ? (
        <div className="rounded border border-gray-200 bg-white p-4 text-sm dark:border-gray-700 dark:bg-gray-900">
          <h2 className="font-semibold text-gray-900 dark:text-gray-100">{t("dependents_title", { count: payload.dependents.length })}</h2>
          <ul className="mt-2 divide-y divide-gray-100 dark:divide-gray-800">
            {payload.dependents.map((dependent) => (
              <li className="flex flex-wrap items-center gap-2 py-2" key={dependent.id}>
                <Link className="text-blue-600 hover:underline" to={withRoutePrefix(dependent.job.job_path, prefix)}>{dependent.job.repository_slug} {jobSlug(dependent.job.id)}</Link>
                <StatusPill state={dependent.job.summary_state} />
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  )
}

function TimelinePanel({ canView, jobId, prefix, runsCount }: { canView: boolean; jobId: number; prefix: string; runsCount: number }) {
  const { t } = useT("jobs")
  const [expanded, setExpanded] = useState(false)
  const timeline = useQuery({
    queryKey: ["jobs", String(jobId), "timeline"],
    queryFn: () => fetchJobTimeline(String(jobId)),
    enabled: canView && expanded
  })

  if (!canView) return null

  return (
    <section className="rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900">
      <button
        aria-expanded={expanded}
        className="flex w-full items-center gap-2 p-4 text-left text-sm font-semibold text-gray-900 hover:bg-gray-50 dark:text-gray-100 dark:hover:bg-gray-800"
        onClick={() => setExpanded((value) => !value)}
        type="button"
      >
        <svg aria-hidden="true" className={`h-3 w-3 shrink-0 transition-transform ${expanded ? "rotate-90" : ""}`} fill="currentColor" viewBox="0 0 20 20">
          <path clipRule="evenodd" d="M7.21 14.77a.75.75 0 0 1 .02-1.06L11.17 10 7.23 6.29a.75.75 0 0 1 1.04-1.08l4.5 4.25a.75.75 0 0 1 0 1.08l-4.5 4.25a.75.75 0 0 1-1.06-.02Z" fillRule="evenodd" />
        </svg>
        {t("section_timeline")} <span className="font-normal text-gray-500 dark:text-gray-400">{t("timeline_runs", { count: runsCount })}</span>
      </button>
      {expanded ? (
        <div className="border-t border-gray-100 px-4 pb-4 dark:border-gray-800">
          {timeline.isPending ? <p className="mt-3 text-sm text-gray-400 dark:text-gray-500">{t("timeline_loading")}</p> : null}
          {timeline.isError ? <p className="mt-3 text-sm text-red-700">{errorMessage(timeline.error || new Error("Timeline failed."), t("timeline_error"))}</p> : null}
          {timeline.data && timeline.data.events.length > 0 ? (
            <ol className="mt-3 space-y-3">
              {timeline.data.events.map((event, index) => (
                <li className="border-l border-gray-200 pl-3 text-sm dark:border-gray-700" key={`${event.at}-${event.title}-${index}`}>
                  <div className="font-medium text-gray-900 dark:text-gray-100">
                    {event.workflow_path ? (
                      <Link className="text-blue-600 underline hover:no-underline" to={withRoutePrefix(event.workflow_path, prefix)}>{event.title}</Link>
                    ) : event.title}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-gray-400">
                    {formatDate(event.at)} · {event.source}
                    {event.ref_label ? (
                      <>
                        {" · "}
                        {event.workflow_path ? (
                          <Link className="text-blue-600 underline hover:no-underline" to={withRoutePrefix(event.workflow_path, prefix)}>{event.ref_label}</Link>
                        ) : event.ref_label}
                      </>
                    ) : null}
                  </div>
                  {event.detail ? <div className="mt-1 text-gray-600 dark:text-gray-300">{event.detail}</div> : null}
                </li>
              ))}
            </ol>
          ) : null}
        </div>
      ) : null}
    </section>
  )
}

function AttachmentPreview({ attachments }: { attachments: JobAttachment[] }) {
  const { t } = useT("jobs")
  if (!attachments || attachments.length === 0) return null

  return (
    <section className="rounded border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-900">
      <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{t("section_attachments")}</h2>
      <div className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {attachments.slice(0, 6).map((attachment) => <AttachmentCard attachment={attachment} key={attachment.id} />)}
      </div>
    </section>
  )
}

function AttachmentsTab({ payload, queryKey, onNotice }: { payload: JobDetailPayload; queryKey: JobDetailQueryKey; onNotice: (message: string | null) => void }) {
  const { t } = useT("jobs")
  const queryClient = useQueryClient()
  const [files, setFiles] = useState<File[]>([])
  const [googleDocUrl, setGoogleDocUrl] = useState("")
  const add = useMutation({
    mutationFn: () => createJobAttachments(payload.paths.app_attachments_path, { files, googleDocUrl }),
    onSuccess: (result) => {
      onNotice(result.message || null)
      setFiles([])
      setGoogleDocUrl("")
      void queryClient.invalidateQueries({ queryKey })
      void queryClient.invalidateQueries({ queryKey: ["jobs", String(payload.job.id)] })
    }
  })
  const remove = useMutation({
    mutationFn: (path: string) => deleteJobCommand(path),
    onSuccess: (result) => {
      onNotice(result.message || null)
      void queryClient.invalidateQueries({ queryKey })
      void queryClient.invalidateQueries({ queryKey: ["jobs", String(payload.job.id)] })
    }
  })

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    add.mutate()
  }

  return (
    <section className="space-y-4">
      <form className="rounded border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-900" onSubmit={submit}>
        <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{t("attachment_add_title")}</h2>
        <div className="mt-3 grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] md:items-end">
          <label className="text-sm font-medium text-gray-700 dark:text-gray-300">
            {t("attachment_files_label")}
            <input className="mt-1 block w-full text-sm" multiple onChange={(event) => setFiles(Array.from(event.target.files || []))} type="file" />
          </label>
          <label className="text-sm font-medium text-gray-700 dark:text-gray-300">
            {t("attachment_google_doc_label")}
            <input className="mt-1 w-full rounded border border-gray-300 bg-white px-2 py-1.5 text-sm text-gray-900 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100" onChange={(event) => setGoogleDocUrl(event.target.value)} placeholder={t("attachment_google_doc_placeholder")} type="url" value={googleDocUrl} />
          </label>
          <button className={buttonClass("primary")} disabled={add.isPending || (files.length === 0 && googleDocUrl.trim() === "")} type="submit">{t("attachment_add_button")}</button>
        </div>
        {add.isError ? <p className="mt-2 text-sm text-red-700">{errorMessage(add.error, t("attachment_add_error"))}</p> : null}
      </form>

      {payload.attachments.length > 0 ? (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {payload.attachments.map((attachment) => (
            <div className="relative" key={attachment.id}>
              <AttachmentCard attachment={attachment} />
              <button className="absolute right-2 top-2 rounded border border-red-200 bg-white px-2 py-1 text-xs text-red-700 hover:bg-red-50 dark:border-red-900 dark:bg-gray-950 dark:text-red-300 dark:hover:bg-red-950/40" disabled={remove.isPending} onClick={() => remove.mutate(attachment.app_delete_path)} type="button">{t("attachment_remove")}</button>
            </div>
          ))}
        </div>
      ) : <PanelMessage>{t("section_no_attachments")}</PanelMessage>}
      {remove.isError ? <PanelMessage tone="error">{errorMessage(remove.error, t("attachment_remove_error"))}</PanelMessage> : null}
    </section>
  )
}

function AttachmentCard({ attachment }: { attachment: JobAttachment }) {
  const { t } = useT("jobs")
  const title = attachment.title || attachment.filename || attachment.google_doc_url || `Attachment #${attachment.id}`
  return (
    <article className="rounded border border-gray-200 bg-white p-3 text-sm dark:border-gray-700 dark:bg-gray-900">
      <div className="font-medium text-gray-900 dark:text-gray-100">{attachment.file_path ? <a className="hover:underline" href={attachment.file_path}>{title}</a> : title}</div>
      <div className="mt-1 text-xs text-gray-500 dark:text-gray-400">
        {attachment.google_doc_url ? <a className="text-blue-600 hover:underline" href={attachment.google_doc_url} rel="noopener" target="_blank">{t("attachment_google_doc")}</a> : attachment.content_type || attachment.attachment_type}
        {attachment.byte_size ? ` · ${formatBytes(attachment.byte_size)}` : ""}
      </div>
    </article>
  )
}


function MergeablePill({ value }: { value: boolean | null }) {
  if (value === true) return <StatusPill state="mergeable" />
  if (value === false) return <StatusPill state="unmergeable" />
  return <StatusPill state="unknown" />
}

function JobStateBadge({ state }: { state: string }) {
  const normalized = state.toLowerCase()
  const isFail = normalized.includes("fail") || normalized.includes("invalid") || normalized.includes("cancel")
  const isSuccess = normalized.includes("success") || normalized.includes("approved") || normalized.includes("merged") || normalized.includes("closed")
  const isActive = normalized.includes("running") || normalized.includes("queued")

  const colors = isFail
    ? "text-red-700 dark:text-red-300"
    : isSuccess
      ? "text-emerald-700 dark:text-emerald-300"
      : isActive
        ? "text-blue-700 dark:text-blue-300"
        : "text-gray-600 dark:text-gray-300"

  const dotColors = isFail
    ? "bg-red-500 dark:bg-red-400"
    : isSuccess
      ? "bg-emerald-500 dark:bg-emerald-400"
      : isActive
        ? "bg-blue-500 dark:bg-blue-400"
        : "bg-gray-400 dark:bg-gray-500"

  return (
    <span className={`inline-flex items-center gap-1.5 text-sm font-semibold ${colors}`}>
      <span aria-hidden="true" className={`inline-block h-2.5 w-2.5 shrink-0 rounded-full ${dotColors} ${isActive ? "animate-pulse" : ""}`} />
      <span className="capitalize">{state.replaceAll("_", " ")}</span>
    </span>
  )
}

function PendingJobTitle({ pending, title }: { pending: boolean; title: string }) {
  const { t } = useT("jobs")
  if (!pending) return <>{title}</>

  return (
    <span className="inline-flex min-w-0 items-center gap-2 italic text-gray-500 dark:text-gray-400">
      <span aria-hidden="true" className="inline-block h-4 w-4 shrink-0 animate-spin rounded-full border-2 border-gray-300 border-t-gray-500 dark:border-gray-700 dark:border-t-gray-300" />
      <span>{t("generating_title")}</span>
    </span>
  )
}

function jobSourceLabel(payload: JobDetailPayload, t: ReturnType<typeof useT>["t"]) {
  if (payload.job.issue_number) return `#${payload.job.issue_number}`
  if (payload.job.kind === "direct") return t("source_label_direct")
  if (payload.job.kind === "cron") return t("source_label_scheduled")
  return jobSlug(payload.job.id)
}

function JobSourceLink({ payload, prefix }: { payload: JobDetailPayload; prefix: string }) {
  const { t } = useT("jobs")
  const label = jobSourceLabel(payload, t)
  if (payload.job.scheduled_task) {
    return (
      <Link className="hover:underline" to={withRoutePrefix(payload.job.scheduled_task.scheduled_task_path, prefix)}>
        {label}
      </Link>
    )
  }
  if (!payload.job.issue_url) return <span>{label}</span>

  return (
    <a className="hover:underline" href={payload.job.issue_url} rel="noopener" target="_blank">
      {label}
    </a>
  )
}

function dependencyLabel(dependency: JobDependency, t: ReturnType<typeof useT>["t"]) {
  if (dependency.pending) return dependency.unresolved_slug || t("dependency_unresolved")
  const target = dependency.depends_on_job
  if (!target) return dependency.unresolved_slug || t("dependency_missing")
  return `${target.repository_slug} ${jobSlug(target.id)} (${target.summary_state})`
}

function DependencyLink({ dependency, prefix }: { dependency: JobDependency; prefix: string }) {
  const { t } = useT("jobs")
  const target = dependency.depends_on_job
  const label = dependencyLabel(dependency, t)
  if (dependency.pending || !target) return <span>{label}</span>

  return (
    <SlugHoverCard id={target.id} kind="job">
      <Link className="text-blue-700 underline hover:no-underline" to={withRoutePrefix(target.job_path, prefix)}>{label}</Link>
    </SlugHoverCard>
  )
}


