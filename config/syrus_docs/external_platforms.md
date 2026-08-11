# External Platform Integrations

Syrus can receive messages from and deliver replies to external messaging platforms (Telegram, and future platforms). All integrations share a common inbound routing layer and an outbound delivery adapter registry.

## Architecture

**Inbound:** `InboundMessageRouter` maps an incoming external message to a Syrus user via `PlatformIdentity`, finds or creates a `ChatSession` for that user+platform pair, creates a user-role `ChatMessage`, and enqueues `ChatTurnJob` when the session's `trigger_policy` is `speak_when_spoken_to`.

**Outbound:** `ChatMessage` fires an `after_create_commit` hook for assistant-role messages in sessions with an `origin_platform`. For each session participant, Syrus looks up their `PlatformIdentity` for that platform and calls the matching `PlatformDelivery` adapter. Participants with no identity for the platform receive web delivery via ActionCable as usual.

**Polling:** Each platform integration runs as a subclass of `PlatformPollingJob`. The base class handles deduplication (at most one instance running), error logging, and self-re-enqueue on every cycle. Subclasses implement `configured?` (checks bot token/handle) and `poll_once` (does one long-poll cycle and calls `InboundMessageRouter` for each incoming message).

## PlatformIdentity

Users link external accounts in **Settings → Connected Platforms**. The link flow generates a short-lived token; the user sends that token to the bot; the bot calls the linking endpoint, which creates the `PlatformIdentity` row. `PlatformIdentity` stores the platform, `external_id` (stable bot-side user ID), `external_handle` (human-readable), and `linked_at`.

## Starting the poller

Platform polling jobs start automatically on application boot when their bot token is configured (`config/initializers/platform_polling.rb`). To start manually without a restart:

```
POST /api/v1/app/admin/platform_polling/start
```

Returns `{ "started": ["TelegramPollingJob", ...] }` with the names of jobs that were newly enqueued. Jobs already running are skipped. Requires admin authentication.

## Trigger policy

ChatSessions created via platform delivery use `trigger_policy: "speak_when_spoken_to"`: Syrus replies to every inbound user message. The policy is stored on the session and checked by `InboundMessageRouter`. Future policies (proactive, scheduled, etc.) can be added by extending `ChatSession::TRIGGER_POLICIES` and adding a handler in the router.

## Adding a new platform

1. Create a `PlatformPollingJob` subclass (e.g. `SlackPollingJob`) that implements `configured?` and `poll_once`.
2. In `poll_once`, call `InboundMessageRouter.new(...).call` for each inbound message.
3. Create a `PlatformDelivery` adapter subclass and register it: `PlatformDelivery::Registry.register("slack", SlackAdapter)`.
4. Add the platform slug to `PlatformIdentity::PLATFORMS`.
5. Add any required `AppSetting` columns for the bot token/handle.
