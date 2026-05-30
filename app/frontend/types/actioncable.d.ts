declare module "@rails/actioncable" {
  export type Subscription = {
    unsubscribe(): void
  }

  export type Consumer = {
    subscriptions: {
      create(params: { channel: string }, mixin: { received(data: unknown): void }): Subscription
    }
  }

  export function createConsumer(url?: string): Consumer
}
