# Phase 1 verification — 10 October 2026

Base: TheBoredTeam/boring.notch tag `v2.8-rc.2`, commit
`1fa326d` (latest published pre-release verified through GitHub's release API).
Fork: https://github.com/junque1r4/boring.notch. Work branch: `agents/phase-1`.

Validated on this Apple silicon Mac using Xcode 27.0 (27A266a), Swift 6.4,
installed Codex CLI 0.144.6 and Codex Desktop 26.1007.21159.

| Requirement | Evidence and boundary |
| --- | --- |
| Original feature preservation | Baseline app built before edits; all 102 inherited app tests pass. Home, Shelf, media controls and battery UI remain present. Live now-playing appeared in the notch. Full camera/calendar/notification/OSD and hardware regression coverage is not claimed. |
| Agents tab | Native UI inspected and visually checked in the expanded notch; Home, Shelf and Agents buttons accessible. Agent Center also opens from the app menu and ⇧⌘A. |
| Modular architecture | Foundation-only `AgentSessionProvider` plus independent actor-based log/hook adapters; UI, merging and alerts do not depend on transcript content. |
| Codex monitoring | Read-only core smoke check found five real local Desktop sessions, including one Working session. Two initial/cached scans took approximately 0.27 seconds. CLI metadata/lifecycle is exercised by synthetic fixtures, not a separately launched live CLI agent. |
| States and freshness | Working, Waiting, Completed and Failed rendered from synthetic logs in the running app; Unknown and Stale also exported from hosted SwiftUI rendering. Live Failed emission has not been observed; no prose/tool-error inference. |
| Completion/attention alerts | In-app completion alert observed after appending a synthetic completion record. Waiting/failure, baseline silence, freshness and deduplication tested in the core. macOS notification authorization succeeded in the release UI; actual banner/sound delivery and click routing were not directly observed. Alerts returned to opt-in/off after validation. |
| Navigation | Synthetic CLI row copied exactly `codex resume <UUID>`; invalid IDs rejected by tests. Installed Desktop has `codex` scheme registration; exact thread routing remains version dependent and is not claimed verified. Only the Codex handler is accepted. |
| Folder access | Running sandboxed app used a folder picker, displayed fixtures, restored its read-only bookmark on relaunch, silently reloaded historical events, and cleared sessions on Disconnect. Fixture grants were removed afterward. No actual Codex folder grant or hook installation was left behind. |
| Builds | Unmodified baseline, modified Debug and universal arm64/x86_64 local Release builds succeed. The Release launches after the documented ad-hoc signing adjustment. Deep/strict code-signature verification passes; App Sandbox stays enabled. |
| Tests | 105 hosted app tests, 8 standalone core tests and 4 Python hook tests pass. A screenshot-export test initially failed when writing outside its sandbox; export was corrected to app-owned temporary storage and the complete suite passed. |
| GPL/source | Original LICENSE, THIRD_PARTY_LICENSES and copyrights retained; modification notice and dates added; local binary is accompanied by a source snapshot, pinned dependency sources and build instructions. No official-upstream endorsement or notarization claim. |

## Release and interface limits

- Local ad-hoc build; no Developer ID signature, Hardened Runtime or notarization.
  App Sandbox remains enabled. Proper public-release signing is still needed.
- The inherited MediaRemoteAdapter is a prebuilt, ad-hoc-signed BSD component;
  its upstream notes explicitly say it is not independently reproducible
  bit-for-bit. Its newer macOS target produces linker warnings. macOS 14–26
  and actual Intel hardware have not been exercised here.
- Inherited Swift concurrency and linker warnings remain; this milestone does
  not migrate the entire application to Swift 6 language mode.
- Session logs are unstable. Monitoring is bounded to local recent sessions;
  remote/cloud, archived and inaccessible sessions are outside coverage.
- Official hook configuration is supplied but has not been installed/trusted
  in the user's Codex configuration. Tests invoke the observer with fixtures.
- No Approve/Deny controls; permissions remain with Codex. No private socket,
  credentials, keychain or state-database access is used.
- Sleep/wake, external displays, Focus-mode notification delivery, all original
  features and long-term polling/energy behavior need broader real-use checks.
- GitHub hosted workflows have not been verified. The inherited upstream
  release/publishing pipeline is not the fork's release pipeline.

See [AGENTS.md](AGENTS.md) for setup, exact state meanings and architecture.
