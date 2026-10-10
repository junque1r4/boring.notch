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
| Agent tab refinements | CodeNotch-inspired remaining-quota rings/details; Notchi-inspired dense hover rows and Working/Attention filters. Real notch and Agent Center visually checked with synthetic fixtures. Compact layout keeps a Working row visible at 135-point height; screenshot/pixel regression passes. Agents quota popups retain the notch's existing popover hold. Home/Shelf/media behavior is unchanged; shared edits only wire the Agents hold and its metadata endpoint/helper source membership. |
| Quotas | Sandboxed release automatically displayed real Codex weekly allowance and Grok Bot weekly cache with no saved folder grants. ChatGPT's ring selects Weekly even when a five-hour primary exists; a missing weekly window is unavailable, never replaced with five-hour usage. Synthetic two-window quotas, reset details and filters verified. Unknown/malformed/future values, passed resets, ambiguous Grok accounts and obsolete secondary windows tested. ChatGPT chat limits and Grok Build CLI quota are not covered. |
| Autodetection | Release UI identified both installed/running apps, showed Automatic monitoring for both, loaded usage and recent Codex sessions through the embedded helper, and omitted Connect local data for each. No folder picker or new OS permission was used. Pausing is persistent; manual connection is reserved for unidentified apps. Fixed-root/provider allowlist and metadata-only wire round-trip are tested. Custom CLI executable locations, unregistered app installs and other Grok Bot versions remain outside verified discovery coverage. |
| Popup interaction | In the running release, opened ChatGPT weekly details, moved into the popup extending below the notch and used its Open app control without the notch closing. The popup remained present across subsequent inspections. Escape dismissed it and restored normal hover closing. Manual Connect visibility is tested for undetected/installed/running/CLI cases; an undetected real installation was not available on this Mac. |
| Modular architecture | Foundation-only `AgentSessionProvider` plus independent actor-based log/hook/usage-cache adapters; UI, merging and alerts do not depend on transcript content. |
| Codex monitoring | Read-only core smoke check found five real local Desktop sessions, including one Working session. Two initial/cached scans took approximately 0.27 seconds. CLI metadata/lifecycle is exercised by synthetic fixtures, not a separately launched live CLI agent. |
| States and freshness | Working, Waiting, Completed and Failed rendered from synthetic logs in the running app; Unknown and Stale also exported from hosted SwiftUI rendering. Live Failed emission has not been observed; no prose/tool-error inference. |
| Completion/attention alerts | In-app completion alert observed after appending a synthetic completion record. Waiting/failure, baseline silence, freshness and deduplication tested in the core. macOS notification authorization succeeded in the release UI; actual banner/sound delivery and click routing were not directly observed. Alerts returned to opt-in/off after validation. |
| Navigation | Synthetic CLI row copied exactly `codex resume <UUID>`; invalid IDs rejected by tests. Installed Desktop has `codex` scheme registration; exact thread routing remains version dependent and is not claimed verified. Only the Codex handler is accepted. |
| Local access | Existing manual read-only grants were exercised with fixtures, restored on relaunch and removed afterward. Final app uses automatic readers for both detected apps with no saved folder grants. The existing helper remains unsandboxed as upstream; its Agents method verifies the enclosing app executable path, bundle ID and same user, accepts only two fixed provider IDs and caps replies at 256 KiB. No arbitrary paths, commands or raw transcript data cross XPC. No hook installation was left behind. |
| Builds | Unmodified baseline, modified Debug and universal arm64/x86_64 local Release builds succeed. The Release launches after the documented ad-hoc signing adjustment. Deep/strict code-signature verification passes; App Sandbox stays enabled. |
| Tests | 110 hosted app tests, 15 standalone core tests and 4 Python hook tests pass (129 total). Includes weekly-window selection, fixed-root automatic readers, metadata-only wire serialization, connection visibility and popup retention state. Synthetic screenshots export to app-owned temporary storage. |
| GPL/source | Original LICENSE, THIRD_PARTY_LICENSES and copyrights retained; modification notice and dates added; design reference notices retained; local binary is accompanied by a source snapshot, pinned dependency sources and build instructions. No official-upstream endorsement or notarization claim. |

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

## Reproducing the hosted suite

Two standard debugger/checker test launches stalled in the system dynamic loader
before app entry. A direct test launch passed all 110 tests. The final local Release
launches normally; this was a test-host issue, not a monitoring failure.
`scripts/test-agents-local.sh ../DerivedData` creates a temporary direct-launch
validation scheme (no debugger/Main Thread Checker/Thread Performance Checker,
`ENABLE_DEBUG_DYLIB=NO`), runs all inherited and Agents tests, then removes the
scheme. It changes no OS security settings and leaves the normal shared scheme
unchanged. Set `TEST_RUNNER_AGENTS_TEST_RENDER_DIR=1` for synthetic screenshots in
the test app's temporary `AgentMonitorValidation` folder.

Standalone checks: `swift test` and `python3 integrations/codex/test_notch_hook.py`.
The 129 passing tests consist of 110 hosted app, 15 core and four hook tests.

See [AGENTS.md](AGENTS.md) for setup, exact state meanings and architecture.

## Dot and Agents scrolling validation (11 October 2026)

The current hosted app suite passed all 134 tests with zero failures. This includes
13 Dot persistence/OAuth/protocol tests, eight scroll-state tests and three panel
geometry tests. The universal local Release build succeeded and its native Dot
button and chat panel were exercised on this Mac. The relay passed 27 Workers
runtime tests, type checks and production builds. Browser testing found and fixed
a consent CSP that blocked the intended GitHub redirect; browser consent remains
bound to the initiating browser and exact owner.

The personal relay is deployed and reports configured:true. Live OAuth discovery
and a bounded protocol consent-to-GitHub redirect check succeeded. These are not
a real Dot exchange. Native owner sign-in and the private ChatGPT plugin
authentication completed successfully in Safari; the notch shows Relay connected.
The plugin exposes both tools and notch.message.created. The authenticated readiness tool was deployed and verified in the refreshed
plugin catalog. The actual Dot reported a repeated task-service failure while
creating its subscription, so no active subscription or real notch reply was
confirmed. Send remains disabled, and the real test text is an unsent local draft.
Native Shift–Return inserted a newline; Escape dismissed the panel, and the
multiline draft survived reopening. Plugin persistent offline access was not
granted; one-hour plugin access and reconnect recovery remain acceptance gaps. A native UI scroll check moved the Agents
scrollbar from 0 to 0.2427 and back to 0 without closing the notch.
Physical trackpad/momentum, external displays and screen
lock remain direct-Mac acceptance checks. Explicit callback DNS/IP connection
pinning remains an acknowledged relay platform limitation.
