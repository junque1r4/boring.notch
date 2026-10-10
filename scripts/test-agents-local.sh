#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Run the complete hosted suite with a direct test launch. This avoids a
# local macOS 27/Xcode 27 debugger/checker loader stall; no OS setting changes.
set -eu
task_repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_build_dir=${1:-"$task_repo_root/build/AgentsTests"}
if [ "$#" -gt 0 ]; then shift; fi
task_scheme_path="$task_repo_root/boringNotch.xcodeproj/xcshareddata/xcschemes/AgentsLocalValidation.xcscheme"
if [ -e "$task_scheme_path" ]; then
  echo 'A validation scheme already exists. Remove or rename it before running this script.' >&2
  exit 1
fi
trap 'rm -f "$task_scheme_path"' EXIT HUP INT TERM
python3 - "$task_repo_root" "$task_scheme_path" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
s=(root/'boringNotch.xcodeproj/xcshareddata/xcschemes/boringNotch.xcscheme').read_text()
s=s.replace('selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB"','selectedDebuggerIdentifier=""')
s=s.replace('selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"','selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn"')
for tag in ['TestAction','LaunchAction']:
    s=s.replace('<'+tag+' ', '<'+tag+' disableMainThreadChecker="YES" disableThreadPerformanceChecker="YES" ')
pathlib.Path(sys.argv[2]).write_text(s)
PY
xcodebuild -project "$task_repo_root/boringNotch.xcodeproj" -scheme AgentsLocalValidation \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath "$task_build_dir" \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_DEBUG_DYLIB=NO test "$@"
