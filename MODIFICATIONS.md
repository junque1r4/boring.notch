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
