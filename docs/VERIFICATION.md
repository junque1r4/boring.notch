# Phase 1 verification — updated 12 October 2026

Base: TheBoredTeam/boring.notch tag `v2.8-rc.2`, commit
`1fa326d` (latest published pre-release verified through GitHub's release API).
Fork: https://github.com/junque1r4/boring.notch. Work branch: `agents/phase-1`.

Validated on this Apple silicon Mac using Xcode 27.0 (27A266a), Swift 6.4,
installed Codex CLI 0.144.6 and Codex Desktop 26.1007.21159.

| Requirement | Evidence and boundary |
| --- | --- |
| Original feature preservation | Baseline app built before edits; all 102 inherited app tests pass. Home, Shelf, media controls and battery UI remain present. Live now-playing appeared in the notch. Full camera/calendar/notification/OSD and hardware regression coverage is not claimed. |
| Agents tab | Native UI inspected and visually checked in the expanded notch; Home, Shelf and Agents buttons accessible. Agent Center also opens from the app menu and ⇧⌘A. |
| Agent tab refinements | The 12 October dashboard uses prominent weekly USED percentages and bars, reset/stale labels, and a 12-week local session-activity calendar. Empty dates are labeled unknown; history is deduplicated and bounded. The 640×440 notch layout keeps usage and activity summaries visible while filters and session rows share one scroll area. Hosted render coverage derives its content height from the actual notch size and checks a second session row with an alert present. Agents quota popups retain the notch's existing popover hold. |
| Quotas | Sandboxed release automatically displayed real Codex weekly allowance and Grok Bot weekly cache with no saved folder grants. ChatGPT's weekly USED card selects Weekly even when a five-hour primary exists; a missing weekly window is unavailable, never replaced with five-hour usage. Synthetic two-window quotas, reset details and filters verified. Unknown/malformed/future values, passed resets, ambiguous Grok accounts and obsolete secondary windows tested. ChatGPT chat limits and Grok Build CLI quota are not covered. |
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
before app entry. A direct test launch passed all 110 tests at the time of the
10 October verification. The final local Release
launches normally; this was a test-host issue, not a monitoring failure.
`scripts/test-agents-local.sh ../DerivedData` creates a temporary direct-launch
validation scheme (no debugger/Main Thread Checker/Thread Performance Checker,
`ENABLE_DEBUG_DYLIB=NO`), runs all inherited and Agents tests, then removes the
scheme. It changes no OS security settings and leaves the normal shared scheme
unchanged. Set `TEST_RUNNER_AGENTS_TEST_RENDER_DIR=1` for synthetic screenshots in
the test app's temporary `AgentMonitorValidation` folder.

Standalone checks: `swift test` and `python3 integrations/codex/test_notch_hook.py`.
The 12 October results are recorded below; these counts describe the earlier
10 October run.

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

## Current UI and live-state check (12 October 2026)

The rebuilt app visibly has Home, Shelf, Agents Status and Dot tabs, a robot
Agents icon and the owner's original Dot avatar. Dot is embedded in the same
notch, up to 760×450 points. Weekly USED bars show source/reset/freshness details;
the 12-week local activity calendar labels missing records unknown.

The latest full hosted suite passed **139 tests**, including 18 Dot tests, with
zero failures. The monitoring core passed 20 tests, the relay passed 31 runtime
tests plus type checks, and the hook adapter passed four tests. Universal local
Release builds succeeded. Counts in the earlier dated sections are historical.

A real message sent with Return in the native notch was read by the actual Dot
through its private plugin. Dot sent “Notch connection verified. 7 plus 5 is 12.”
through `notch_reply`, and that reply was visibly rendered inside the notch.
That first exchange required a diagnostic prompt in Safari.

A second native test was accepted by the genuine ChatGPT callback with HTTP 200
on its first attempt (12 October 2026, 07:59:31 UTC). Dot reapplied the exact
event binding; a third native test was also accepted on its first attempt at
08:03:33 UTC. The third test then received the actual Dot reply automatically:
“Event delivery works. 6 plus 8 is 14.” It arrived after several minutes without
a manual handling prompt for that message. The earlier no-run condition therefore
does not describe the refreshed binding. Dot reported that its wake-up omitted
the payload and recovered the originating ID through private diagnostics.
Callback acceptance is deliberately distinct from processing/reply. Private
bounded diagnostics retain UUID/status/time only; no message content or callback
secret/path/response body is exposed. The verified callback origin is pinned to
`https://connectors.api.openai.com`.

Live Mac checks: Agents scrolling moved its scrollbar from 0 to 0.2797 and back
to 0 without closing; usage popup opened and dismissed; Return sent; Shift–Return
inserted a newline; Escape closed Dot; the two-line draft survived reopening and
tab changes. Native credentials and the pending message survived a restart after
the owner allowed the macOS Keychain prompt. Ad-hoc rebuilds can require the
owner to approve Keychain access again.

An incoming automatic reply preserved the older-message scroll position and
showed an unread badge/new-replies prompt; scrolling to the bottom cleared it.
A bounded metadata-only pending-message queue was added for missing-payload
recovery. A fourth native message sent at 08:18:33 UTC triggered automatic
recovery: Dot answered the older unanswered test first, then replied
“Queue recovery verified. 11 plus 6 is 17.” Both replies were visible inside
the notch, with two unread replies shown while Agents Status was selected.
The authenticated pending queue was empty afterward. No manual handling prompt
was sent for this fourth test, and no duplicate replies were observed.
This establishes one automatic backlog recovery, not long-term reliability.

Still unverified: sustained subscription/token renewal, physical trackpad
momentum, external displays, screen lock and complete notification/focus/IME
regression behavior. This remains a local development build, not a
Developer ID signed/notarized public release. Existing callback TLS pinning and
upstream helper/framework boundaries documented above remain.

## 12 October 2026 — Chat polish and latency benchmark

- 143 hosted macOS tests passed, zero failures, including pin lifecycle, Home
  isolation, Markdown block parsing and unsafe-link removal. Evidence:
  `work/DotPolishVerifiedTests-20261012.xcresult` and
  `work/dot-polish-tests-verified.log` in the parent delivery workspace.
- Universal local Release rebuilt successfully; codesign verification passed.
- Real automatic reply after the task-prompt cleanup: 111.680 seconds from relay
  creation to stored response. Callback acceptance took 0.985 seconds; actual Dot
  reported a wake about 64 seconds after callback acceptance. A direct native-Dot
  fixed-text baseline was observed complete within 18.5 seconds. Native parity
  remains unmet. Full evidence and interpretation: [DOT-LATENCY.md](DOT-LATENCY.md).
- On the Mac, verified dated message grouping, reply avatars, times, double reply
  ticks, formatted numbered lists, removed byte/keyboard hints and Return send.
  Pinned chat remained open after clicking Safari. Escape explicitly dismissed
  it and reopening showed the pin cleared. Scrolling to the first and last
  messages left the chat open. Pending/reply content survived reopening.
- No complete original Dot animation bundle was found. The original personal
  avatar remains unchanged; Codex pet animations were not substituted.
- Screen lock, multiple displays, physical trackpad momentum and full IME/focus
  regression remain the previously documented live-hardware limits. Pinning does
  not override explicit close/tab selection or screen lock.

## 12 October 2026 — Adaptive bubble layout refinement

- Universal local Release rebuilt successfully after changing only the chat view.
  The build script verified the app signature; `git diff --check` passed.
- Live Mac inspection confirmed short outgoing messages and short replies shrink
  to their content; longer paragraphs and numbered lists wrap at the width cap.
  The original Dot avatar is horizontally centered within the actual reply bubble.
  Timestamps and receipt marks remain inside the 14pt horizontal/12pt vertical
  padding. Scrolling between short and long messages kept the pinned chat open.
- The supplied native-chat reference was converted from its embedded color
  profile to sRGB: outgoing #FFCC39, reply #F0F0F0, text #0D0D0D.
- Screenshot: `outputs/Dot-chat-adaptive-bubbles.jpg` in the parent delivery
  workspace. This visual-only refinement did not rerun the earlier 143-test suite
  or change/benchmark the relay. Earlier latency and hardware limits still apply.

## 12 October 2026 — Closed-notch Dot shortcut and stable signing

- Universal Release built and codesign verification passed. The closed notch now
  has an original-avatar shortcut with a black background overlapping its curved
  right edge by 20pt, with a separate 36pt input region and balanced layout.
- Live Mac: clicking the closed shortcut opened Dot directly and focused the
  composer. A real test message received “Dot shortcut ready”; while chat was
  closed the shortcut showed a 1 badge. The badge survived an app restart, then
  cleared after opening the reply. The seam-free closed state and unread badge
  were captured in outputs/Dot-closed-shortcut.jpg and Dot-shortcut-unread.jpg
  in the parent delivery workspace.
- Replaced ad-hoc signing with the available Apple Development certificate.
  Verified the designated requirement is certificate/bundle based and identical
  before and after a code-changing rebuild. After the owner approved migration
  access, the changed build launched in about two seconds, restored encrypted
  history and relay sign-in, and opened chat without a further Keychain prompt.
- Both Keychain items remain protected: OAuth credentials and local history key.
  No secret export, item deletion or blanket Keychain access was used. Certificate
  replacement, revocation or a new signing identity can require approval again.
- This is a development-signed local build, not notarized. Earlier physical
  trackpad, display, screen-lock and long-term relay limits remain open. The
  earlier automated test suite was not rerun for this view/signing-only change.
