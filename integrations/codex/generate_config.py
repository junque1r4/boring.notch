#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Print a mergeable hooks.json fragment; never edit user configuration."""
import json
from pathlib import Path
import shlex

script = Path(__file__).with_name("notch_hook.py").resolve()
events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"]
command = "/usr/bin/python3 " + shlex.quote(str(script))
print(json.dumps({"hooks": {event: [{"hooks": [{"type": "command", "command": command, "timeout": 1}]}] for event in events}}, indent=2))
