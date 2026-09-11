#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "launch_report", Path(__file__).parents[1] / "harness/launch-report.py")
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


class LaunchReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.session = self.root / "capture"
        self.session.mkdir()
        self.write(self.root / "active.json", {"session": str(self.session)})
        self.write(self.root / "result.json", {"exit_code": 0})
        self.restoration = {"preferences_restored": True, "docker_unchanged": True,
                            "related_processes": [], "files_restored": 44}
        self.run = {"launch_requested_epoch": 100, "injector_spawn_epoch": 102,
                    "prefix_update_epoch": 90,
                    "first_window": {"epoch": 115, "launch_seconds": 15,
                                     "poll_interval_seconds": 0.2},
                    "renderer_verified": {key: "a" * 64 for key in
                        ("d3d8.dll", "d3d9.dll", "mtld3d.dll", "mtld3d.so")},
                    "credentials": "private fixture"}
        (self.session / "launcher.log").write_text(
            "unrelated private fixture\nlaunch timing: prepare elapsed=0 epoch=101.000\n"
            "launch timing: spawn elapsed=0.500 epoch=101.500\n")

    @staticmethod
    def write(path, value):
        path.write_text(json.dumps(value))

    def summarize(self):
        self.write(self.session / "menu-run.json", self.run)
        self.write(self.root / "restoration.json", self.restoration)
        return report.summarize(self.root)

    def test_timings_and_allowlisted_output(self):
        self.restoration["private_path"] = "private fixture"
        self.run["renderer_verified"]["private_path"] = "private fixture"
        value = self.summarize()
        self.assertTrue(value["valid"])
        self.assertEqual(value["preparation_seconds"], 0.5)
        self.assertEqual(value["prepare_to_window_seconds"], 14)
        self.assertEqual(value["request_to_spawn_seconds"], 2)
        self.assertEqual(value["spawn_to_window_seconds"], 13)
        self.assertFalse(value["wine_prefix_updated_during_launch"])
        self.assertNotIn("private fixture", json.dumps(value))

    def test_failed_restoration_or_invalid_renderer_rejects_result(self):
        self.restoration["docker_unchanged"] = False
        self.assertFalse(self.summarize()["valid"])
        self.restoration["docker_unchanged"] = True
        self.run["renderer_verified"]["mtld3d.so"] = "not-a-hash"
        self.assertFalse(self.summarize()["valid"])
        self.run["renderer_verified"] = True
        self.assertFalse(self.summarize()["valid"])

    def test_missing_window_is_invalid_without_crashing(self):
        self.run.pop("first_window")
        value = self.summarize()
        self.assertFalse(value["valid"])
        self.assertNotIn("spawn_to_window_seconds", value)


if __name__ == "__main__":
    unittest.main()
