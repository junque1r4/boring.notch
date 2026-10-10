# Modifications to Boring Notch

Date: 10 October 2026. Fork: junque1r4/boring.notch. License: GPL-3.0-only.
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

Original license, copyright notices, credits and third-party notices remain.
See [docs/AGENTS.md](docs/AGENTS.md) for behavior and limitations.
