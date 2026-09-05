#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "renderer_report", Path(__file__).parents[1] / "harness/renderer-report.py")
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


def window(end, seconds=1, fps=120, zone=235):
    return {"epoch": end, "seconds": seconds, "frames": fps * seconds, "fps": fps,
            "zone": zone, "p99_ms": 10, "max_ms": 20, "jit_enabled": 0}


class RendererReportTests(unittest.TestCase):
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
