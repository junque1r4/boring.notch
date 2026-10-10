# Boring Notch Agents — Phase 1

Modified 10 October 2026 by the junque1r4 fork. Based on the latest published
pre-release at implementation time, [v2.8-rc.2](https://github.com/TheBoredTeam/boring.notch/releases/tag/v2.8-rc.2).
This fork and its modifications remain GPL-3.0-only. Original notices, LICENSE,
THIRD_PARTY_LICENSES and contributor credits are preserved.

## Start

Build and launch **Boring Notch Agents.app**. Choose the **Agents** tab in the
expanded notch, or **Agents → Open Agent Center** (⇧⌘A) in the app menu.
The menu-bar Agents item also opens the center in compact player mode, which
retains the original player-only layout.

Monitoring is off by default. The app asks you to choose folders and saves
read-only security-scoped bookmarks. Disconnect revokes its saved bookmark,
releases access, and clears the displayed session cache. It does not change Codex.

### Optional local session-log adapter

Choose `~/.codex/sessions` with **Choose session logs**. Hidden folders are
visible in the picker; ⇧⌘G can enter the path. Choose the `sessions` directory
under your actual `CODEX_HOME` if customized.

The adapter observes Desktop and CLI logs from the last 24 hours, up to 80
recent files. It reads a bounded header and tail, caches unchanged files,
then reads appended records so a long turn keeps its observed state. A partial
JSON record may be buffered briefly in memory, up to 1 MiB, until its next write.
The append budget is 1 MiB per poll; exceeding it resets the old state to Unknown
and rechecks the bounded tail instead of carrying a status across an unread gap.
It rejects symlinks escaping the grant, tolerates partial writes, and keeps only
session ID, project directory name, origin, lifecycle state, turn ID and time.
JSON records may briefly contain other fields while decoding, but those fields
are never retained in the model, logged, persisted or transmitted by monitoring.
The maximum traversal is 20,000 entries; a diagnostic reports reaching that limit.

**This is an optional compatibility adapter, not an official status API.**
Codex explicitly documents that transcript formats can change. Unrecognized
events are ignored; unknown states stay Unknown. Changes in format can reduce
coverage. Archived, remote/cloud-only, older and inaccessible sessions are not
observed. Desktop origin is identified only from explicit metadata. CLI origin
requires `source: cli`; other origins remain generic Codex.

### Documented Codex hooks

The observer in `integrations/codex/notch_hook.py` accepts Codex's documented
hook input on stdin. It writes metadata-only JSON files to
`~/.codex/notch-agent-status`, using owner-only permissions, a per-session lock
and atomic replacement. It never returns an approval decision, changes a prompt,
blocks a tool or sends network traffic. Errors return an empty JSON object so
monitoring cannot stop Codex. Hook trust still belongs to Codex.

1. Keep the script in a stable checkout location.
2. Run `python3 integrations/codex/generate_config.py` from the checkout to
   print a hooks.json fragment with its absolute, shell-quoted script path.
3. Merge those entries into your existing Codex hooks configuration, preserving
   existing hooks. Follow [official hook setup and trust review](https://learn.chatgpt.com/docs/hooks).
   The generator does not install or trust hooks, or overwrite configuration.
4. Review and trust the observer using Codex's normal mechanism, then start a
   new turn. Hooks may be unavailable or restricted by your Codex version or
   managed policy; the app does not bypass those restrictions.
5. Choose `~/.codex/notch-agent-status` in **Choose hook bridge** after it exists.

For a custom bridge path, set `BORING_NOTCH_AGENT_DIR` in the Codex environment,
and select the same folder in the app. The directory must belong to your user
with mode 0700. Files are mode 0600. Do not place it in a shared or synced folder.

Hook behavior and available surfaces vary by client. A hook event alone does
not identify Desktop versus CLI, so the UI shows Codex unless matching local
session metadata establishes the origin. Both adapters deduplicate by session
ID; the newer observation wins and a hook wins tied timestamps.

## State and alert semantics

| State | Evidence |
| --- | --- |
| Working | Turn start in local logs; prompt/tool hooks |
| Waiting | Session start, PermissionRequest or Interrupt hook; aborted turn in logs |
| Completed | Stop hook or explicit turn completion in logs |
| Failed | Explicit task_failed/turn_failed lifecycle log event only |
| Unknown | No recognized lifecycle event available |

Completed means the **turn ended**, not that the requested objective succeeded.
Waiting does not always mean an approval is pending. Tool exit codes and assistant
prose never imply failure. The hook API does not establish a terminal session
failure, so hooks alone cannot supply Failed. The log failure mappings are
defensive compatibility mappings; a real Failed emission was not observed
on the installed client.

Working, Waiting and Unknown observations older than ten minutes carry a
**Stale** badge. There is no process-liveness claim and no automatic success/failure
inference. Polling runs every three seconds. The first snapshot is silent;
new, fresh attention/completion/failure transitions produce an in-app alert.
macOS alerts are opt-in and depend on notification permission, Focus settings
and OS delivery. Alerts omit project names, paths and conversation content.
Repeated session/turn/state alerts are deduplicated, with at most five per poll.

Compaction SessionStart hooks are ignored so they do not mark an active turn
Waiting. A Stop hook is an observation of a stop attempt: another hook may
request a continuation, which is reflected by later prompt/tool activity.
Subagent tool hooks can use their parent's session ID, so hook-based Working
and Waiting observations may include activity in that parent's subagents.

## Navigation and approvals

Desktop sessions use `codex://threads/<UUID>` only when the registered handler
has the verified Codex bundle ID `com.openai.codex`.
The installed app's scheme registration has been verified; individual thread
routing remains version dependent. The UI reports that limit. Missing handlers
fall back to copying the CLI resume command.

CLI and unidentified sessions copy `codex resume <UUID>` for the user to run in
their terminal. Phase 1 does not focus an already-running terminal session or
launch shell commands. IDs must be UUIDs, so log text cannot inject a URL or
shell command. Folder grants do not authorize commands or approval decisions.

**Approve/deny controls are intentionally absent.** Approval and attention actions
remain in Codex. [Codex App Server](https://learn.chatgpt.com/docs/app-server)
supports status and approval protocols for a client connected to a server it
owns or is authorized to access; starting a new server does not expose the live
status or approval channel of an existing Desktop/CLI process. This milestone
does not attach to private sockets or read auth.json, keychains or state databases.

## Extend

`AgentSessionProvider` is the read-only integration seam. Each provider returns
`AgentSnapshot` values; the monitor handles merging, ordering, alerts and UI.
Core code depends only on Foundation and has a standalone Swift package test
target. Provider work runs in actors off the main UI actor. Add another provider
without changing media, calendar, shelf, camera, battery or notification managers.
Control capabilities need a separate supported API and authorization model.

## Build and license

Requires macOS 14+ and Xcode with the upstream package dependencies.

```sh
swift test
python3 integrations/codex/test_notch_hook.py
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
sh scripts/build-agents-local.sh
```

The fork has its own app/helper bundle IDs and product name so it can coexist
with upstream. Sparkle stays stopped and the upstream feed/signing key are removed
to prevent an original-app update from replacing this fork. Existing upstream
feature code is preserved; tabs are always available in the full layout, with
Shelf still conditional on its setting. Automatic upstream updates are the
intentional compatibility exception. The original update settings are inactive.

When conveying a binary, provide the matching Corresponding Source, including
modified files, build instructions, dependency lockfile, resources, license and
notices, under GPL-3.0; preserve third-party licenses. Do not imply upstream
endorsement. Ad-hoc builds are local development artifacts, not notarized public
releases. A future public release needs an independent signing/update pipeline.

The local build script retains App Sandbox but disables Hardened Runtime for
the ad-hoc build: without a Developer ID team identity, library validation rejects
the inherited MediaRemoteAdapter framework at launch. No system protection is
changed. Public distribution must use proper signing of the app and embedded
frameworks, Hardened Runtime and notarization. The inherited framework also
reports a newer macOS build target, so macOS 14–26 compatibility is unverified.
