# Private Boring Notch → Dot relay

This is a new channel to the owner's actual Dot, not an OpenAI API assistant or
mirror of existing ChatGPT history. The deployed Worker contains no model API
call or synthetic response. A real authenticated notch → Dot → reply exchange was observed on 12 October
2026 after prompting the actual Dot in Safari to handle the originating message.
A later native test received an automatic reply after the event binding was
refreshed. A further automatic test recovered both an older pending message
and a new message, leaving the queue empty. Replies can take several minutes;
these checks do not establish sustained renewal or long-term reliability.

Live status on 2026-10-12: the owner's actual Dot completed MCP Events callback
verification and `notch_connection_status` reports the subscription active for
`notch.message.created`. The callback origin was captured from that authenticated
subscription attempt and added to the exact-origin allowlist. A genuine Dot reply was visibly rendered in the native notch. The event task initially did not run despite HTTP 200 callback acknowledgements.
After the exact binding was reapplied, a subsequent test received an automatic
Dot reply. Missing event payloads are recovered through the private pending-ID
queue described below. `/health` keeps
`endToEndVerified` set to `false`; subscription readiness alone does not prove
message delivery or a correlated reply.

Only explicitly submitted chat text is relayed. Session metadata, logs and usage
readings have no route into this module. GitHub numeric owner `39351332` is checked
at sign-in, token refresh, native/MCP requests and webhook delivery. The owner
restriction fails closed; a public Worker URL is not public chat access.

## Configure with cf

Use `npm ci`, `npm run typecheck`, `npm test`, `npm run build` and `npm run deploy`.
The private relay origin is `https://boring-notch-dot-relay.ext-joao-junqueira.workers.dev`.
The project uses `cloudflare.config.ts` and the `cf` CLI. Set
`CLOUDFLARE_ACCOUNT_ID` to the user's selected **personal** Cloudflare account
before any deploy. The initial empty bindings deliberately deploy only `/health`;
all OAuth and chat paths return `503 relay_not_configured` until setup finishes.
Never deploy this channel to the corporate account.

1. Deploy the initial Worker and register its workers.dev address in the selected
   personal account if Cloudflare requires it. Set `RELAY_ORIGIN` to that exact
   HTTPS origin, with no trailing slash, port, credentials or path. Redeploy.
2. Register an owner-controlled GitHub OAuth app with callback
   `<RELAY_ORIGIN>/callback`. Replace the empty `GITHUB_CLIENT_ID`,
   `GITHUB_CLIENT_SECRET`, and `RELAY_ENCRYPTION_KEY` text placeholders in the
   Cloudflare config with `bindings.secret()`. Upload them through cf secrets;
   the encryption key must be 32 random bytes encoded as base64. Never commit
   credentials, copy them into a chat transcript or enter them in public config.
3. Dynamic registration accepts only the exact native public callback; ChatGPT uses CIMD.
   Native OAuth uses `boringnotch-agents://oauth/callback`, public DCR with
   `token_endpoint_auth_method: none`, authorization-code + refresh-token grants,
   PKCE S256, scopes `notch:read notch:send offline_access`, and **the bare relay
   origin** as `resource`. OAuthProvider advertises RFC 9207 issuer identification
   and appends `iss` to the authorization response.
4. Replace the placeholder endpoint in `plugin/mcp.json` with the private relay
   `/mcp` endpoint. Install the private plugin in ChatGPT and connect it with the
   same owner GitHub account. OAuth discovery is provided by maintained
   `@cloudflare/workers-oauth-provider` 1.2.3. Plugin scopes are
   `notch:context notch:reply notch:subscribe offline_access`.
5. Ask your actual Dot to subscribe to `notch.message.created`, with
   `conversationId: notch`, and respond to each event through `notch_reply` using
   its originating message ID. Subscriptions are not started silently on install.
6. Configure `CALLBACK_ORIGINS` with the exact trusted public ChatGPT webhook
   origin supplied by the genuine connection. Arbitrary callback origins fail
   closed. Do not use wildcards, tenant-controlled shared tunnel domains, or
   origins whose DNS the owner cannot trust. Verification must succeed before
   payload delivery. This deployment uses Workers' `global_fetch_strictly_public`
   flag and disables redirects. **It does not implement an explicit DNS-resolve /
   validated-IP TLS connection primitive**; verify that the production platform's
   egress protections meet the complete MCP Events callback requirement before
   treating this limitation as closed.
7. Sign in from the native notch, send an explicit small test message and confirm
   the actual Dot's correlated reply appears in the notch. A `delivered` webhook
   acknowledgment means receipt only. Do not call the integration complete until
   this real exchange is demonstrated.

## Native contract

`POST /v1/messages` takes `{messageId: UUID, text: string}` (8 KiB UTF-8 maximum).
It returns `{messageId,status,sequence,subscriptionActive}`. Reusing an ID with
identical content is idempotent; changed content returns 409. Explicit retries
retain the same message ID. Acknowledgments never claim model processing.

`GET /v1/events?after=<integer>` returns `{events,cursor,subscriptionActive}`.
Events contain `sequence`, UUID `eventId`, UUID `messageId`, `type` (`delivery` or
`reply`), `status` or `text`, and fractional-second ISO 8601 `createdAt`. Responses
contain at most 100 events and about 900 KiB of event payload. Preserve the cursor
and deduplicate by event ID. Polling is **native app recovery**, not an MCP Events
polling transport; ChatGPT subscriptions use signed webhooks exclusively.

`GET /v1/settings` reports subscription status and bounds. `POST /v1/revoke`
revokes subscription delivery. OAuth token revocation is handled by the provider's
standard advertised revocation endpoint (use OAuth discovery).

MCP 2026-07-28 `/mcp` implements `server/discover`, `events/list`,
`events/subscribe`, `events/unsubscribe`, `tools/list` and `tools/call`.
`notch_connection_status` validates owner authentication and reports whether a
callback allowlist is configured, whether a subscription is active, and the
latest subscription setup result for up to one hour. The result may include only
the callback HTTPS origin; it excludes the URL path, query, secret, and chat
content. It also reports the newest native message UUID, delivery state, and
creation time from metadata already stored in the relay. This summary contains
no chat content and does not imply an exact HTTP callback status. For attempts
made after this diagnostic was deployed, it reports the latest outbound webhook
result for up to one hour: originating message UUID, callback HTTP status (or
`null` if no HTTP response was received), timestamp, attempt count, and delivery
category. This diagnostic is encrypted at rest and never includes the callback
path, query, headers, response body, webhook secret, or message content. Native
settings do not expose these diagnostics. Call it before subscribing; the native
app gates Send until the subscription is active. A 2xx callback response
confirms receipt by ChatGPT only; it does not prove that Dot processed the event
or produced a reply.
If an event handler cannot access a delivered event payload, readiness also
includes up to 20 oldest unreplied message UUID/status/time summaries younger
than seven days, plus `hasMorePending`; it never includes message text. Recover
these in oldest-first order by reading `notch_conversation_context` for each
UUID and replying with a stable reply ID. A `message_already_replied` conflict
means that originating message is complete and should be skipped. Failed,
replied, and expired messages are excluded from this queue.
`notch_conversation_context` returns at most 20 originating messages and 64 KiB.
`notch_reply` requires `messageId`, stable UUID `replyId`, and at most 64 KiB text.
It accepts one response per originating send and deduplicates retries.

## Privacy, delivery and recovery

SQLite Durable Object records encrypt message/reply content, webhook secrets and
subscription credentials with AES-GCM. Message conflict fingerprints use a keyed
HMAC, not a publicly guessable text hash. Seven-day alarms purge relay payloads.
Only opaque originating IDs remain for 30 days after purge, to reject an old retry
with `410 message_expired` instead of starting a duplicate Dot run. The local
transcript is a separate native encrypted store.

Webhook IDs remain stable through up to six attempts. Each retry is freshly signed
with Standard Webhooks HMAC and exponential delays capped at 60 seconds. `410`
revokes the subscription; `413` stops that delivery. Expired/revoked subscriptions
stop deliveries. Secret rotation overlaps signatures for five minutes. Successful
verification is cached for five minutes only for the same owner, grant, callback
and secret. Subscription lifetime is at most 24 hours and must be refreshed.

The read:user upstream GitHub token is stored encrypted because the relay must
recheck GitHub revocation before future event delivery. It is not a GitHub repo
write token. The OAuth provider stores native/plugin tokens by hash and encrypts
props. No request bodies, authorization headers, OAuth query strings or chat
content are written to logs. Invocation logs are disabled, query strings are
redacted, and application errors expose fixed codes only.

## Verification and license

The 31 Workers runtime tests passed on 2026-10-12; type generation/check and cf build passed.
The Workers runtime tests use explicit synthetic fixtures, never a Dot responder
in deployed code. Tests cover payload bounds, OAuth/owner boundaries, callback
verification, signing, encrypted persistence, expiry, idempotency and revocation.
The actual Dot subscription and callback verification are live and active. The actual Dot replied to a real native message after a diagnostic prompt in
Safari. A later automatic event wake-up also produced a real reply inside the notch;
a further automatic two-message recovery was verified. Sustained renewal
remains unverified.

This directory is GPL-3.0-only as part of the modified Boring Notch distribution.
The maintained OAuth dependency is MIT; its notice is in `licenses/`. The exact
package lock is included. Include this source, build files, plugin package and
pinned dependency source in the corresponding source archive when distributing
the app or deployed relay bundle.

Protocol references:
- https://developers.openai.com/plugins/build/mcp-events
- https://developers.openai.com/plugins/build/plugins
- https://github.com/cloudflare/workers-oauth-provider/tree/v1.2.3
- https://developers.cloudflare.com/cf/agents/
