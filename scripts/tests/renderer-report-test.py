#!/usr/bin/env python3
import importlib.util
import csv
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "renderer_report", Path(__file__).parents[1] / "harness/renderer-report.py")
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


def window(end, seconds=1, fps=120, zone=235):
    return {"epoch": end, "seconds": seconds, "frames": fps * seconds, "fps": fps,
            "zone": zone, "p99_ms": 10, "max_ms": 20, "jit_enabled": 0}


class RendererReportTests(unittest.TestCase):
    def test_clock_and_zone_setup_fail_before_a_scene_can_be_accepted(self):
        marker = {"label": "city settled", "zone": 235, "epoch": 136,
                  "world_distance": 20, "entity_distance": 20,
                  "vana_hour": 12, "vana_minute": 15}
        self.assertIsNone(report.world_scene_problem(marker, 20, 100))
        self.assertIn("expected zone", report.world_scene_problem({**marker, "zone": 234}, 20, 100))
        self.assertIn("noon scenario", report.world_scene_problem({**marker, "vana_hour": 16}, 20, 100))
        self.assertIn("not recorded", report.world_scene_problem({**marker, "vana_hour": None}, 20, 100))

    def fixture(self, root, distances, counters=True):
        session = root / "session"
        session.mkdir()
        (root / "active.json").write_text(json.dumps({"session": str(session)}))
        (root / "result.json").write_text('{"exit_code": 0}')
        (root / "restoration.json").write_text(
            '{"docker_unchanged": true, "preferences_restored": true}')
        (session / "menu-run.json").write_text(json.dumps({
            "renderer_verified": {"d3d9.dll": "fixture"}, "leftover_processes": [],
            "draw_distance_requested": 10}))
        markers = [{"label": "city settled", "epoch": 10, "zone": 235, **distances},
                   {"label": "zone bastok mines", "epoch": 30, "zone": 235}]
        (session / "perfscene-markers.jsonl").write_text(
            "\n".join(json.dumps(marker) for marker in markers))
        if counters:
            with (session / "common-fps.csv").open("w") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(window(0)))
                writer.writeheader()
                writer.writerows(window(i) for i in range(13, 31))

    def test_effective_distance_must_match_both_requested_values(self):
        for distances, valid in [({"world_distance": 10, "entity_distance": 10}, True),
                                 ({"world_distance": 20, "entity_distance": 10}, False),
                                 ({"world_distance": 10}, False)]:
            with self.subTest(distances=distances), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root, distances)
                result = report.report(root)
                self.assertEqual(result["problems"], [])
                self.assertEqual(result["scenes"][0]["valid"], valid)
                if not valid:
                    self.assertIn("effective draw distance", result["scenes"][0]["reason"])

    def test_failed_launch_without_counters_still_has_a_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, {}, counters=False)
            (root / "result.json").write_text('{"exit_code": 6}')
            result = report.report(root)
            self.assertEqual(result["scenes"], [])
            self.assertEqual(len(result["problems"]), 2)
            self.assertIn("no frame-counter data", result["problems"][-1])

    def test_disabled_menu_samples_do_not_create_invalid_intervals(self):
        events = [{"label": "menu sample start", "scene": "rules", "epoch": 1},
                  {"label": "menu sample end", "scene": "rules", "epoch": 1.001}]
        self.assertEqual(report.intervals({"events": events}, []), [])

    def test_duration_weights_rate_and_excludes_boundary_and_other_zone(self):
        rows = [window(i) for i in range(1, 11)] + [window(12, 2, 60),
                window(12, 1, 9999, 0), window(13, 2, 9999)]
        result = report.summarize(rows, 0, 12, 235)
        self.assertTrue(result["valid"])
        self.assertEqual(result["fps"], 110)
        self.assertEqual(result["windows"], 11)
        self.assertEqual(result["percent_time_below_120"], 16.67)

    def test_missing_and_frozen_counter_windows_invalidate_sample(self):
        rows = [window(i) for i in range(1, 21)]
        for changed in (rows[:-3], rows[3:], rows[:5] + rows[8:]):
            self.assertFalse(report.summarize(changed, 0, 20, 235)["valid"])

    def test_world_intervals_stop_at_next_marker_and_require_expected_zone(self):
        phases = report.intervals({}, [
            {"label": "city settled", "epoch": 10, "zone": 106},
            {"label": "zone bastok mines", "epoch": 30, "zone": 106}])
        self.assertEqual(phases[0]["start"], 12)
        self.assertEqual(phases[0]["end"], 30)
        self.assertEqual(phases[0]["zone"], 235)
        self.assertFalse(report.summarize([window(i, zone=106) for i in range(13, 31)],
                                         12, 30, 235)["valid"])


if __name__ == "__main__":
    unittest.main()
