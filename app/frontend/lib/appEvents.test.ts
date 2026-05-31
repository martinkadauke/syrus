import { QueryClient } from "@tanstack/react-query"
import { describe, expect, it, vi } from "vitest"
import { applyAppEvent, queryKeysFor } from "./appEvents"

describe("queryKeysFor", () => {
  it("maps resource events to the query keys they invalidate", () => {
    expect(queryKeysFor(event("user", null))).toEqual([["bootstrap"]])
    expect(queryKeysFor(event("job", 42))).toEqual([["jobs"], ["jobs", "42"]])
    expect(queryKeysFor(event("workflow", 7))).toEqual([["workflows"], ["workflows", "7"]])
    expect(queryKeysFor(event("repository", 3))).toEqual([["repositories"], ["repositories", "3"]])
    expect(queryKeysFor(event("chat", 5))).toEqual([["chats"], ["chats", "5"]])
    expect(queryKeysFor(event("admin_overview", null))).toEqual([["admin", "overview"], ["admin", "stuck"]])
    expect(queryKeysFor(event("unknown", 1))).toEqual([])
  })
})

describe("applyAppEvent", () => {
  it("invalidates every mapped query key", () => {
    const queryClient = new QueryClient()
    const invalidate = vi.spyOn(queryClient, "invalidateQueries")

    applyAppEvent(queryClient, event("job", 42))

    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["jobs"] })
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["jobs", "42"] })
  })

  it("applies chat replace-tail payloads directly to cached chat data", () => {
    const queryClient = new QueryClient()
    const invalidate = vi.spyOn(queryClient, "invalidateQueries")
    queryClient.setQueryData(["chats", "9", ""], chatPayload([
      message(1, "user", "old"),
      {
        type: "tool_group",
        tool: "Read",
        calls: [
          { message_id: 2, detail: "a.rb", result_body: "a", result_error: false },
          { message_id: 3, detail: "b.rb", result_body: "", result_error: false }
        ]
      }
    ]))

    applyAppEvent(queryClient, {
      ...event("chat", 9),
      payload: {
        action: "replace_tail",
        replace_from_id: 3,
        turn_in_flight: false,
        stop_requested_at: "2026-05-30T12:00:00Z",
        items: [
          {
            type: "tool_group",
            tool: "Read",
            calls: [
              { message_id: 3, detail: "b.rb", result_body: "b", result_error: false },
              { message_id: 4, detail: "c.rb", result_body: "c", result_error: false }
            ]
          },
          message(5, "assistant", "done")
        ]
      }
    })

    expect(invalidate).not.toHaveBeenCalled()
    const updated = queryClient.getQueryData<ReturnType<typeof chatPayload>>(["chats", "9", ""])
    expect(updated?.turn_in_flight).toBe(false)
    expect(updated?.chat.stop_requested_at).toBe("2026-05-30T12:00:00Z")
    expect(updated?.messages).toEqual([
      message(1, "user", "old"),
      {
        type: "tool_group",
        tool: "Read",
        calls: [
          { message_id: 2, detail: "a.rb", result_body: "a", result_error: false },
          { message_id: 3, detail: "b.rb", result_body: "b", result_error: false },
          { message_id: 4, detail: "c.rb", result_body: "c", result_error: false }
        ]
      },
      message(5, "assistant", "done")
    ])
  })
})

function event(resource: string, id: number | null) {
  return {
    type: `${resource}.updated`,
    resource,
    id,
    changed: [],
    occurred_at: "2026-05-30T12:00:00.000Z"
  }
}

function message(id: number, role: "user" | "assistant", text: string) {
  return {
    type: "message" as const,
    id,
    role,
    text,
    bookmarkable: true,
    bookmark_path: `/chats/9/bookmarks`
  }
}

function chatPayload(messages: Array<ReturnType<typeof message> | {
  type: "tool_group"
  tool: string
  calls: Array<{ message_id: number; detail: string; result_body: string; result_error: boolean }>
}>) {
  return {
    message: null,
    chat: {
      id: 9,
      title: "Chat",
      chat_path: "/chats/9",
      repository: null,
      stop_requested_at: null,
      cumulative_input_tokens: 0,
      cumulative_output_tokens: 0,
      cumulative_cost_usd: 0
    },
    chat_available: true,
    turn_in_flight: true,
    has_more_older: false,
    messages,
    bookmarks: [],
    pending_actions: [],
    attachment_groups: { repositories: [], epics: [], jobs: [], documents: [] },
    documents_in_scope: [],
    attachment_results: [],
    whiteboard: { version: 0, elements: [] },
    paths: {
      new_chat_path: "/chats/new",
      credentials_path: "/credentials/edit",
      repositories_path: "/repositories",
      app_messages_path: "/api/v1/app/chats/9/messages",
      app_message_path: "/api/v1/app/chats/9/message",
      app_stop_path: "/api/v1/app/chats/9/stop",
      app_refresh_path: "/api/v1/app/chats/9/refresh",
      app_reset_path: "/api/v1/app/chats/9/reset",
      app_bookmarks_path: "/api/v1/app/chats/9/bookmarks",
      app_attachments_path: "/api/v1/app/chats/9/attachments",
      app_whiteboard_path: "/api/v1/app/chats/9/whiteboard",
      chat_messages_path: "/chats/9/messages",
      chat_attachments_path: "/chats/9/attachments",
      chat_whiteboard_path: "/chats/9/whiteboard"
    }
  }
}
