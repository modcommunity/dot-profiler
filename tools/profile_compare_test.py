#!/usr/bin/env python3
"""Checks profile_compare.py's sections and --diff noise floor: python3 tools/profile_compare_test.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import profile_compare as pc  # noqa: E402

A = {"frames": 10, "p50_ms": 10.0, "phases": {}, "systems": [{"system": "bots", "ms_per_frame": 2.0}, {"system": "hud", "ms_per_frame": 1.0}],
     "monitors": {"draw_calls": {"avg": 1000.0}},
     "groups": [{"group": "bots", "count": {"avg": 32.0}, "systems": [{"system": "arena.bot_brain", "us_per_unit": 50.0}]}],
     "script_functions": {"functions": [{"function": "think", "script": "res://brain.gd", "line": 3, "self_ms": 1.0}]}}
B = {"frames": 10, "p50_ms": 10.2, "phases": {}, "systems": [{"system": "bots", "ms_per_frame": 2.5}, {"system": "hud", "ms_per_frame": 1.02}],
     "monitors": {"draw_calls": {"avg": 1200.0}},
     "groups": [{"group": "bots", "count": {"avg": 32.0}, "systems": [{"system": "arena.bot_brain", "us_per_unit": 60.0}]}],
     "script_functions": {"functions": [{"function": "think", "script": "res://brain.gd", "line": 3, "self_ms": 1.3}]}}


class CompareTest(unittest.TestCase):
    def test_sections(self):
        names = {(s, n) for s, n, _, _ in pc.compare(A, B, 0.05)}
        self.assertIn(("group", "bots us/unit arena.bot_brain"), names)
        self.assertIn(("script", "think brain.gd:3"), names)
        self.assertIn(("monitor", "draw_calls"), names)

    def test_noise_floor(self):
        moved = {(s, n) for s, n, _, _ in pc.changed(pc.compare(A, B, 0.05))}
        self.assertIn(("system", "bots"), moved)
        self.assertNotIn(("system", "hud"), moved)
        self.assertNotIn(("frame", "p50"), moved)
        self.assertEqual(pc.changed(pc.compare(A, B, 0.05), 50.0), [])

    def test_cli_diff(self):
        with tempfile.TemporaryDirectory() as d:
            pa, pb = os.path.join(d, "a.json"), os.path.join(d, "b.json")
            for p, r in ((pa, A), (pb, B)):
                with open(p, "w", encoding="utf-8") as f:
                    json.dump(r, f)
            tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), "profile_compare.py")
            out = subprocess.run([sys.executable, tool, pa, pb, "--diff", "--json"], capture_output=True, text=True, check=True).stdout
            rows = json.loads(out)
            self.assertTrue(rows and all(abs(r["delta"]) * 100 / abs(r["a"]) >= 5 for r in rows if r["a"]))
            self.assertNotIn("hud", [r["name"] for r in rows])


if __name__ == "__main__":
    unittest.main()
