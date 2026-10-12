# Modifications to Boring Notch

Date: 11 October 2026. Fork: junque1r4/boring.notch. License: GPL-3.0-only.
Base: TheBoredTeam/boring.notch v2.8-rc.2.

This is a modified version, not an official TheBoredTeam release.

- Added native Agents tab and Agent Center, local provider architecture, bounded
  Codex session-log adapter and documented observer-only Codex hook bridge.
- Added Working, Waiting, Completed, Failed and Unknown display states,
  source/freshness labels, opt-in macOS alerts, in-app alerts and navigation.
- Added metadata privacy, folder grants, safe ID validation and tests.
- Changed app/helper IDs and product name for coexistence; disabled upstream
  Sparkle replacement. No approval controls are implemented.
- Added a shared Xcode test scheme, standalone core tests, hook tests, setup,
  validation and distribution instructions.

- Refined only the Agents UI with CodeNotch-inspired remaining-usage rings,
  Notchi-inspired compact/hover session rows and Working/Attention filters.
- Added installed/running Codex and Grok Bot detection, local Codex quota windows
  and Grok Bot weekly-cache adapter, with unavailable/stale/reset/ambiguity handling.
  No credentials, API calls, Grok cloud task status or approval controls were added.
- Added automatic fixed-root metadata readers for detected apps through the
  existing local helper, with an allowlisted caller and bounded metadata replies.
  Manual connection controls now appear only for unidentified installations;
  provider monitoring can be paused and resumed.
- Changed the ChatGPT ring headline to weekly allowance, and linked Agents quota
  popup presentation to the notch's existing popover hold so its lower controls
  remain accessible. The only shared-view refinement is that Agents hold binding;
  no Home/Shelf/media behavior was changed.

- Added stable parent gesture enablement and Agents scroll forwarding with momentum
  reset across tab changes, preserving other tabs' gesture identity.
- Added a native Agents-only Dot chat panel, encrypted bounded local persistence,
  Keychain OAuth credentials and a separately scoped private Cloudflare relay.
  This opt-in chat sends explicit messages; monitoring still stays local.
- Added GitHub-owner PKCE authentication, private MCP tools/events and GPL relay
  source with maintained OAuth dependency source and MIT notices. Real Dot delivery
  remains an acceptance gate, not a claim based on protocol fixtures.

Original license, copyright notices, credits and third-party notices remain.
See [docs/AGENTS.md](docs/AGENTS.md) for behavior and limitations.

## 12 October 2026 — Embedded Dot and usage design

- Added the fourth Dot tab with the owner's unmodified personal avatar, bounded
  embedded chat, per-window focus/dismissal, and unread badge.
- Replaced the Agents chip with a robot icon; redesigned weekly used statistics
  and added a local, bounded activity calendar that keeps missing days unknown.
- Diagnosed the empty relay callback allowlist using encrypted expiring private
  diagnostics; pinned the verified OpenAI callback origin and activated the
  actual Dot subscription.
- Preserved original Home/Shelf dimensions and media behavior.

## 12 October 2026 — Chat polish and latency analysis

- Added local date separators, per-message times, compact delivery/reply ticks,
  original Dot avatars on replies, aligned bubbles and native Markdown formatting.
- Removed composer byte counts and keyboard instruction text; retained keyboard
  behavior, privacy bounds and accessible delivery explanations.
- Added per-window pinning that survives outside clicks; explicit close, Escape,
  tab changes and screen lock still clear the pin. Home/Shelf behavior is preserved.
- Investigated response latency and streamlined the existing actual-Dot task's
  routine prompt. The platform's asynchronous dispatch remains a measured limit.
- Searched for original Dot animations; no complete distributable bundle found.

## 12 October 2026 — Content-sized chat bubbles

- Size each bubble to its message and footer, wrapping long content at a bounded
  width instead of stretching every message to the same width.
- Center the original Dot avatar within each reply and inset timestamps and
  receipt marks with consistent transcript spacing.
- Match the supplied native-chat reference with sRGB yellow #FFCC39 for outgoing
  messages, neutral gray #F0F0F0 for replies, and dark readable text.

## 12 October 2026 — Persistent Dot shortcut

- Added a black right-side extension to the closed notch with the original Dot
  avatar and shared unread reply count (capped visually at 9+).
- Clicking the shortcut opens the embedded Dot chat directly with composer focus.
  It has a dedicated hit region outside Home's hover/gesture handling.
- Keeps the physical notch centered and preserves the open-state tab navigation.

## 12 October 2026 — Stable development signing

- Local builds now select the sole available code-signing certificate, or use an
  explicitly configured BORING_NOTCH_SIGNING_IDENTITY. Multiple/no identities
  stop with selection instructions rather than silently reverting to ad-hoc.
- Certificate signing preserves the app's designated requirement across rebuilds,
  allowing remembered Keychain access to survive code changes. Existing secrets
  and Keychain access controls are preserved. The first transition can require
  the owner to approve both saved items with Always Allow.

## 12 October 2026 — Dot motion and restored notch behavior

- Keep one persistent original-avatar launcher between the closed dock and Dot
  tab, with independent hover/press reactions and a single unread-reply nod.
- Restore the original main-notch hover shadow, open/close timing and content
  expansion transition. Keep the right extension at the existing closed height.
- Capture the settled closed dock before opening so closing returns toward that
  endpoint rather than following the shrinking expanded notch's right edge.
- Honor Reduce Motion and animation preferences; keep Dot accessible in compact
  mode without replacing the normal Home compact-player behavior.
