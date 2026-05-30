import { useQueryClient } from "@tanstack/react-query"
import { useEffect } from "react"
import { subscribeToAppEvents } from "./actionCable"

export function useAppEvents() {
  const queryClient = useQueryClient()

  useEffect(() => {
    const subscription = subscribeToAppEvents(queryClient)
    return () => subscription.unsubscribe()
  }, [queryClient])
}
