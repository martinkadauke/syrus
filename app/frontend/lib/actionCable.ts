import { createConsumer, type Consumer, type Subscription } from "@rails/actioncable"
import type { QueryClient } from "@tanstack/react-query"
import { applyAppEvent, type AppEvent } from "./appEvents"

export function subscribeToAppEvents(
  queryClient: QueryClient,
  consumer: Consumer = createConsumer()
): Subscription {
  return consumer.subscriptions.create(
    { channel: "AppUserChannel" },
    {
      received(data: unknown) {
        applyAppEvent(queryClient, data as AppEvent)
      }
    }
  )
}
