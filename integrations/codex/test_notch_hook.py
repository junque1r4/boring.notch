# SPDX-License-Identifier: GPL-3.0-only
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("hook", Path(__file__).with_name("notch_hook.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
ID = "11111111-2222-3333-4444-555555555555"


class HookTests(unittest.TestCase):
    def test_lifecycle_and_privacy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "bridge"
            for event, expected in hook.STATES.items():
                hook.write_status({"session_id": ID, "hook_event_name": event, "cwd": "/private/project",
                                   "prompt": "SECRET", "tool_input": "SECRET", "last_assistant_message": "SECRET"}, root)
                raw = (root / (ID + ".json")).read_text()
                self.assertNotIn("SECRET", raw)
                self.assertNotIn("/private", raw)
                self.assertEqual(json.loads(raw)["state"], expected)
                self.assertEqual((root / (ID + ".json")).stat().st_mode & 0o777, 0o600)
            hook.write_status({"session_id": ID, "hook_event_name": "SessionEnd"}, root)
            self.assertFalse((root / (ID + ".json")).exists())

    def test_rejects_symlink_and_path_injection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            link = root / "link"
            link.symlink_to(root, target_is_directory=True)
            with self.assertRaises(ValueError):
                hook.write_status({"session_id": ID, "hook_event_name": "Stop"}, link)
            with self.assertRaises(ValueError):
                hook.write_status({"session_id": "../../evil", "hook_event_name": "Stop"}, root)

    def test_does_not_treat_tool_errors_as_session_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            hook.write_status({"session_id": ID, "hook_event_name": "PostToolUse", "tool_response": {"exit_code": 1}}, root)
            self.assertEqual(json.loads((root / (ID + ".json")).read_text())["state"], "working")

    def test_compaction_does_not_change_an_active_turn_to_waiting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            hook.write_status({"session_id": ID, "hook_event_name": "UserPromptSubmit"}, root)
            hook.write_status({"session_id": ID, "hook_event_name": "SessionStart", "source": "compact"}, root)
            self.assertEqual(json.loads((root / (ID + ".json")).read_text())["state"], "working")


if __name__ == "__main__":
    unittest.main()
