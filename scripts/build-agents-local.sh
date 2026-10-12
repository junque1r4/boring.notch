#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Local development build; sandbox retained, no notarization claim.
set -eu
task_repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_build_dir=${1:-"$task_repo_root/build/AgentsLocal"}
# Ad-hoc signatures identify the binary hash, so each rebuild invalidates the
# Keychain's remembered app identity. Prefer a persistent certificate instead.
task_signing_identity=${BORING_NOTCH_SIGNING_IDENTITY:-}
if [ -z "$task_signing_identity" ]; then
  task_signing_identities=$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) .*/\1/p')
  task_identity_count=$(printf '%s\n' "$task_signing_identities" | awk 'NF { n++ } END { print n+0 }')
  if [ "$task_identity_count" != 1 ]; then
    printf '%s\n' 'Select a stable certificate with BORING_NOTCH_SIGNING_IDENTITY. Set it to - only for an explicitly ad-hoc build (repeated Keychain prompts).' >&2
    exit 1
  fi
  task_signing_identity=$task_signing_identities
fi
xcodebuild -project "$task_repo_root/boringNotch.xcodeproj" -scheme boringNotch \
  -configuration Release -derivedDataPath "$task_build_dir" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$task_signing_identity" \
  DEVELOPMENT_TEAM="${BORING_NOTCH_DEVELOPMENT_TEAM:-}" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_HARDENED_RUNTIME=NO build
codesign --verify --deep --strict "$task_build_dir/Build/Products/Release/Boring Notch Agents.app"
