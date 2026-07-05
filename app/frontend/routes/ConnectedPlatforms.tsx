import { createConsumer } from "@rails/actioncable"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { ReactNode } from "react"
import { useEffect, useRef, useState } from "react"
import { NoticeToast } from "../components/NoticeToast"
import {
  createLinkingToken,
  deletePlatformIdentity,
  fetchPlatformIdentities,
  type AvailablePlatform,
  type LinkingTokenPayload,
  type PlatformIdentitiesPayload,
  type PlatformIdentity
} from "../api/platformIdentities"
import { ApiError } from "../api/client"

const queryKey = ["platform_identities"] as const

const PLATFORM_LABELS: Record<string, string> = {
  telegram: "Telegram",
  slack: "Slack"
}

export function ConnectedPlatformsRoute() {
  const [notice, setNotice] = useState<string | null>(null)

  return (
    <main aria-label="Connected Platforms" className="mx-auto max-w-4xl space-y-6 p-6">
      <header>
        <h1 className="text-2xl font-semibold text-gray-900 dark:text-gray-100">Connected Platforms</h1>
        <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">Link your Syrus account to external messaging platforms.</p>
      </header>

      <NoticeToast message={notice} onDismiss={() => setNotice(null)} />
      <ConnectedPlatformsPanel onNotice={setNotice} />
    </main>
  )
}

function ConnectedPlatformsPanel({ onNotice }: { onNotice: (message: string | null) => void }) {
  const result = useQuery({
    queryKey,
    queryFn: fetchPlatformIdentities
  })

  if (result.isPending) return <PanelMessage>Loading connected platforms...</PanelMessage>
  if (result.isError) return <PanelMessage tone="error">{errorMessage(result.error, "Unable to load connected platforms.")}</PanelMessage>

  return <PlatformsView onNotice={onNotice} payload={result.data} />
}

function PlatformsView({ payload, onNotice }: { payload: PlatformIdentitiesPayload; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()

  const disconnect = useMutation({
    mutationFn: (id: number) => deletePlatformIdentity(id),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || "Platform account disconnected.")
    }
  })

  return (
    <section className="divide-y divide-gray-200 dark:divide-gray-700 rounded border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900">
      {payload.available_platforms.map((ap) => {
        const linked = payload.platform_identities.find((pi) => pi.platform === ap.platform)
        return (
          <PlatformRow
            key={ap.platform}
            availablePlatform={ap}
            disconnectPending={disconnect.isPending && disconnect.variables === linked?.id}
            identity={linked}
            onConnect={(updated) => {
              queryClient.setQueryData(queryKey, updated)
            }}
            onDisconnect={() => linked && disconnect.mutate(linked.id)}
            onNotice={onNotice}
          />
        )
      })}
    </section>
  )
}

function PlatformRow({
  availablePlatform,
  identity,
  disconnectPending,
  onConnect,
  onDisconnect,
  onNotice
}: {
  availablePlatform: AvailablePlatform
  identity: PlatformIdentity | undefined
  disconnectPending: boolean
  onConnect: (payload: PlatformIdentitiesPayload) => void
  onDisconnect: () => void
  onNotice: (message: string | null) => void
}) {
  const label = PLATFORM_LABELS[availablePlatform.platform] ?? availablePlatform.platform
  const [linkingToken, setLinkingToken] = useState<LinkingTokenPayload | null>(null)
  const [linkError, setLinkError] = useState<string | null>(null)

  const connect = useMutation({
    mutationFn: () => createLinkingToken(availablePlatform.platform),
    onSuccess: (result) => {
      setLinkingToken(result)
      setLinkError(null)
      onNotice(null)
    },
    onError: (err) => {
      setLinkError(errorMessage(err, `Unable to start ${label} linking.`))
    }
  })

  function handleDisconnect() {
    if (window.confirm(`Disconnect your ${label} account?`)) {
      setLinkingToken(null)
      setLinkError(null)
      onDisconnect()
    }
  }

  return (
    <div className="p-5">
      <div className="flex items-center justify-between gap-4">
        <div>
          <div className="text-sm font-medium text-gray-900 dark:text-gray-100">{label}</div>
          {identity ? (
            <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
              Connected{identity.external_handle ? ` as ${identity.external_handle}` : ""} since {new Date(identity.linked_at).toLocaleDateString()}
            </p>
          ) : (
            <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400">Not connected</p>
          )}
        </div>

        <div className="flex shrink-0 gap-2">
          {identity ? (
            <button
              className="rounded border border-gray-300 dark:border-gray-600 px-3 py-1.5 text-sm text-red-700 dark:text-red-300 hover:bg-red-50 dark:hover:bg-red-950/50 disabled:text-red-300 dark:disabled:text-red-500"
              disabled={disconnectPending}
              onClick={handleDisconnect}
              type="button"
            >
              {disconnectPending ? "Disconnecting..." : "Disconnect"}
            </button>
          ) : availablePlatform.configured ? (
            <button
              className="rounded bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500 disabled:bg-blue-300 dark:disabled:bg-blue-900"
              disabled={connect.isPending}
              onClick={() => connect.mutate()}
              type="button"
            >
              {connect.isPending ? "Generating link..." : linkingToken ? "Regenerate link" : "Connect"}
            </button>
          ) : (
            <button
              className="rounded border border-gray-200 dark:border-gray-700 px-3 py-1.5 text-sm text-gray-400 dark:text-gray-500 cursor-not-allowed"
              disabled
              title="This platform integration is not yet available on this instance"
              type="button"
            >
              Not yet available
            </button>
          )}
        </div>
      </div>

      {linkError ? (
        <p className="mt-3 text-xs text-red-700 dark:text-red-300">{linkError}</p>
      ) : null}

      {linkingToken && !identity ? (
        <LinkingInstructions
          onLinked={onConnect}
          onNotice={onNotice}
          platform={availablePlatform.platform}
          tokenPayload={linkingToken}
        />
      ) : null}
    </div>
  )
}

function LinkingInstructions({
  platform,
  tokenPayload,
  onLinked,
  onNotice
}: {
  platform: string
  tokenPayload: LinkingTokenPayload
  onLinked: (payload: PlatformIdentitiesPayload) => void
  onNotice: (message: string | null) => void
}) {
  const [copied, setCopied] = useState(false)
  const onLinkedRef = useRef(onLinked)
  onLinkedRef.current = onLinked

  useEffect(() => {
    const consumer = createConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: "AppUserChannel" },
      {
        received(data: unknown) {
          const event = data as { type?: string; payload?: PlatformIdentitiesPayload }
          if (event.type === "platform_identity_linked" && event.payload) {
            onLinkedRef.current(event.payload)
            onNotice(`${PLATFORM_LABELS[platform] ?? platform} account connected.`)
          }
        }
      }
    )

    return () => subscription.unsubscribe()
  }, [platform, onNotice])

  async function copyToken() {
    try {
      await navigator.clipboard.writeText(`/start ${tokenPayload.token}`)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      setCopied(false)
    }
  }

  return (
    <div className="mt-3 rounded border border-blue-100 dark:border-blue-900/60 bg-blue-50 dark:bg-blue-950/40 p-3 text-sm text-blue-950 dark:text-blue-100">
      <p className="font-medium">How to connect</p>
      <p className="mt-1 text-xs">{tokenPayload.instructions.text}</p>
      {tokenPayload.instructions.bot_handle ? (
        <div className="mt-2 flex items-center gap-2">
          <code className="flex-1 rounded bg-blue-100 dark:bg-blue-900/60 px-2 py-1 font-mono text-xs break-all">
            /start {tokenPayload.token}
          </code>
          <button
            className="shrink-0 rounded border border-blue-300 dark:border-blue-700 px-2 py-1 text-xs text-blue-700 dark:text-blue-300 hover:bg-blue-100 dark:hover:bg-blue-900/60"
            onClick={copyToken}
            type="button"
          >
            {copied ? "Copied!" : "Copy"}
          </button>
        </div>
      ) : null}
      <p className="mt-2 text-xs text-blue-700 dark:text-blue-300">This link expires in 15 minutes. Waiting for you to send the message…</p>
    </div>
  )
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" }) {
  const colors = {
    error: "border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300",
    muted: "border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 text-gray-600 dark:text-gray-400"
  }
  return <div className={`rounded border p-4 text-sm ${colors[tone]}`}>{children}</div>
}

function errorMessage(error: Error, fallback: string) {
  return error instanceof ApiError ? error.message : fallback
}
