#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Local ad-hoc build: sandbox retained; no Developer ID/notarization claim.
set -eu
task_repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_build_dir=${1:-"$task_repo_root/build/AgentsLocal"}
xcodebuild -project "$task_repo_root/boringNotch.xcodeproj" -scheme boringNotch \
  -configuration Release -derivedDataPath "$task_build_dir" \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_HARDENED_RUNTIME=NO build
codesign --verify --deep --strict "$task_build_dir/Build/Products/Release/Boring Notch Agents.app"
