#!/usr/bin/env python3
"""Offline regression tests: python -m unittest discover -s this-directory."""
import subprocess
import unittest
from unittest.mock import patch

import trigger_probe


class PreflightTests(unittest.TestCase):
    def preflight_with(self, stdout, stderr="", returncode=0):
        result = subprocess.CompletedProcess([], returncode, stdout, stderr)
        with patch.object(trigger_probe.subprocess, "run", return_value=result):
            with patch.object(trigger_probe, "neutral_cwd", return_value="."):
                return trigger_probe.preflight(None)

    def test_accepts_ready_stdout(self):
        for answer in ("READY", "ready\n", "\nREADY\n"):
            with self.subTest(answer=answer):
                self.assertEqual(self.preflight_with(answer), (True, ""))

    def test_benign_stderr_does_not_hide_ready_answer(self):
        self.assertEqual(
            self.preflight_with("READY\n", "Warning: update available\n"),
            (True, ""),
        )

    def test_rejects_nonzero_exit_even_with_ready_stdout(self):
        ok, _ = self.preflight_with("READY\n", returncode=1)
        self.assertFalse(ok)

    def test_stderr_cannot_supply_ready_answer(self):
        ok, reason = self.preflight_with("", "Error: model is not READY\n")
        self.assertFalse(ok)
        self.assertIn("model is not READY", reason)

    def test_rejects_ready_substring_in_unrelated_output(self):
        for output in ("Already running", "Model is not ready"):
            with self.subTest(output=output):
                ok, reason = self.preflight_with(output)
                self.assertFalse(ok)
                self.assertEqual(reason, output)


if __name__ == "__main__":
    unittest.main()
